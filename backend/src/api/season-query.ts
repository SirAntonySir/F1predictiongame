import { ApiError } from './errors.js'
import * as seasonsRepo from '../repo/seasons.js'

/** Read an optional `?season=YYYY` query param, falling back to `fallback`. */
export function seasonFromQuery(q: unknown, fallback: number): number {
  const s = (q as { season?: unknown } | undefined)?.season
  if (s === undefined) return fallback
  const n = Number(s)
  if (!Number.isFinite(n)) throw new ApiError('BAD_REQUEST', 'season must be a number')
  return n
}

/** Resolve the season for a read route: `?season=YYYY` or the current season. */
export async function resolveSeason(q: unknown): Promise<number> {
  const cur = await seasonsRepo.getCurrent()
  return seasonFromQuery(q, cur?.year ?? new Date().getUTCFullYear())
}
