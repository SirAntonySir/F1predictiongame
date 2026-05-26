import { describe, it, expect } from 'vitest'
import * as users from '../../src/repo/users.js'
import * as seasons from '../../src/repo/seasons.js'
import * as events from '../../src/repo/events.js'
import * as sessions from '../../src/repo/sessions.js'
import * as leagues from '../../src/repo/leagues.js'
import * as members from '../../src/repo/leagueMembers.js'
import * as scores from '../../src/repo/scores.js'

const bd = (p: number) => ({
  perPosition: [{ position: 1, exact: true, wrongPos: false, points: p }],
  teamBonus: { applied: false, points: 0 },
  rule: 'test-v1'
})
const bdp = (p: number) => ({
  driver: { picked: 'VER', truth: 'VER', correct: true, points: p },
  team: { picked: null, truth: null, correct: false, points: 0 },
  pointsTotal: p,
  rule: 'preseason-surprise-v1'
})

async function seedSession() {
  await seasons.upsertSeason({ year: 2026, isCurrent: true })
  const ev = await events.upsertEvent({
    seasonYear: 2026, round: 1, name: 'B', circuitName: 'C', country: 'X', hasSprint: false
  })
  return sessions.upsertSession({
    eventId: ev.id, type: 'race',
    scheduledStart: new Date(2026, 2, 8, 15), scheduledEnd: new Date(2026, 2, 8, 17), status: 'scheduled',
  openf1SessionKey: null
  })
}

describe('leaderboard sums session + preseason scores', () => {
  it('a user with both kinds gets the combined total', async () => {
    const ses = await seedSession()
    const owner = await users.insertUser({ email: 'o@x.com', passwordHash: 'h', displayName: 'O' })
    const l = await leagues.createLeagueWithOwner({ name: 'L', ownerUserId: owner.id, joinCode: 'CMB001' })

    // Session score: 10 pts
    await scores.upsertScore(owner.id, ses.id, 10, bd(10))
    // Preseason scores: 4 + 8 = 12 pts across 2 categories
    await scores.upsertPreseasonScore(owner.id, 2026, 'surprise', 4, bdp(4))
    await scores.upsertPreseasonScore(owner.id, 2026, 'dnf',      8, bdp(8))

    const lb = await scores.leagueLeaderboard(l.id, 2026)
    const me = lb.find((r) => r.userId === owner.id)!
    expect(me.pointsTotal).toBe(22)
    expect(me.sessionsScored).toBe(1)  // only 1 session, preseason doesn't count
  })

  it('preseason-only user still appears with their points', async () => {
    await seedSession()
    const owner = await users.insertUser({ email: 'p@x.com', passwordHash: 'h', displayName: 'P' })
    const l = await leagues.createLeagueWithOwner({ name: 'LP', ownerUserId: owner.id, joinCode: 'CMB002' })
    await scores.upsertPreseasonScore(owner.id, 2026, 'wdc_wcc', 8, bdp(8))
    const lb = await scores.leagueLeaderboard(l.id, 2026)
    const me = lb.find((r) => r.userId === owner.id)!
    expect(me.pointsTotal).toBe(8)
    expect(me.sessionsScored).toBe(0)
  })

  it('zero-score member still appears', async () => {
    await seedSession()
    const owner = await users.insertUser({ email: 'z@x.com', passwordHash: 'h', displayName: 'Z' })
    const l = await leagues.createLeagueWithOwner({ name: 'LZ', ownerUserId: owner.id, joinCode: 'CMB003' })
    const lb = await scores.leagueLeaderboard(l.id, 2026)
    expect(lb.find((r) => r.userId === owner.id)!.pointsTotal).toBe(0)
  })

  it('season filter excludes preseason from other seasons', async () => {
    await seedSession()
    await seasons.upsertSeason({ year: 2024, isCurrent: false })
    const owner = await users.insertUser({ email: 'f@x.com', passwordHash: 'h', displayName: 'F' })
    const l = await leagues.createLeagueWithOwner({ name: 'LF', ownerUserId: owner.id, joinCode: 'CMB004' })
    await scores.upsertPreseasonScore(owner.id, 2024, 'surprise', 99, bdp(99))
    const lb = await scores.leagueLeaderboard(l.id, 2026)
    expect(lb.find((r) => r.userId === owner.id)!.pointsTotal).toBe(0)
  })
})
