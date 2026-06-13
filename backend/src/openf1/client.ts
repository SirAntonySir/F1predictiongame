import { config } from '../config.js'

export type FetchFn = typeof fetch

const sleep = (ms: number) => new Promise<void>((r) => setTimeout(r, ms))

export class OpenF1Client {
  constructor(
    private base = config.openf1Base,
    private fetchFn: FetchFn = fetch
  ) {}

  // OpenF1 throttles aggressively (HTTP 429 after ~3 req/s). 429 used to be
  // swallowed as "no data" along with 404, so tight backfill loops would
  // silently report empty results for half the season. Retry 429 with
  // exponential backoff before falling back to the "no data" convention.
  private async getJson(path: string): Promise<unknown | null> {
    const url = `${this.base}${path}`
    const maxAttempts = 5
    let delay = 500
    for (let attempt = 1; attempt <= maxAttempts; attempt++) {
      const res = await this.fetchFn(url, { headers: { Accept: 'application/json' } })
      if (res.status === 429) {
        if (attempt === maxAttempts) {
          throw new Error(`OpenF1 429 for ${path} after ${maxAttempts} attempts`)
        }
        const retryAfter = Number(res.headers.get('retry-after'))
        const wait = Number.isFinite(retryAfter) && retryAfter > 0 ? retryAfter * 1000 : delay
        await sleep(wait)
        delay = Math.min(delay * 2, 8000)
        continue
      }
      // 4xx (non-429) = "no data" (same convention as JolpicaClient — session
      // not found, etc.)
      if (res.status >= 400 && res.status < 500) return null
      if (!res.ok) throw new Error(`OpenF1 ${res.status} for ${path}`)
      return res.json()
    }
    return null
  }

  getSessions(year: number) {
    return this.getJson(`/sessions?year=${year}`)
  }
  getDrivers(sessionKey: number) {
    return this.getJson(`/drivers?session_key=${sessionKey}`)
  }
  getSessionResult(sessionKey: number) {
    return this.getJson(`/session_result?session_key=${sessionKey}`)
  }

  getPosition(sessionKey: number) {
    return this.getJson(`/position?session_key=${sessionKey}`)
  }

  // All laps in a session, with per-sector durations and pit-out flags.
  getLaps(sessionKey: number) {
    return this.getJson(`/laps?session_key=${sessionKey}`)
  }
}
