/**
 * One-off correction after the Baku 2026 audit: enforce the retroactive
 * 3-jokers-per-season rule and backfill picks that never reached the app.
 *
 * Authoritative joker state (decided by the league, 2026-09-29):
 *   Jakob  — Japan, Belgien, Niederlande   → 0 left
 *   Jonas  — Monaco, Barcelona, Belgien    → 0 left  (Belgien = late hand-in,
 *            real picks stay, only the label becomes 'joker')
 *   Anton  — Baku                          → 2 left  (already correct in DB)
 *   David  — China, Italien, Baku          → 0 left
 *   Merlin — Niederlande, Baku             → 1 left  (already correct in DB)
 *
 * Points are NOT taken from the Excel — every touched session is rescored by
 * the canonical engine from official results. Resolves users BY NAME within
 * the league, sessions by (season, round, type), so it runs against any
 * database — point DATABASE_URL at the target.
 *
 *   DRY_RUN=1 npx tsx src/scripts/fixJokersBaku2026.ts   # plan only, no writes
 *   npx tsx src/scripts/fixJokersBaku2026.ts             # apply + rescore + diff
 *
 * Idempotent: relabels/upserts overwrite, deletes are no-ops on re-run.
 */
import { and, eq, ilike, inArray } from 'drizzle-orm'
import { getDb, getPool } from '../db/client.js'
import { user, event, session, driver, league, leagueMember, prediction, score } from '../db/schema.js'
import { upsertPredictionWithPicks, deleteByUserAndSession, countJokersUsedForSeason, listForSessionWithPicks } from '../repo/predictions.js'
import { deleteSessionScore } from '../repo/scores.js'
import { rescoreSession } from '../scoring/rescorer.js'

const SEASON = 2026
const LEAGUE_NAME = 'The Box'

type SessionKind = 'qualifying' | 'sprint_quali' | 'sprint' | 'race'
const pick = (codes: string[]) => codes.map((driverCode, i) => ({ position: i + 1, driverCode }))

/// Predictions whose picks are real but whose source must become 'joker'
/// (missed-race copies imported as 'app', or late hand-ins that consumed a joker).
const RELABEL_TO_JOKER: { name: string; round: number; kind: SessionKind }[] = [
  { name: 'David', round: 2,  kind: 'race' },   // China   = Kopie von Australien
  { name: 'Jakob', round: 3,  kind: 'race' },   // Japan   = Kopie von China
  { name: 'Jonas', round: 6,  kind: 'race' },   // Monaco  = Kopie von Kanada
  { name: 'Jonas', round: 7,  kind: 'race' },   // Barcelona = Kopie von Monaco
  { name: 'Jakob', round: 10, kind: 'race' },   // Belgien = Kopie von GB
  { name: 'Jonas', round: 10, kind: 'race' }    // Belgien = Nachreichung, kostet Joker
]

/// Auto-jokers beyond the 3-per-season budget: the prediction (and its score)
/// must go — no picks, no points.
const DELETE_PREDICTION: { name: string; round: number; kind: SessionKind }[] = [
  { name: 'Jonas', round: 12, kind: 'race' },   // Niederlande (Joker waren verbraucht)
  { name: 'Jakob', round: 13, kind: 'race' },   // Italien    (4. Joker)
  { name: 'Jakob', round: 14, kind: 'race' }    // Spanien    (5. Joker)
]

/// Real submissions that never reached the app (WhatsApp/Excel), replacing
/// wrong auto-jokers or filling gaps. Source 'app' to match the season import.
const SET_PICKS: { name: string; round: number; kind: SessionKind; codes: string[] }[] = [
  { name: 'Jonas', round: 9,  kind: 'sprint',       codes: ['HAM', 'LEC'] },              // partial: P3 fehlt
  { name: 'David', round: 9,  kind: 'sprint',       codes: ['ANT', 'HAM'] },              // partial: P3 fehlt
  { name: 'Jonas', round: 12, kind: 'sprint_quali', codes: ['ANT'] },
  { name: 'David', round: 12, kind: 'sprint',       codes: ['RUS', 'NOR', 'LEC'] },
  { name: 'David', round: 12, kind: 'race',         codes: ['NOR', 'RUS', 'ANT', 'LEC', 'PIA'] },
  { name: 'David', round: 13, kind: 'qualifying',   codes: ['RUS', 'LEC'] },
  { name: 'Jonas', round: 13, kind: 'race',         codes: ['RUS', 'GAS', 'LEC', 'PIA', 'HAM'] },
  { name: 'Jonas', round: 14, kind: 'qualifying',   codes: ['ANT', 'LEC'] },
  { name: 'Jonas', round: 14, kind: 'race',         codes: ['ANT', 'VER', 'HAM', 'NOR', 'RUS'] },
  { name: 'Jonas', round: 15, kind: 'qualifying',   codes: ['VER', 'RUS'] }
]

