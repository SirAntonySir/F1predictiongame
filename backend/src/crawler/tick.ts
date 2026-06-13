import type { JolpicaClient } from '../jolpica/client.js'
import type { WikipediaClient } from '../wikipedia/client.js'
import type { OpenF1Client } from '../openf1/client.js'
import {
  parseRaceResults, parseQualifyingResults, parseSprintResults,
  parseDriverStandings, parseConstructorStandings,
  extractDriversFromResults, extractConstructorsFromResults,
  extractDriversFromStandings, extractConstructorsFromStandings,
  type DriverLookup, type ConstructorLookup
} from '../jolpica/parsers.js'
import { parseSessionResult as parseOpenF1SessionResult, parseDrivers as parseOpenF1Drivers, parseBestLapsPerDriver, type OpenF1DriverLookup } from '../openf1/parsers.js'
import * as sessionsRepo from '../repo/sessions.js'
import * as eventsRepo from '../repo/events.js'
import * as resultsRepo from '../repo/results.js'
import * as bestLapsRepo from '../repo/bestLaps.js'
import * as driversRepo from '../repo/drivers.js'
import * as constructorsRepo from '../repo/constructors.js'
import * as standingsRepo from '../repo/standings.js'
import * as seasonsRepo from '../repo/seasons.js'
import { rescoreSession } from '../scoring/rescorer.js'
import { rescorePreseasonForSeason } from '../preseason/rescorer.js'
import type { SessionType, SessionResultRow } from '../domain/types.js'
import { compareClassifications } from './crossCheck.js'
import { enrichDriversAndConstructors } from './openf1Enrichment.js'

export type TickSummary = { sessionsFinished: number; sessionsSkipped: number; errors: number }

type FetchOutput = {
  rows: SessionResultRow[]
  drivers: DriverLookup[]
  constructors: ConstructorLookup[]
}

export async function fetchByType(
  client: JolpicaClient,
  openf1: OpenF1Client,
  type: SessionType,
  year: number,
  round: number,
  openf1SessionKey: number | null
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
    case 'fp1':
    case 'fp2':
    case 'fp3': {
      if (openf1SessionKey == null) return empty
      const sr = await openf1.getSessionResult(openf1SessionKey)
      if (!sr) return empty
      const drv = await openf1.getDrivers(openf1SessionKey)
      if (!drv) return empty
      const openF1Drivers = parseOpenF1Drivers(drv)
      rows = parseOpenF1SessionResult(sr, openF1Drivers)
      return {
        rows,
        drivers: openF1Drivers.map((d) => ({
          code: d.code, givenName: d.givenName, familyName: d.familyName,
          nationality: null, permanentNumber: d.driverNumber, wikipediaUrl: null
        })),
        constructors: dedupeConstructorsFromOpenF1(openF1Drivers)
      }
    }
  }
  return {
    rows,
    drivers: extractDriversFromResults(raw),
    constructors: extractConstructorsFromResults(raw)
  }
}

function dedupeConstructorsFromOpenF1(drivers: OpenF1DriverLookup[]) {
  const seen = new Map<string, { id: string; name: string; nationality: null; wikipediaUrl: null }>()
  for (const d of drivers) {
    const id = d.teamName.toLowerCase().replace(/\s+/g, '_')
    if (!seen.has(id)) seen.set(id, { id, name: d.teamName, nationality: null, wikipediaUrl: null })
  }
  return [...seen.values()]
}

async function enrichImage(wiki: WikipediaClient, wikipediaUrl: string | null): Promise<string | null> {
  if (!wikipediaUrl) return null
  return wiki.getImageUrl(wikipediaUrl)
}

// Upsert lookup rows for genuinely-new drivers and enrich images on first sight.
// Existing rows keep their fetched image_url and any manual image_url_override.
export async function upsertNewDrivers(drivers: DriverLookup[], wiki: WikipediaClient): Promise<void> {
  for (const d of drivers) {
    if (await driversRepo.exists(d.code)) continue
    await driversRepo.upsertDriver({ ...d, imageUrl: null, imageUrlOverride: null, headshotUrl: null })
    const img = await enrichImage(wiki, d.wikipediaUrl)
    if (img) await driversRepo.setImageUrl(d.code, img)
  }
}

export async function upsertNewConstructors(constructors: ConstructorLookup[], wiki: WikipediaClient): Promise<void> {
  for (const c of constructors) {
    if (await constructorsRepo.exists(c.id)) continue
    await constructorsRepo.upsertConstructor({ ...c, imageUrl: null, imageUrlOverride: null, teamColour: null })
    const img = await enrichImage(wiki, c.wikipediaUrl)
    if (img) await constructorsRepo.setImageUrl(c.id, img)
  }
}

