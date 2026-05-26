import { config } from '../config.js'

export type FetchFn = typeof fetch

export class OpenF1Client {
  constructor(
    private base = config.openf1Base,
    private fetchFn: FetchFn = fetch
  ) {}

  private async getJson(path: string): Promise<unknown | null> {
    const url = `${this.base}${path}`
    const res = await this.fetchFn(url, { headers: { Accept: 'application/json' } })
    // 4xx = "no data" (same convention as JolpicaClient — session not found, etc.)
    if (res.status >= 400 && res.status < 500) return null
    if (!res.ok) throw new Error(`OpenF1 ${res.status} for ${path}`)
    return res.json()
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
}