/// Jokers whose copied picks are stale because the race they copy from was
/// itself corrected (joker = previous race's picks).
const SET_JOKER_PICKS: { name: string; round: number; kind: SessionKind; codes: string[] }[] = [
  { name: 'David', round: 13, kind: 'race', codes: ['NOR', 'RUS', 'ANT', 'LEC', 'PIA'] }  // Kopie von Niederlande (korrigiert)
]

/// Expected joker usage after the fix — the script aborts the celebration (but
/// not the writes) with a loud warning if the DB disagrees.
const EXPECTED_JOKERS: Record<string, number> = {
  Jakob: 3, Jonas: 3, David: 3, Anton: 1, Merlin: 2, Torsten: 1
}

type Snapshot = Map<string, Map<number, number>>  // userId -> sessionId -> points

async function snapshotScores(userIds: string[]): Promise<Snapshot> {
  const db = getDb()
  const rows = await db
    .select({ userId: score.userId, sessionId: score.sessionId, points: score.pointsTotal })
    .from(score)
    .innerJoin(session, eq(session.id, score.sessionId))
    .innerJoin(event, eq(event.id, session.eventId))
    .where(and(eq(score.kind, 'session'), eq(event.seasonYear, SEASON), inArray(score.userId, userIds)))
  const snap: Snapshot = new Map()
  for (const r of rows) {
    if (!snap.has(r.userId)) snap.set(r.userId, new Map())
    snap.get(r.userId)!.set(r.sessionId!, r.points)
  }
  return snap
}

const total = (m: Map<number, number> | undefined) =>
  [...(m?.values() ?? [])].reduce((s, x) => s + x, 0)

