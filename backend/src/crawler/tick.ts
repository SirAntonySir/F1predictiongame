import type { JolpicaClient } from '../jolpica/client.js'
import type { WikipediaClient } from '../wikipedia/client.js'
import {
  parseRaceResults, parseQualifyingResults, parseSprintResults,
  parseDriverStandings, parseConstructorStandings,
  extractDriversFromResults, extractConstructorsFromResults,
  extractDriversFromStandings, extractConstructorsFromStandings,
  type DriverLookup, type ConstructorLookup
} from '../jolpica/parsers.js'
import * as sessionsRepo from '../repo/sessions.js'
import * as eventsRepo from '../repo/events.js'
import * as resultsRepo from '../repo/results.js'
import * as driversRepo from '../repo/drivers.js'
import * as constructorsRepo from '../repo/constructors.js'
import * as standingsRepo from '../repo/standings.js'
import * as seasonsRepo from '../repo/seasons.js'
import type { SessionType, SessionResultRow } from '../domain/types.js'

export type TickSummary = { sessionsFinished: number; sessionsSkipped: number; errors: number }

type FetchOutput = {
  rows: SessionResultRow[]
  drivers: DriverLookup[]
  constructors: ConstructorLookup[]
}

async function fetchByType(
  client: JolpicaClient, type: SessionType, year: number, round: number
): Promise<FetchOutput> {
  const empty: FetchOutput = { rows: [], drivers: [], constructors: [] }
  let raw: unknown | null = null
  let rows: SessionResultRow[] = []
  switch (type) {
    case 'race':
      raw = await client.getRaceResults(year, round)
      if (!raw) return empty
      rows = parseRaceResults(raw)
      break
    case 'qualifying':
      raw = await client.getQualifyingResults(year, round)
      if (!raw) return empty
      rows = parseQualifyingResults(raw)
      break
    case 'sprint':
      raw = await client.getSprintResults(year, round)
      if (!raw) return empty
      rows = parseSprintResults(raw)
      break
    case 'sprint_quali':
      raw = await client.getSprintQualifyingResults(year, round)
      if (!raw) return empty
      rows = parseQualifyingResults(raw)
      break
    default:
      return empty  // FPx — never fetched
  }
  return {
    rows,
    drivers: extractDriversFromResults(raw),
    constructors: extractConstructorsFromResults(raw)
  }
}

async function enrichImage(wiki: WikipediaClient, wikipediaUrl: string | null): Promise<string | null> {
  if (!wikipediaUrl) return null
  return wiki.getImageUrl(wikipediaUrl)
}

// Upsert lookup rows for genuinely-new drivers and enrich images on first sight.
// Existing rows keep their fetched image_url and any manual image_url_override.
async function upsertNewDrivers(drivers: DriverLookup[], wiki: WikipediaClient): Promise<void> {
  for (const d of drivers) {
    if (await driversRepo.exists(d.code)) continue
    await driversRepo.upsertDriver({ ...d, imageUrl: null, imageUrlOverride: null })
    const img = await enrichImage(wiki, d.wikipediaUrl)
    if (img) await driversRepo.setImageUrl(d.code, img)
  }
}

async function upsertNewConstructors(constructors: ConstructorLookup[], wiki: WikipediaClient): Promise<void> {
  for (const c of constructors) {
    if (await constructorsRepo.exists(c.id)) continue
    await constructorsRepo.upsertConstructor({ ...c, imageUrl: null, imageUrlOverride: null })
    const img = await enrichImage(wiki, c.wikipediaUrl)
    if (img) await constructorsRepo.setImageUrl(c.id, img)
  }
}

export async function runTick(jolpica: JolpicaClient, wiki: WikipediaClient): Promise<TickSummary> {
  const summary: TickSummary = { sessionsFinished: 0, sessionsSkipped: 0, errors: 0 }
  const candidates = await sessionsRepo.listCandidates()
  if (candidates.length === 0) return summary

  const eventsCache = new Map<number, Awaited<ReturnType<typeof eventsRepo.getById>>>()
  async function getEvent(id: number) {
    if (eventsCache.has(id)) return eventsCache.get(id)!
    const ev = await eventsRepo.getById(id)
    if (!ev) throw new Error(`Event ${id} not found`)
    eventsCache.set(id, ev)
    return ev
  }

  let anyFinished = false

  for (const ses of candidates) {
    try {
      const ev = await getEvent(ses.eventId)
      if (!ev) { summary.errors++; continue }
      const { rows, drivers, constructors } = await fetchByType(jolpica, ses.type, ev.seasonYear, ev.round)
      if (rows.length === 0) { summary.sessionsSkipped++; continue }

      // Drivers/constructors must exist before session_result rows reference them via FK.
      await upsertNewDrivers(drivers, wiki)
      await upsertNewConstructors(constructors, wiki)

      await resultsRepo.replaceForSession(ses.id!, rows.map((r) => ({ ...r, sessionId: ses.id! })))
      await sessionsRepo.markFinished(ses.id!)
      summary.sessionsFinished++
      anyFinished = true
    } catch (err) {
      summary.errors++
      console.error('Tick error for session', ses.id, err)
    }
  }

  if (anyFinished) {
    try {
      const cur = await seasonsRepo.getCurrent()
      if (cur) {
        const drvRaw = await jolpica.getDriverStandings(cur.year)
        if (drvRaw) {
          // Standings can include drivers/constructors that never appeared in a
          // fetched session (subs, reserves) — upsert their lookups first so the
          // standings FK insert doesn't fail.
          await upsertNewDrivers(extractDriversFromStandings(drvRaw), wiki)
          await upsertNewConstructors(extractConstructorsFromStandings(drvRaw), wiki)
          await standingsRepo.replaceDriverStandings(cur.year, parseDriverStandings(drvRaw))
        }
        const ctorRaw = await jolpica.getConstructorStandings(cur.year)
        if (ctorRaw) {
          await upsertNewConstructors(extractConstructorsFromStandings(ctorRaw), wiki)
          await standingsRepo.replaceConstructorStandings(cur.year, parseConstructorStandings(ctorRaw))
        }
      }
    } catch (err) {
      summary.errors++
      console.error('Standings refresh error', err)
    }
  }

  return summary
}
