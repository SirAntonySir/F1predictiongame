/// Pulls circuit metadata + SVGs from the julesr0y/f1-circuits-svg repo and
/// mirrors them into the local DB. Idempotent — re-running just refreshes
/// `fetchedAt` and any updated SVG bytes.
///
/// "currentLayoutId" per circuit = the layout whose `seasons` string covers
/// the latest year. Upstream `seasons` strings look like "2003-2024", "2024",
/// or comma-separated lists like "1995,1957,1959,1961-1962" — we parse and
/// pick the layout whose max year is highest.
import { CircuitsClient, ALL_DETAILS, ALL_VARIANTS, type UpstreamCircuit } from './client.js'
import * as circuitsRepo from '../repo/circuits.js'

export type CrawlSummary = {
  circuitsUpserted: number
  svgsFetched: number
  svgsMissing: number
  errors: number
}

function maxYearIn(seasons: string): number {
  // "2003-2024,2026"  →  2026
  // "2024"            →  2024
  let max = 0
  for (const part of seasons.split(',').map((s) => s.trim()).filter(Boolean)) {
    const m = part.match(/^(\d{4})(?:-(\d{4}))?$/)
    if (!m) continue
    const a = Number(m[1])
    const b = m[2] ? Number(m[2]) : a
    if (b > max) max = b
  }
  return max
}

export function pickCurrentLayoutId(c: UpstreamCircuit): string | null {
  if (c.layouts.length === 0) return null
  let bestId: string | null = null
  let bestYear = -Infinity
  for (const l of c.layouts) {
    const y = maxYearIn(l.seasons)
    if (y > bestYear) { bestYear = y; bestId = l.layoutId }
  }
  return bestId
}

export type CrawlOpts = {
  /// When non-null only sync circuits whose currentLayoutId's max year is
  /// at least this. Cuts the workload from ~80 historical circuits to ~24
  /// currently-active ones.
  minSeason?: number
  /// Layout ids to limit the SVG fetch to. Default: only the
  /// currentLayoutId. Set to 'all' to mirror every historical layout.
  layouts?: 'current' | 'all'
}

export async function runCircuitsCrawl(
  client: CircuitsClient = new CircuitsClient(),
  opts: CrawlOpts = {}
): Promise<CrawlSummary> {
  const summary: CrawlSummary = { circuitsUpserted: 0, svgsFetched: 0, svgsMissing: 0, errors: 0 }
  const list = await client.getCircuitsJson()
  const minSeason = opts.minSeason ?? 2018  // covers every circuit on the modern grid
  const layoutsMode = opts.layouts ?? 'current'

  for (const c of list) {
    const currentLayoutId = pickCurrentLayoutId(c)
    const latestSeasonsYear = currentLayoutId
      ? maxYearIn(c.layouts.find((l) => l.layoutId === currentLayoutId)!.seasons)
      : 0
    if (latestSeasonsYear < minSeason) continue   // skip pre-modern grid history

    await circuitsRepo.upsertCircuit({
      id: c.id,
      name: c.name,
      countryId: c.countryId ?? null,
      latitude: c.latitude ?? null,
      longitude: c.longitude ?? null,
      currentLayoutId
    })
    summary.circuitsUpserted++

    const layoutsToFetch = layoutsMode === 'all'
      ? c.layouts.map((l) => l.layoutId)
      : (currentLayoutId ? [currentLayoutId] : [])

    for (const layoutId of layoutsToFetch) {
      for (const detail of ALL_DETAILS) {
        for (const variant of ALL_VARIANTS) {
          try {
            const svg = await client.getSvg(layoutId, detail, variant)
            if (svg == null) { summary.svgsMissing++; continue }
            await circuitsRepo.upsertSvg({
              circuitId: c.id, layoutId, detail, variant, svg
            })
            summary.svgsFetched++
          } catch (err) {
            summary.errors++
            console.error('SVG fetch failed', { layoutId, detail, variant, err })
          }
        }
      }
    }
  }
  return summary
}