async function main() {
  const dry = !!process.env.DRY_RUN
  const db = getDb()

  // --- resolve users (all league members, for the standings table) ----------
  const members = await db
    .select({ id: user.id, name: user.displayName })
    .from(user)
    .innerJoin(leagueMember, eq(leagueMember.userId, user.id))
    .innerJoin(league, eq(league.id, leagueMember.leagueId))
    .where(eq(league.name, LEAGUE_NAME))
  const idByName = new Map<string, string>()
  for (const m of members) {
    if (idByName.has(m.name)) throw new Error(`Ambiguous display name in league: ${m.name}`)
    idByName.set(m.name, m.id)
  }
  const need = new Set([...RELABEL_TO_JOKER, ...DELETE_PREDICTION, ...SET_PICKS, ...SET_JOKER_PICKS].map((c) => c.name))
  for (const n of need) if (!idByName.has(n)) throw new Error(`User "${n}" not found in league "${LEAGUE_NAME}"`)

  // --- resolve sessions by (round, type) ------------------------------------
  const sessRows = await db
    .select({ id: session.id, type: session.type, round: event.round, evName: event.name })
    .from(session)
    .innerJoin(event, eq(event.id, session.eventId))
    .where(eq(event.seasonYear, SEASON))
  const sessionByKey = new Map<string, { id: number; evName: string }>()
  for (const s of sessRows) {
    const key = `${s.round}:${s.type}`
    if (sessionByKey.has(key)) throw new Error(`Duplicate session for ${key}`)
    sessionByKey.set(key, { id: s.id, evName: s.evName })
  }
  const sess = (round: number, kind: SessionKind) => {
    const s = sessionByKey.get(`${round}:${kind}`)
    if (!s) throw new Error(`No ${kind} session for round ${round} in ${SEASON}`)
    return s
  }

  // --- validate driver codes -------------------------------------------------
  const allCodes = [...new Set([...SET_PICKS, ...SET_JOKER_PICKS].flatMap((c) => c.codes))]
  const known = new Set((await db.select({ code: driver.code }).from(driver).where(inArray(driver.code, allCodes))).map((d) => d.code))
  for (const c of allCodes) if (!known.has(c)) throw new Error(`Unknown driver code: ${c}`)

  // --- plan ------------------------------------------------------------------
  console.log(`Fix jokers after Baku ${SEASON} — league "${LEAGUE_NAME}"${dry ? '  [DRY RUN, no writes]' : ''}\n`)
  console.log('Relabel source → joker (picks unchanged):')
  for (const c of RELABEL_TO_JOKER) console.log(`  ${c.name.padEnd(6)} R${c.round} ${sess(c.round, c.kind).evName} ${c.kind}`)
  console.log('Delete prediction + score (joker budget exhausted):')
  for (const c of DELETE_PREDICTION) console.log(`  ${c.name.padEnd(6)} R${c.round} ${sess(c.round, c.kind).evName} ${c.kind}`)
  console.log('Set real picks (source app):')
  for (const c of SET_PICKS) console.log(`  ${c.name.padEnd(6)} R${c.round} ${sess(c.round, c.kind).evName} ${c.kind}: ${c.codes.join(' ')}`)
  console.log('Update joker picks (stale copy):')
  for (const c of SET_JOKER_PICKS) console.log(`  ${c.name.padEnd(6)} R${c.round} ${sess(c.round, c.kind).evName} ${c.kind}: ${c.codes.join(' ')}`)

  if (dry) {
    console.log('\nDry run complete — re-run without DRY_RUN to apply.')
    return
  }

  // --- before snapshot -------------------------------------------------------
  const memberIds = members.map((m) => m.id)
  const before = await snapshotScores(memberIds)

  // --- apply -----------------------------------------------------------------
  const touched = new Map<number, string>()  // sessionId -> label
  for (const c of RELABEL_TO_JOKER) {
    const s = sess(c.round, c.kind)
    const uid = idByName.get(c.name)!
    const existing = (await listForSessionWithPicks(s.id)).find((p) => p.userId === uid)
    if (!existing || existing.picks.length === 0) throw new Error(`Relabel target missing: ${c.name} R${c.round} ${c.kind}`)
    await db.update(prediction).set({ source: 'joker' }).where(and(eq(prediction.userId, uid), eq(prediction.sessionId, s.id)))
    console.log(`  ✓ relabel ${c.name} R${c.round} → joker`)
  }
  for (const c of DELETE_PREDICTION) {
    const s = sess(c.round, c.kind)
    const uid = idByName.get(c.name)!
    await deleteByUserAndSession(uid, s.id)
    await deleteSessionScore(uid, s.id)
    touched.set(s.id, `R${c.round} ${s.evName} ${c.kind}`)
    console.log(`  ✓ delete  ${c.name} R${c.round} ${c.kind}`)
  }
  for (const c of SET_PICKS) {
    const s = sess(c.round, c.kind)
    await upsertPredictionWithPicks(idByName.get(c.name)!, s.id, pick(c.codes))
    touched.set(s.id, `R${c.round} ${s.evName} ${c.kind}`)
    console.log(`  ✓ picks   ${c.name} R${c.round} ${c.kind} = ${c.codes.join(' ')}`)
  }
  for (const c of SET_JOKER_PICKS) {
    const s = sess(c.round, c.kind)
    await upsertPredictionWithPicks(idByName.get(c.name)!, s.id, pick(c.codes), { source: 'joker' })
    touched.set(s.id, `R${c.round} ${s.evName} ${c.kind}`)
    console.log(`  ✓ joker   ${c.name} R${c.round} ${c.kind} = ${c.codes.join(' ')}`)
  }

  // --- rescore ---------------------------------------------------------------
  console.log('\nRescoring touched sessions:')
  for (const [sid, label] of touched) {
    const r = await rescoreSession(sid)
    console.log(`  ${label}: ${r.users} predictions, ${r.totalPoints} pts total`)
  }

  // --- diff ------------------------------------------------------------------
  const after = await snapshotScores(memberIds)
  const nameById = new Map(members.map((m) => [m.id, m.name]))
  console.log('\nScore changes (before → after):')
  for (const uid of memberIds) {
    const b = before.get(uid) ?? new Map<number, number>()
    const a = after.get(uid) ?? new Map<number, number>()
    for (const sid of new Set([...b.keys(), ...a.keys()])) {
      const bv = b.get(sid), av = a.get(sid)
      if (bv === av) continue
      const label = touched.get(sid) ?? `session ${sid}`
      console.log(`  ${nameById.get(uid)!.padEnd(6)} ${label}: ${bv ?? '—'} → ${av ?? '—'}`)
    }
  }

  console.log('\nSeason totals (before → after):')
  const rowsOut = memberIds
    .map((uid) => ({ name: nameById.get(uid)!, b: total(before.get(uid)), a: total(after.get(uid)) }))
    .sort((x, y) => y.a - x.a)
  for (const r of rowsOut) {
    const delta = r.a - r.b
    console.log(`  ${r.name.padEnd(8)} ${String(r.b).padStart(4)} → ${String(r.a).padStart(4)}  ${delta === 0 ? '' : (delta > 0 ? `+${delta}` : `${delta}`)}`)
  }

  // --- joker audit -----------------------------------------------------------
  const usedById = await countJokersUsedForSeason(SEASON)
  console.log('\nJokers used (of 3):')
  let warned = false
  for (const m of members) {
    const used = usedById.get(m.id) ?? 0
    const expected = EXPECTED_JOKERS[m.name] ?? 0
    const flag = used > 3 ? '  !! OVER LIMIT' : used !== expected ? `  !! expected ${expected}` : ''
    if (flag) warned = true
    if (used > 0 || flag) console.log(`  ${m.name.padEnd(8)} ${used}${flag}`)
  }
  console.log(warned ? '\nDone — WITH WARNINGS, check the joker audit above.' : '\nDone — joker audit clean.')
}

main()
  .then(async () => { await getPool().end() })
  .catch(async (e) => { console.error('ERROR:', e instanceof Error ? e.message : e); try { await getPool().end() } catch { /* noop */ } process.exitCode = 1 })
