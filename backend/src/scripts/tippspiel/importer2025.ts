import { eq, sql } from 'drizzle-orm'
import { hashPassword } from '../../auth/password.js'
import { getDb } from '../../db/client.js'
import { user as userTable, league as leagueTable } from '../../db/schema.js'
import * as usersRepo from '../../repo/users.js'
import * as leaguesRepo from '../../repo/leagues.js'
import * as eventsRepo from '../../repo/events.js'
import * as sessionsRepo from '../../repo/sessions.js'
import * as predictionsRepo from '../../repo/predictions.js'
import * as preseasonPicksRepo from '../../repo/preseasonPicks.js'
import * as preseasonStandingsRepo from '../../repo/preseasonStandings.js'
import type { ParsedSeason } from './types.js'
import { SESSION_TYPE_BY_KIND } from './types.js'
import { mapEventName2025 } from './mappings2025.js'
import type { PreseasonCategory, SessionType } from '../../domain/types.js'

const PASSWORD_PLAIN = 'tippspiel-test'
const LEAGUE_NAME = 'The Box'
const LEAGUE_JOIN_CODE = 'TIPP-2026'
const ANTON_EXCEL_NAME = 'Anton'

// Excel display name -> existing account display name. "Julius" (2025) is the
// same person as the "Juli" account created for 2026; everyone else matches by
// name (Manu has no prior account, so one is created).
export const DEFAULT_ALIASES: Record<string, string> = { Julius: 'Juli' }

const EXPECTED_PICKS: Partial<Record<SessionType, number>> = {
  qualifying: 2, sprint_quali: 1, sprint: 3, race: 5
}

const emailFor = (name: string) => `${name.toLowerCase()}@tippspiel.test`

export type Import2025Summary = {
  userIdByExcelName: Map<string, string>
  leagueId: string
  predictionsUpserted: number
  predictionsSkipped: { reason: string; count: number }[]
  preseasonPicksUpserted: number
  preseasonStandingsUpserted: number
}

export async function importParsedSeason2025(
  parsed: ParsedSeason,
  opts: { aliases?: Record<string, string> } = {}
): Promise<Import2025Summary> {
  const aliases = opts.aliases ?? DEFAULT_ALIASES
  const db = getDb()
  const passwordHash = await hashPassword(PASSWORD_PLAIN)

  // 1. Resolve/create users (alias-aware, find by display name).
  const userIdByExcelName = new Map<string, string>()
  for (const player of parsed.players) {
    const displayName = aliases[player.excelName] ?? player.excelName
    const existing = await db.select().from(userTable).where(eq(userTable.displayName, displayName)).limit(1)
    const id = existing.length > 0
      ? existing[0]!.id
      : (await usersRepo.insertUser({ email: emailFor(displayName), passwordHash, displayName })).id
    userIdByExcelName.set(player.excelName, id)
  }

  const antonId = userIdByExcelName.get(ANTON_EXCEL_NAME)
  if (!antonId) throw new Error('Anton not found among parsed players — required as league owner')

  // 2. Find The Box (don't recreate). On a fresh DB, create it owned by Anton;
  //    if Anton already owns a (differently-named) league, reuse that rather
  //    than violate the one-league-per-owner constraint.
  const byName = await db.select().from(leagueTable).where(eq(leagueTable.name, LEAGUE_NAME)).limit(1)
  let leagueId: string
  if (byName.length > 0) {
    leagueId = byName[0]!.id
  } else {
    const owned = await db.select().from(leagueTable).where(eq(leagueTable.ownerUserId, antonId)).limit(1)
    leagueId = owned.length > 0
      ? owned[0]!.id
      : (await leaguesRepo.createLeagueWithOwner({ name: LEAGUE_NAME, ownerUserId: antonId, joinCode: LEAGUE_JOIN_CODE })).id
  }

  // 3. League membership for everyone (insert-ignore).
  for (const uid of userIdByExcelName.values()) {
    await db.execute(sql`
      INSERT INTO league_member (league_id, user_id)
      VALUES (${leagueId}::uuid, ${uid}::uuid)
      ON CONFLICT (league_id, user_id) DO NOTHING
    `)
  }

  // 4/5. Preseason standings + single picks.
  let preseasonStandingsUpserted = 0
  let preseasonPicksUpserted = 0
  for (const player of parsed.players) {
    const uid = userIdByExcelName.get(player.excelName)!
    if (player.preseasonStandings.constructors.length > 0) {
      await preseasonStandingsRepo.replaceConstructorPicks(
        uid, parsed.seasonYear,
        player.preseasonStandings.constructors.map((c) => ({ position: c.position, entityId: c.constructorId }))
      )
      preseasonStandingsUpserted++
    }
    if (player.preseasonStandings.drivers.length > 0) {
      await preseasonStandingsRepo.replaceDriverPicks(
        uid, parsed.seasonYear,
        player.preseasonStandings.drivers.map((dr) => ({ position: dr.position, entityId: dr.driverCode }))
      )
      preseasonStandingsUpserted++
    }
    for (const [category, vals] of Object.entries(player.preseasonSingle)) {
      await preseasonPicksRepo.upsertPick(uid, parsed.seasonYear, category as PreseasonCategory, {
        driverCode: vals!.driverCode, constructorId: vals!.constructorId
      })
      preseasonPicksUpserted++
    }
  }

  // 6. Per-race predictions. Skip pick lists whose count != the expected number
  //    for that session (e.g. a 2-of-3 sprint) — the canonical engine can only
  //    score complete sets, so a partial is treated as "no valid prediction".
  const events = await eventsRepo.listForSeason(parsed.seasonYear)
  const eventIdByName = new Map(events.map((e) => [e.name, e.id]))
  const sessionsByEventId = new Map<number, { type: string; id: number }[]>()
  for (const ev of events) {
    sessionsByEventId.set(ev.id, (await sessionsRepo.listForEvent(ev.id)).map((s) => ({ type: s.type, id: s.id })))
  }

  let predictionsUpserted = 0
  const skip = new Map<string, number>()
  const bump = (r: string) => skip.set(r, (skip.get(r) ?? 0) + 1)

  for (const player of parsed.players) {
    const uid = userIdByExcelName.get(player.excelName)!
    for (const [excelEvent, racePicks] of Object.entries(player.racePicks)) {
      let dbName: string
      try { dbName = mapEventName2025(excelEvent) } catch { bump(`unknown-event:${excelEvent}`); continue }
      const eventId = eventIdByName.get(dbName)
      if (eventId === undefined) { bump(`event-not-in-db:${dbName}`); continue }
      const sessions = sessionsByEventId.get(eventId) ?? []
      for (const kind of ['quali', 'sprintQuali', 'sprint', 'race'] as const) {
        const list = racePicks[kind]
        if (list.length === 0) continue
        const sType = SESSION_TYPE_BY_KIND[kind]
        if (list.length !== EXPECTED_PICKS[sType]) { bump(`partial-picks:${sType}`); continue }
        const session = sessions.find((s) => s.type === sType)
        if (!session) { bump(`session-not-in-db:${dbName}:${sType}`); continue }
        await predictionsRepo.upsertPredictionWithPicks(uid, session.id, list)
        predictionsUpserted++
      }
    }
  }

  return {
    userIdByExcelName, leagueId, predictionsUpserted,
    predictionsSkipped: [...skip.entries()].map(([reason, count]) => ({ reason, count })),
    preseasonPicksUpserted, preseasonStandingsUpserted
  }
}
