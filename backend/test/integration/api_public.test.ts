import { describe, it, expect, beforeEach } from 'vitest'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { buildApp } from '../../src/index.js'
import { runBootstrap } from '../../src/crawler/bootstrap.js'
import { JolpicaClient } from '../../src/jolpica/client.js'

function jolpicaScheduleFetch() {
  return async () => new Response(
    readFileSync(resolve('test/fixtures/jolpica/schedule-2024.json'), 'utf8'),
    { status: 200 }
  )
}

describe('public read routes', () => {
  beforeEach(async () => {
    const client = new JolpicaClient('https://x', jolpicaScheduleFetch())
    await runBootstrap(client, 2024)
  })

  it('GET /api/seasons/current returns the current season', async () => {
    const app = await buildApp({ scheduler: null })
    const res = await app.inject({ method: 'GET', url: '/api/seasons/current' })
    expect(res.statusCode).toBe(200)
    expect(res.json()).toMatchObject({ year: 2024, isCurrent: true })
    await app.close()
  })

  it('GET /api/events lists events with sessions', async () => {
    const app = await buildApp({ scheduler: null })
    const res = await app.inject({ method: 'GET', url: '/api/events' })
    expect(res.statusCode).toBe(200)
    const body = res.json()
    expect(body.length).toBeGreaterThan(20)
    expect(body[0].sessions.length).toBeGreaterThan(0)
    await app.close()
  })

  it('GET /api/events/:round returns one event or 404', async () => {
    const app = await buildApp({ scheduler: null })
    const ok = await app.inject({ method: 'GET', url: '/api/events/1' })
    expect(ok.statusCode).toBe(200)
    expect(ok.json().round).toBe(1)
    const miss = await app.inject({ method: 'GET', url: '/api/events/999' })
    expect(miss.statusCode).toBe(404)
    await app.close()
  })

  it('GET /api/events/:round rejects non-numeric round with 400', async () => {
    const app = await buildApp({ scheduler: null })
    const res = await app.inject({ method: 'GET', url: '/api/events/foo' })
    expect(res.statusCode).toBe(400)
    await app.close()
  })

  it('GET /api/next-session returns 200 or 404 depending on date', async () => {
    const app = await buildApp({ scheduler: null })
    const res = await app.inject({ method: 'GET', url: '/api/next-session' })
    // After bootstrapping 2024 in 2026, all sessions are past — expect 404.
    // Future-dated bootstrap data could return 200. Either is acceptable.
    expect([200, 404]).toContain(res.statusCode)
    await app.close()
  })

  it('GET /api/sessions/:id returns 400 on non-numeric id', async () => {
    const app = await buildApp({ scheduler: null })
    const res = await app.inject({ method: 'GET', url: '/api/sessions/abc' })
    expect(res.statusCode).toBe(400)
    await app.close()
  })

  it('GET /api/sessions/:id returns 404 on unknown id', async () => {
    const app = await buildApp({ scheduler: null })
    const res = await app.inject({ method: 'GET', url: '/api/sessions/999999' })
    expect(res.statusCode).toBe(404)
    await app.close()
  })

  it('GET /api/standings/drivers returns [] when no standings have been refreshed', async () => {
    const app = await buildApp({ scheduler: null })
    const res = await app.inject({ method: 'GET', url: '/api/standings/drivers' })
    expect(res.statusCode).toBe(200)
    expect(res.json()).toEqual([])
    await app.close()
  })

  it('GET /api/drivers/:code returns 404 for unknown', async () => {
    const app = await buildApp({ scheduler: null })
    const res = await app.inject({ method: 'GET', url: '/api/drivers/XYZ' })
    expect(res.statusCode).toBe(404)
    await app.close()
  })

  it('GET /api/constructors/:id returns 404 for unknown', async () => {
    const app = await buildApp({ scheduler: null })
    const res = await app.inject({ method: 'GET', url: '/api/constructors/nope' })
    expect(res.statusCode).toBe(404)
    await app.close()
  })
})
