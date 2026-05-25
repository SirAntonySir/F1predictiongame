import { config } from '../config.js'

export type FetchFn = typeof fetch

export class JolpicaClient {
  constructor(
    private base = config.jolpicaBase,
    private fetchFn: FetchFn = fetch
  ) {}

  private async getJson(path: string): Promise<unknown | null> {
    const url = `${this.base}${path}`
    const res = await this.fetchFn(url, { headers: { Accept: 'application/json' } })
    // Treat 4xx as "no data" — Jolpica returns 400 for unsupported endpoints
    // (e.g. sprintQualifying) and 404 for unknown rounds. Both mean "no results".
    if (res.status >= 400 && res.status < 500) return null
    if (!res.ok) throw new Error(`Jolpica ${res.status} for ${path}`)
    return res.json()
  }

  getSeasonSchedule(year: number) {
    return this.getJson(`/f1/${year}.json`)
  }
  getRaceResults(year: number, round: number) {
    return this.getJson(`/f1/${year}/${round}/results.json`)
  }
  getQualifyingResults(year: number, round: number) {
    return this.getJson(`/f1/${year}/${round}/qualifying.json`)
  }
  getSprintResults(year: number, round: number) {
    return this.getJson(`/f1/${year}/${round}/sprint.json`)
  }
  getSprintQualifyingResults(year: number, round: number) {
    return this.getJson(`/f1/${year}/${round}/sprintQualifying.json`)
  }
  getDriverStandings(year: number) {
    return this.getJson(`/f1/${year}/driverStandings.json`)
  }
  getConstructorStandings(year: number) {
    return this.getJson(`/f1/${year}/constructorStandings.json`)
  }
}
