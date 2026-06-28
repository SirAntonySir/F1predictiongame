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
import { parseSessionResult as parseOpenF1SessionResult, parseDrivers as parseOpenF1Drivers, parseBestLapsPerDriver, parseKnockoutBestLapsPerDriver, type OpenF1DriverLookup } from '../openf1/parsers.js'
import { parseLivePositions } from '../openf1/live.js'
import { isScorableSessionType } from '../scoring/index.js'
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
import { enrichDriversAndConstructors } from './openf1Enrichment.js'

export type TickSummary = { sessionsFinished: number; sessionsSkipped: number; sessionsProvisional: number; errors: number }

type FetchOutput = {
  rows: SessionResultRow[]
  drivers: DriverLookup[]
  constructors: ConstructorLookup[]
  /// 'openf1' when rows came from the OpenF1 fast path; 'jolpica' when they
  /// came from Ergast/Jolpica. The runTick caller stamps this on the persisted
  /// session_result rows so the reconciliation pass can later flip 'openf1'
  /// rows to 'jolpica' once the official classification is published.
  source: 'openf1' | 'jolpica'
  /// Parsed OpenF1 drivers when the OpenF1 path was used — handed back so
  /// the caller can run image/constructor enrichment without re-fetching.
  openF1Drivers: OpenF1DriverLookup[] | null
}

async function fetchFromOpenF1(
  openf1: OpenF1Client,
  openf1SessionKey: number
): Promise<{ rows: SessionResultRow[]; drivers: OpenF1DriverLookup[] } | null> {
  const sr = await openf1.getSessionResult(openf1SessionKey)
  if (!sr) return null
  const drv = await openf1.getDrivers(openf1SessionKey)
  if (!drv) return null
  const openF1Drivers = parseOpenF1Drivers(drv)
  const rows = parseOpenF1SessionResult(sr, openF1Drivers)
  if (rows.length === 0) return null
  return { rows, drivers: openF1Drivers }
}

export async function fetchByType(
  client: JolpicaClient,
  openf1: OpenF1Client,
  type: SessionType,
  year: number,
  round: number,
  openf1SessionKey: number | null
): Promise<FetchOutput> {
  const empty: FetchOutput = { rows: [], drivers: [], constructors: [], source: 'jolpica', openF1Drivers: null }

  // OpenF1 fast path — try it first for every session type. Lands within
  // minutes of the chequered flag; Jolpica typically lags by 30 min to 1+ day.
  // We accept that OpenF1's classification may not yet reflect stewards'
  // penalties; the reconciliation pass will replace these rows with Jolpica's
  // official classification once it's published.
  if (openf1SessionKey != null) {
    try {
      const o = await fetchFromOpenF1(openf1, openf1SessionKey)
      if (o) {
        return {
          rows: o.rows,
          drivers: o.drivers.map((d) => ({
            code: d.code, givenName: d.givenName, familyName: d.familyName,
            nationality: null, permanentNumber: d.driverNumber, wikipediaUrl: null
          })),
          constructors: dedupeConstructorsFromOpenF1(o.drivers),
          source: 'openf1',
          openF1Drivers: o.drivers
        }
      }
    } catch (err) {
      console.warn('OpenF1 fast-path failed, falling back to Jolpica', { type, year, round, err })
    }
  }

  // Jolpica fallback — used when OpenF1 has no session key (older seasons,
  // pre-OpenF1-coverage) or when its fast path returned nothing yet.
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
    case 'fp3':
      // Jolpica doesn't publish these — if OpenF1 didn't have them either,
      // we have nothing to persist this tick.
      return empty
  }
  return {
    rows,
    drivers: extractDriversFromResults(raw),
    constructors: extractConstructorsFromResults(raw),
    source: 'jolpica',
    openF1Drivers: null
  }
}

