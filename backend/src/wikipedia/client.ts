import { config } from '../config.js'

export type FetchFn = typeof fetch

export class WikipediaClient {
  constructor(
    private base = config.wikipediaBase,
    private fetchFn: FetchFn = fetch
  ) {}

  async getImageUrl(wikipediaUrl: string | null): Promise<string | null> {
    if (!wikipediaUrl) return null
    const title = this.titleFromUrl(wikipediaUrl)
    if (!title) return null
    const url = `${this.base}/w/api.php?action=query&titles=${encodeURIComponent(title)}&prop=pageimages&pithumbsize=400&format=json`
    try {
      const res = await this.fetchFn(url, {
        headers: { 'User-Agent': 'f1pg-backend/0.1 (https://github.com/SirAntonySir/F1predictiongame)' }
      })
      if (!res.ok) return null
      const json = (await res.json()) as { query?: { pages?: Record<string, { thumbnail?: { source?: string } }> } }
      const pages = json.query?.pages ?? {}
      for (const page of Object.values(pages)) {
        if (page.thumbnail?.source) return page.thumbnail.source
      }
      return null
    } catch {
      return null
    }
  }

  private titleFromUrl(url: string): string | null {
    try {
      const u = new URL(url)
      if (!u.hostname.endsWith('wikipedia.org')) return null
      const m = u.pathname.match(/^\/wiki\/(.+)$/)
      return m && m[1] ? decodeURIComponent(m[1]) : null
    } catch {
      return null
    }
  }
}