export async function runTick(jolpica: JolpicaClient, wiki: WikipediaClient, openf1: OpenF1Client): Promise<TickSummary> {
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
      const jolpicaOut = await fetchByType(jolpica, openf1, ses.type, ev.seasonYear, ev.round, ses.openf1SessionKey)

      let rowsToPersist = jolpicaOut.rows
      let driversToUpsert = jolpicaOut.drivers
      let constructorsToUpsert = jolpicaOut.constructors
      let openF1Drivers: OpenF1DriverLookup[] | null = null

      const isCrossCheckable = ses.type === 'race' || ses.type === 'qualifying' || ses.type === 'sprint'
      if (isCrossCheckable && ses.openf1SessionKey != null) {
        try {
          const sr = await openf1.getSessionResult(ses.openf1SessionKey)
          const drv = await openf1.getDrivers(ses.openf1SessionKey)
          if (sr && drv) {
            openF1Drivers = parseOpenF1Drivers(drv)
            const oRows = parseOpenF1SessionResult(sr, openF1Drivers)
            if (rowsToPersist.length === 0 && oRows.length > 0) {
              rowsToPersist = oRows
              driversToUpsert = openF1Drivers.map((d) => ({
                code: d.code, givenName: d.givenName, familyName: d.familyName,
                nationality: null, permanentNumber: d.driverNumber, wikipediaUrl: null
              }))
              constructorsToUpsert = dedupeConstructorsFromOpenF1(openF1Drivers)
            } else if (oRows.length > 0) {
              const cmp = compareClassifications(rowsToPersist, oRows)
              if (cmp.kind !== 'match') {
                console.warn('OpenF1 cross-check mismatch', { sessionId: ses.id, type: ses.type, summary: cmp })
              }
            }
          }
        } catch (err) {
          console.warn('OpenF1 cross-check fetch failed', { sessionId: ses.id, err })
        }
      }

      if (rowsToPersist.length === 0) { summary.sessionsSkipped++; continue }

      // Drivers/constructors must exist before session_result rows reference them via FK.
      await upsertNewDrivers(driversToUpsert, wiki)
      await upsertNewConstructors(constructorsToUpsert, wiki)

      await resultsRepo.replaceForSession(ses.id!, rowsToPersist.map((r) => ({ ...r, sessionId: ses.id! })))
      await sessionsRepo.markFinished(ses.id!)

      // Best-lap-with-sectors snapshot for the sector-color reference view on
      // the predict screen. OpenF1-only; skip if the session has no key.
      // Failures here don't block the tick — the result row is what matters
      // for scoring; sector data is decorative.
      if (ses.openf1SessionKey != null) {
        try {
          const lapsRaw = await openf1.getLaps(ses.openf1SessionKey)
          const drvForLaps = openF1Drivers
            ?? parseOpenF1Drivers(await openf1.getDrivers(ses.openf1SessionKey) ?? [])
          const best = parseBestLapsPerDriver(lapsRaw, drvForLaps)
          await bestLapsRepo.replaceForSession(ses.id!, best)
        } catch (err) {
          console.warn('Best-lap snapshot failed (session result saved)', { sessionId: ses.id, err })
        }
      }

      if (openF1Drivers) {
        await enrichDriversAndConstructors(openF1Drivers)
      } else if (ses.type === 'sprint_quali' && ses.openf1SessionKey != null) {
        try {
          const drv = await openf1.getDrivers(ses.openf1SessionKey)
          if (drv) await enrichDriversAndConstructors(parseOpenF1Drivers(drv))
        } catch (err) {
          console.warn('OpenF1 enrichment fetch failed (sprint_quali)', { sessionId: ses.id, err })
        }
      }

      summary.sessionsFinished++
      anyFinished = true
      try {
        const rescore = await rescoreSession(ses.id!)
        console.log('Rescored session', { sessionId: ses.id, ...rescore })
      } catch (err) {
        console.error('Rescore failed (results saved)', { sessionId: ses.id, err })
      }
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
        try {
          const preseasonSummary = await rescorePreseasonForSeason(cur.year)
          console.log('Preseason rescored', { year: cur.year, ...preseasonSummary })
        } catch (err) {
          console.error('Preseason rescore failed', err)
        }
      }
    } catch (err) {
      summary.errors++
      console.error('Standings refresh error', err)
    }
  }

  return summary
}
