import { describe, it, expect } from 'vitest'
import { eq, and } from 'drizzle-orm'
import { getDb } from '../../src/db/client.js'
import { user, league, leagueMember, prediction, predictionPick, session as sessionT } from '../../src/db/schema.js'
import * as seasons from '../../src/repo/seasons.js'
import * as eventsRepo from '../../src/repo/events.js'
import * as sessionsRepo from '../../src/repo/sessions.js'
import * as usersRepo from '../../src/repo/users.js'
import * as driversRepo from '../../src/repo/drivers.js'
import { importParsedSeason2025 } from '../../src/scripts/tippspiel/importer2025.js'
import type { ParsedSeason, RacePicks } from '../../src/scripts/tippspiel/types.js'

const NOPTS = { quali: 0, sprint: 0, race: 0 }
const picks = (p: Partial<RacePicks>): RacePicks =>
  ({ quali: [], sprintQuali: [], sprint: [], race: [], excelPoints: NOPTS, ...p })
const d = (pos: number[], codes: string[]) => pos.map((position, i) => ({ position, driverCode: codes[i]! }))

async function seedSeason() {
  await seasons.upsertSeason({ year: 2025, isCurrent: false })
  // Drivers must exist (prediction_pick.driver_code FK) — the real flow loads
  // these via the backfill before importing.
  for (const code of ['NOR', 'LEC', 'PIA', 'VER', 'RUS']) {
    await driversRepo.upsertDriver({ code, givenName: code, familyName: code, nationality: null, permanentNumber: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, headshotUrl: null })
  }
  const aus = await eventsRepo.upsertEvent({ seasonYear: 2025, round: 1, name: 'Australian Grand Prix', circuitName: 'Albert Park', country: 'Australia', hasSprint: false })
  const bel = await eventsRepo.upsertEvent({ seasonYear: 2025, round: 13, name: 'Belgian Grand Prix', circuitName: 'Spa', country: 'Belgium', hasSprint: true })
  const t0 = new Date('2025-03-16T05:00:00Z')
  for (const type of ['qualifying', 'race'] as const) {
    await sessionsRepo.upsertSession({ eventId: aus.id, type, scheduledStart: t0, scheduledEnd: t0, status: 'finished', openf1SessionKey: null })
  }
  await sessionsRepo.upsertSession({ eventId: bel.id, type: 'sprint', scheduledStart: t0, scheduledEnd: t0, status: 'finished', openf1SessionKey: null })
}

describe('importParsedSeason2025', () => {
  it('maps Julius→existing Juli, creates Manu, imports into The Box, skips partial picks', async () => {
    await seedSeason()
    // A pre-existing "Juli" account (the 2026 display name) Julius should attach to.
    const juli = await usersRepo.insertUser({ email: 'juli@tippspiel.test', passwordHash: 'x', displayName: 'Juli' })

    const parsed: ParsedSeason = {
      seasonYear: 2025,
      players: [
        // Anton owns The Box; full Australia quali + race.
        { excelName: 'Anton', racePicks: { Australien: picks({ quali: d([1, 2], ['NOR', 'LEC']), race: d([1, 2, 3, 4, 5], ['NOR', 'PIA', 'VER', 'RUS', 'LEC']) }) }, preseasonStandings: { constructors: [], drivers: [] }, preseasonSingle: {} },
        // Julius -> Juli; a partial Belgium sprint (2 of 3) must be skipped.
        { excelName: 'Julius', racePicks: { Belgium: picks({ sprint: d([1, 2], ['PIA', 'VER']) }) }, preseasonStandings: { constructors: [], drivers: [] }, preseasonSingle: {} },
        // Manu is new.
        { excelName: 'Manu', racePicks: { Australien: picks({ quali: d([1, 2], ['VER', 'NOR']) }) }, preseasonStandings: { constructors: [], drivers: [] }, preseasonSingle: {} }
      ]
    }

    const summary = await importParsedSeason2025(parsed)
    const db = getDb()

    // Julius attached to the existing Juli account (no separate "Julius" user).
    expect(summary.userIdByExcelName.get('Julius')).toBe(juli.id)
    expect((await db.select().from(user).where(eq(user.displayName, 'Julius')))).toHaveLength(0)
    // Manu created.
    expect((await db.select().from(user).where(eq(user.displayName, 'Manu')))).toHaveLength(1)

    // The Box exists, owned by Anton, with all three as members.
    const boxes = await db.select().from(league).where(eq(league.name, 'The Box'))
    expect(boxes).toHaveLength(1)
    const antonId = summary.userIdByExcelName.get('Anton')!
    expect(boxes[0]!.ownerUserId).toBe(antonId)
    const members = await db.select().from(leagueMember).where(eq(leagueMember.leagueId, boxes[0]!.id))
    expect(members.map((m) => m.userId).sort()).toEqual([antonId, juli.id, summary.userIdByExcelName.get('Manu')!].sort())

    // Anton's Australia quali (2) + race (5) predictions stored.
    const antonPreds = await db.select().from(prediction).where(eq(prediction.userId, antonId))
    expect(antonPreds).toHaveLength(2)

    // Julius's partial Belgium sprint (2 of 3) was skipped — no prediction stored for him.
    const juliPreds = await db.select().from(prediction).where(eq(prediction.userId, juli.id))
    expect(juliPreds).toHaveLength(0)
    expect(summary.predictionsSkipped.some((s) => /partial|count/i.test(s.reason))).toBe(true)
  })
})
