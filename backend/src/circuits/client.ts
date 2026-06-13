/// HTTP client for julesr0y/f1-circuits-svg upstream — pulls circuits.json
/// and individual SVG files. Same fetch-as-injected-dep pattern used by
/// JolpicaClient so we can swap a fake in tests.
import { config } from '../config.js'

export type FetchFn = typeof fetch

export type UpstreamCircuit = {
  id: string
  name: string
  countryId?: string | null
  latitude?: number | null
  longitude?: number | null
  layouts: { layoutId: string; seasons: string }[]
}

export type SvgDetail = 'detailed' | 'minimal'
export type SvgVariant = 'black' | 'white' | 'black-outline' | 'white-outline'
export const ALL_DETAILS: SvgDetail[] = ['detailed', 'minimal']
export const ALL_VARIANTS: SvgVariant[] = ['black', 'white', 'black-outline', 'white-outline']

export class CircuitsClient {
  constructor(
    private base = config.circuitsBase,
    private fetchFn: FetchFn = fetch
  ) {}

  private async getText(path: string): Promise<string | null> {
    const url = `${this.base}${path}`
    const res = await this.fetchFn(url, { headers: { Accept: 'image/svg+xml,application/json' } })
    if (res.status === 404) return null
    if (!res.ok) throw new Error(`Circuits upstream ${res.status} for ${path}`)
    return res.text()
  }

  async getCircuitsJson(): Promise<UpstreamCircuit[]> {
    const raw = await this.getText('/circuits.json')
    if (!raw) throw new Error('circuits.json not found upstream')
    return JSON.parse(raw) as UpstreamCircuit[]
  }

  /// Returns null when the variant isn't published for that layout (404).
  /// Older / minor layouts often only have a subset of the eight variants.
  async getSvg(layoutId: string, detail: SvgDetail, variant: SvgVariant): Promise<string | null> {
    return this.getText(`/circuits/${detail}/${variant}/${layoutId}.svg`)
  }
}
