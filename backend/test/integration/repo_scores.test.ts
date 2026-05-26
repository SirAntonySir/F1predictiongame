import { describe, it, expect } from 'vitest'
import * as users from '../../src/repo/users.js'
import * as seasons from '../../src/repo/seasons.js'
import * as events from '../../src/repo/events.js'
import * as sessions from '../../src/repo/sessions.js'
import * as leagues from '../../src/repo/leagues.js'
import * as members from '../../src/repo/leagueMembers.js'
import * as scores from '../../src/repo/scores.js'

async function seedSessions(count = 2) {
  await seasons.upsertSeason({ year: 2026, isCurrent: true })
  const ev = await events.upsertEvent({
    seasonYear: 2026, round: 1, name: 'Bahrain', circuitName: 'BIC', country: 'Bahrain', hasSprint: false
  })
  const out = []
  const types: ('race' | 'qualifying')[] = ['qualifying', 'race']
  for (let i = 0; i < count; i++) {
    const s = await sessions.upsertSession({
      eventId: ev.id, type: types[i % 2]!,
      scheduledStart: new Date(2026, 0, 1 + i),
      scheduledEnd: new Date(2026, 0, 1 + i, 2),
      status: 'scheduled',
    openf1SessionKey: null
    })
    out.push(s)
  }
  return { event: ev, sessions: out }
}

function breakdown(points: number) {
  return {
    perPosition: [{ position: 1, exact: true, wrongPos: false, points }],
    teamBonus: { applied: false, points: 0 },
    rule: 'test-v1'
  }
}

describe('scores repo', () => {
  it('upsert overwrites existing row', async () => {
    const { sessions: ss } = await seedSessions(1)
    const u = await users.insertUser({ email: 'a@x.com', passwordHash: 'h', displayName: 'A' })
    await scores.upsertScore(u.id, ss[0]!.id, 5, breakdown(5))
    await scores.upsertScore(u.id, ss[0]!.id, 12, breakdown(12))
    const list = await scores.listForUser(u.id, 2026)
    expect(list).toHaveLength(1)
    expect(list[0]!.pointsTotal).toBe(12)
  })

  it('league leaderboard sums per member', async () => {
    const { sessions: ss } = await seedSessions(3)
    const owner = await users.insertUser({ email: 'o@x.com', passwordHash: 'h', displayName: 'Owner' })
    const m1 = await users.insertUser({ email: 'm1@x.com', passwordHash: 'h', displayName: 'M1' })
    const m2 = await users.insertUser({ email: 'm2@x.com', passwordHash: 'h', displayName: 'M2' })
    const out = await users.insertUser({ email: 'out@x.com', passwordHash: 'h', displayName: 'Out' })
    const l = await leagues.createLeagueWithOwner({ name: 'L', ownerUserId: owner.id, joinCode: 'LBR001' })
    await members.add(l.id, m1.id)
    await members.add(l.id, m2.id)
    // owner gets points; m1 gets more points; m2 gets nothing; out (not a member) shouldn't appear
    await scores.upsertScore(owner.id, ss[0]!.id, 7,  breakdown(7))
    await scores.upsertScore(owner.id, ss[1]!.id, 3,  breakdown(3))
    await scores.upsertScore(m1.id,    ss[0]!.id, 17, breakdown(17))
    await scores.upsertScore(out.id,   ss[0]!.id, 99, breakdown(99))

    const lb = await scores.leagueLeaderboard(l.id, 2026)
    const byId = new Map(lb.map((r) => [r.userId, r]))
    expect(byId.size).toBe(3)  // owner + m1 + m2; out excluded
    expect(byId.get(owner.id)!.pointsTotal).toBe(10)
    expect(byId.get(owner.id)!.sessionsScored).toBe(2)
    expect(byId.get(m1.id)!.pointsTotal).toBe(17)
    expect(byId.get(m1.id)!.sessionsScored).toBe(1)
    expect(byId.get(m2.id)!.pointsTotal).toBe(0)
    expect(byId.get(m2.id)!.sessionsScored).toBe(0)
    // sort: desc by pointsTotal
    expect(lb[0]!.userId).toBe(m1.id)
  })

  it('leaderboard filters by season via event.season_year', async () => {
    await seasons.upsertSeason({ year: 2024, isCurrent: false })
    const ev2024 = await events.upsertEvent({
      seasonYear: 2024, round: 1, name: 'Old', circuitName: 'X', country: 'X', hasSprint: false
    })
    const old = await sessions.upsertSession({
      eventId: ev2024.id, type: 'race',
      scheduledStart: new Date(2024, 0, 1), scheduledEnd: new Date(2024, 0, 1, 2), status: 'scheduled',
    openf1SessionKey: null
    })
    const { sessions: ss } = await seedSessions(1)
    const owner = await users.insertUser({ email: 'o2@x.com', passwordHash: 'h', displayName: 'O' })
    const l = await leagues.createLeagueWithOwner({ name: 'L2', ownerUserId: owner.id, joinCode: 'LBR002' })
    await scores.upsertScore(owner.id, ss[0]!.id, 10, breakdown(10))
    await scores.upsertScore(owner.id, old.id, 100, breakdown(100))

    const lb2026 = await scores.leagueLeaderboard(l.id, 2026)
    expect(lb2026.find((r) => r.userId === owner.id)!.pointsTotal).toBe(10)

    const lb2024 = await scores.leagueLeaderboard(l.id, 2024)
    expect(lb2024.find((r) => r.userId === owner.id)!.pointsTotal).toBe(100)
  })

  it('listForUser returns scores with breakdown JSONB', async () => {
    const { sessions: ss } = await seedSessions(2)
    const u = await users.insertUser({ email: 'h@x.com', passwordHash: 'h', displayName: 'H' })
    await scores.upsertScore(u.id, ss[0]!.id, 5, breakdown(5))
    await scores.upsertScore(u.id, ss[1]!.id, 12, breakdown(12))
    const list = await scores.listForUser(u.id, 2026)
    expect(list).toHaveLength(2)
    expect(list[0]!.breakdown.rule).toBe('test-v1')
  })

  it('cascades from user delete', async () => {
    const { sessions: ss } = await seedSessions(1)
    const u = await users.insertUser({ email: 'c@x.com', passwordHash: 'h', displayName: 'C' })
    await scores.upsertScore(u.id, ss[0]!.id, 5, breakdown(5))
    await users.deleteById(u.id)
    const list = await scores.listForUser(u.id, 2026)
    expect(list).toEqual([])
  })
})