/// Provisional fallback. When neither OpenF1's `session_result` nor Jolpica has
/// published the official classification yet (the window between the chequered
/// flag and the official result landing), derive a finishing order from
/// OpenF1's live `/position` timing — the same feed the live results screen
/// shows. Returns the rows + OpenF1 driver lookups (same shape as
/// [fetchFromOpenF1]) or null when there's no live order yet. The caller
/// persists these WITHOUT marking the session finished, so the next tick keeps
/// trying the official path and upgrades the rows the moment it publishes.
async function fetchProvisionalFromOpenF1(
  openf1: OpenF1Client,
  openf1SessionKey: number
): Promise<{ rows: SessionResultRow[]; drivers: OpenF1DriverLookup[] } | null> {
  const [rawPos, rawDrv] = await Promise.all([
    openf1.getPosition(openf1SessionKey),
    openf1.getDrivers(openf1SessionKey)
  ])
  if (!rawPos || !rawDrv) return null
  const openF1Drivers = parseOpenF1Drivers(rawDrv)
  const live = parseLivePositions(rawPos, openF1Drivers)
  if (live.length === 0) return null
  // Strip the live-only teamColour field — persist as a plain SessionResultRow.
  const rows: SessionResultRow[] = live.map(({ teamColour: _teamColour, ...r }) => r)
  return { rows, drivers: openF1Drivers }
}

function dedupeConstructorsFromOpenF1(drivers: OpenF1DriverLookup[]) {
  const seen = new Map<string, { id: string; name: string; nationality: null; wikipediaUrl: null }>()
  for (const d of drivers) {
    const id = d.teamName.toLowerCase().replace(/\s+/g, '_')
    if (!seen.has(id)) seen.set(id, { id, name: d.teamName, nationality: null, wikipediaUrl: null })
  }
  return [...seen.values()]
}

