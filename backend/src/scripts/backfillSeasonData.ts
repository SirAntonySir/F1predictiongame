// Backfill a *completed* season's reference data (events, sessions, results,
// driver/constructor standings) from the F1 APIs — without disturbing the live
// current season.
//
// Differs from the normal crawler in two safety-critical ways:
//   - the season is upserted with is_current=false (runBootstrap forces true),
//   - standings are fetched for THIS year explicitly (runTick refreshes only
//     the current season's standings).
//
// Reuses the crawler's per-session fetch/parse + driver/constructor upserts so
// the data matches exactly what a live tick would have produced.
import { JolpicaClient } from '../jolpica/client.js'
import { OpenF1Client } from '../openf1/client.js'
import { WikipediaClient } from '../wikipedia/client.js'
import {
  parseSchedule, parseDriverStandings, parseConstructorStandings,
  extractDriversFromStandings, extractConstructorsFromStandings
} from '../jolpica/parsers.js'
import { mapSessionsToOpenF1 } from '../crawler/openf1Mapping.js'
import { fetchByType, upsertNewDrivers, upsertNewConstructors } from '../crawler/tick.js'
import * as seasonsRepo from '../repo/seasons.js'
import * as eventsRepo from '../repo/events.js'
import * as sessionsRepo from '../repo/sessions.js'
import * as resultsRepo from '../repo/results.js'
import * as standingsRepo from '../repo/standings.js'

export type BackfillDeps = { jolpica: JolpicaClient; openf1: OpenF1Client; wiki: WikipediaClient }
export type BackfillSummary = {
  year: number
  eventsUpserted: number
  sessionsUpserted: number
  sessionsFinished: number
  sessionsSkipped: number
  driverStandings: number
  constructorStandings: number
  errors: number
}

const PRACTICE = new Set(['fp1', 'fp2', 'fp3'])

export async function backfillSeasonData(year: number, deps: Partial<BackfillDeps> = {}): Promise<BackfillSummary> {
  const jolpica = deps.jolpica ?? new JolpicaClient()
  const openf1 = deps.openf1 ?? new OpenF1Client()
  const wiki = deps.wiki ?? new WikipediaClient()
  const summary: BackfillSummary = {
    year, eventsUpserted: 0, sessionsUpserted: 0, sessionsFinished: 0,
    sessionsSkipped: 0, driverStandings: 0, constructorStandings: 0, errors: 0
  }

  // 1. Schedule -> season (NOT current) + events + sessions.
  const raw = await jolpica.getSeasonSchedule(year)
  if (!raw) throw new Error(`Jolpica returned null for season ${year}`)
  const schedule = parseSchedule(raw)
  await seasonsRepo.upsertSeason({ year: schedule.year, isCurrent: false })
  for (const ev of schedule.events) {
    const stored = await eventsRepo.upsertEvent({
      seasonYear: ev.seasonYear, round: ev.round, name: ev.name,
      circuitName: ev.circuitName, country: ev.country, hasSprint: ev.hasSprint
    })
    summary.eventsUpserted++
    for (const s of ev.sessions) {
      await sessionsRepo.upsertSession({
        eventId: stored.id, type: s.type,
        scheduledStart: s.scheduledStart, scheduledEnd: s.scheduledEnd,
        status: 'scheduled', openf1SessionKey: null
      })
      summary.sessionsUpserted++
    }
  }

  // OpenF1 session-key mapping (needed for sprint_quali, which Jolpica lacks).
  try {
    await mapSessionsToOpenF1(year, openf1)
  } catch (err) {
    console.error('OpenF1 mapping failed (backfill continues)', err)
  }

  // 2. Per-session results for every (non-practice) session in the season.
  const events = await eventsRepo.listForSeason(year)
  for (const ev of events) {
    const ss = await sessionsRepo.listForEvent(ev.id)
    for (const ses of ss) {
      if (PRACTICE.has(ses.type)) continue
      try {
        const out = await fetchByType(jolpica, openf1, ses.type, year, ev.round, ses.openf1SessionKey)
        if (out.rows.length === 0) { summary.sessionsSkipped++; continue }
        await upsertNewDrivers(out.drivers, wiki)
        await upsertNewConstructors(out.constructors, wiki)
        await resultsRepo.replaceForSession(ses.id, out.rows.map((r) => ({ ...r, sessionId: ses.id })))
        await sessionsRepo.markFinished(ses.id)
        summary.sessionsFinished++
      } catch (err) {
        summary.errors++
        console.error('Backfill session error', { sessionId: ses.id, type: ses.type, round: ev.round, err })
      }
    }
  }

  // 3. Standings for THIS year (not the current season).
  const drvRaw = await jolpica.getDriverStandings(year)
  if (drvRaw) {
    await upsertNewDrivers(extractDriversFromStandings(drvRaw), wiki)
    await upsertNewConstructors(extractConstructorsFromStandings(drvRaw), wiki)
    const parsed = parseDriverStandings(drvRaw)
    await standingsRepo.replaceDriverStandings(year, parsed)
    summary.driverStandings = parsed.length
  }
  const ctorRaw = await jolpica.getConstructorStandings(year)
  if (ctorRaw) {
    await upsertNewConstructors(extractConstructorsFromStandings(ctorRaw), wiki)
    const parsed = parseConstructorStandings(ctorRaw)
    await standingsRepo.replaceConstructorStandings(year, parsed)
    summary.constructorStandings = parsed.length
  }

  return summary
}
