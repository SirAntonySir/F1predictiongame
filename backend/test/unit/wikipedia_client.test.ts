import { describe, it, expect } from 'vitest'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { WikipediaClient } from '../../src/wikipedia/client.js'

function fixtureFetch(name: string) {
  const body = readFileSync(resolve('test/fixtures/wikipedia', name), 'utf8')
  return async () => new Response(body, { status: 200 })
}

describe('WikipediaClient.getImageUrl', () => {
  it('returns the thumbnail URL when present', async () => {
    const c = new WikipediaClient('https://en.wikipedia.org', fixtureFetch('verstappen.json'))
    const url = await c.getImageUrl('https://en.wikipedia.org/wiki/Max_Verstappen')
    expect(url).toMatch(/^https?:\/\//)
  })

  it('returns null when no image present', async () => {
    const c = new WikipediaClient('https://en.wikipedia.org', fixtureFetch('notfound.json'))
    const url = await c.getImageUrl('https://en.wikipedia.org/wiki/DefinitelyNotARealPersonXYZ')
    expect(url).toBeNull()
  })

  it('returns null when given a non-wikipedia URL', async () => {
    const c = new WikipediaClient('https://en.wikipedia.org', async () => new Response('', { status: 200 }))
    const url = await c.getImageUrl('https://example.com/foo')
    expect(url).toBeNull()
  })

  it('returns null when given null', async () => {
    const c = new WikipediaClient('https://en.wikipedia.org', async () => new Response('', { status: 200 }))
    expect(await c.getImageUrl(null)).toBeNull()
  })

  it('returns null on fetch error (network failure)', async () => {
    const c = new WikipediaClient('https://en.wikipedia.org', async () => { throw new Error('econnreset') })
    expect(await c.getImageUrl('https://en.wikipedia.org/wiki/Max_Verstappen')).toBeNull()
  })

  it('returns null on non-200 response', async () => {
    const c = new WikipediaClient('https://en.wikipedia.org', async () => new Response('', { status: 500 }))
    expect(await c.getImageUrl('https://en.wikipedia.org/wiki/Max_Verstappen')).toBeNull()
  })
})