/// Map each row's derived OpenF1 constructorId to the canonical id already
/// in use for this driver this season, when one exists. See the call site in
/// runTick for the why: OpenF1's team_name strings drift mid-season and the
/// derived id ("stake_f1_team_kick_sauber") doesn't match Jolpica's ("sauber"),
/// which would create duplicate constructor rows.
async function canonicaliseConstructorIds(
  rows: SessionResultRow[],
  seasonYear: number
): Promise<SessionResultRow[]> {
  const out: SessionResultRow[] = []
  for (const r of rows) {
    const canonical = await resultsRepo.lastConstructorIdForDriverInSeason(r.driverCode, seasonYear)
    out.push(canonical && canonical !== r.constructorId ? { ...r, constructorId: canonical } : r)
  }
  return out
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

/// Re-pulls the current season's official driver + constructor standings from
/// Jolpica, replaces the stored standings, then rescores preseason predictions
/// against the fresh numbers. Shared by the tick (fired when a session flips to
/// finished) and the reconcile pass (hourly catch-up, since the finish-tick
/// refresh is a single shot that misses Jolpica's post-race publication lag).
/// Throws on fetch/parse/db failure — callers decide how to count the error.
export async function refreshStandings(
  jolpica: JolpicaClient,
  wiki: WikipediaClient
): Promise<void> {
  const cur = await seasonsRepo.getCurrent()
  if (!cur) return
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

export type RunTickOptions = {
  /// Limit the tick to a single session. Used by the scheduler's one-shot
  /// path (`tickForSession`) when triggered by an external event — e.g. a
  /// frontend FINALISED notification or an admin endpoint. When omitted, the
  /// normal candidate query runs.
  sessionId?: number
}

export async function runTick(
  jolpica: JolpicaClient,
  wiki: WikipediaClient,
  openf1: OpenF1Client,
  opts: RunTickOptions = {}
): Promise<TickSummary> {
  const summary: TickSummary = { sessionsFinished: 0, sessionsSkipped: 0, sessionsProvisional: 0, errors: 0 }
  let candidates
  if (opts.sessionId != null) {
    const one = await sessionsRepo.getById(opts.sessionId)
    // Only process the session if it's still scheduled — finished sessions are
    // handled by the reconciliation pass, not the tick.
    candidates = one && one.status === 'scheduled' ? [one] : []
  } else {
    candidates = await sessionsRepo.listCandidates()
  }
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
      let fetched = await fetchByType(jolpica, openf1, ses.type, ev.seasonYear, ev.round, ses.openf1SessionKey)
      let provisional = false

      if (fetched.rows.length === 0 && isScorableSessionType(ses.type) && ses.openf1SessionKey != null) {
        // No official classification yet (OpenF1 session_result + Jolpica both
        // empty), but the session is past its scheduled end (it's a candidate).
        // Fall back to OpenF1 live timing so the leaderboard + pick log reflect
        // a PROVISIONAL result now instead of waiting for the official to land.
        const prov = await fetchProvisionalFromOpenF1(openf1, ses.openf1SessionKey)
        if (prov) {
          fetched = {
            rows: prov.rows,
            drivers: prov.drivers.map((d) => ({
              code: d.code, givenName: d.givenName, familyName: d.familyName,
              nationality: null, permanentNumber: d.driverNumber, wikipediaUrl: null
            })),
            constructors: dedupeConstructorsFromOpenF1(prov.drivers),
            source: 'openf1',
            openF1Drivers: prov.drivers
          }
          provisional = true
        }
      }

      let rowsToPersist = fetched.rows
      const driversToUpsert = fetched.drivers
      const constructorsToUpsert = fetched.constructors
      const openF1Drivers = fetched.openF1Drivers

      if (rowsToPersist.length === 0) { summary.sessionsSkipped++; continue }

      // OpenF1's team_name strings drift mid-season ("Kick Sauber" →
      // "Stake F1 Team Kick Sauber"), and the derived constructor id would
      // create a duplicate row. For each row sourced from OpenF1, if the
      // driver has already been classified under a constructor this season,
      // reuse that canonical id instead. New teams (no prior result) take the
      // derived id and accept the cost of an alias being created — the
      // reconciliation pass will replace it with Jolpica's id soon enough.
      if (fetched.source === 'openf1') {
        rowsToPersist = await canonicaliseConstructorIds(rowsToPersist, ev.seasonYear)
      }

      // Drivers/constructors must exist before session_result rows reference them via FK.
      await upsertNewDrivers(driversToUpsert, wiki)
      await upsertNewConstructors(constructorsToUpsert, wiki)

      await resultsRepo.replaceForSession(
        ses.id!,
        rowsToPersist.map((r) => ({ ...r, sessionId: ses.id! })),
        fetched.source
      )
      // Provisional rows are persisted but the session stays 'scheduled' — it
      // remains a tick candidate so the next pass upgrades it to the official
      // OpenF1/Jolpica classification (which then marks it finished). A session
      // that is 'scheduled' yet has session_result rows is, by definition, the
      // provisional state; no extra flag needed.
      if (!provisional) {
        await sessionsRepo.markFinished(ses.id!)
        // Source=openf1 means we know this is provisional and the reconciliation
        // pass should pick it up. Clear any previous reconciled stamp so a
        // re-imported session gets re-reconciled. Source=jolpica is already the
        // official classification — stamp it immediately so the reconciler skips
        // it on its next pass.
        await sessionsRepo.setLastReconciledAt(
          ses.id!,
          fetched.source === 'jolpica' ? new Date() : null
        )
      }

      // Best-lap-with-sectors snapshot for the sector-color reference view on
      // the predict screen. For quali / sprint_quali we write one row per
      // (driver, knockout) so the Q1/Q2/Q3 columns get real sector tiers;
      // otherwise one row per driver (knockout=0). OpenF1-only; skip if the
      // session has no key. Failures here don't block the tick — the result
      // row is what matters for scoring; sector data is decorative.
      if (ses.openf1SessionKey != null) {
        try {
          const lapsRaw = await openf1.getLaps(ses.openf1SessionKey)
          const drvForLaps = openF1Drivers
            ?? parseOpenF1Drivers(await openf1.getDrivers(ses.openf1SessionKey) ?? [])
          if (ses.type === 'qualifying' || ses.type === 'sprint_quali') {
            const persistedResults = await resultsRepo.listForSession(ses.id!)
            const best = parseKnockoutBestLapsPerDriver(lapsRaw, drvForLaps, persistedResults)
            await bestLapsRepo.replaceForSession(ses.id!, best)
          } else {
            const best = parseBestLapsPerDriver(lapsRaw, drvForLaps)
            await bestLapsRepo.replaceForSession(ses.id!, best)
          }
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

      if (provisional) {
        summary.sessionsProvisional++
        // Don't set anyFinished — provisional results don't change the official
        // F1 driver/constructor standings (those come from Jolpica), so there's
        // nothing to refresh there. The per-session rescore below is what feeds
        // the leaderboard.
      } else {
        summary.sessionsFinished++
        anyFinished = true
      }
      try {
        const rescore = await rescoreSession(ses.id!)
        console.log(provisional ? 'Rescored session (provisional)' : 'Rescored session', { sessionId: ses.id, ...rescore })
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
      await refreshStandings(jolpica, wiki)
    } catch (err) {
      summary.errors++
      console.error('Standings refresh error', err)
    }
  }

  return summary
}
