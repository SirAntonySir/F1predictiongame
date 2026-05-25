import { describe, it, expect } from 'vitest'
import { buildApp } from '../../src/index.js'

describe('GET /api/health', () => {
  it('returns ok when DB is reachable', async () => {
    const app = await buildApp({ scheduler: null })
    const res = await app.inject({ method: 'GET', url: '/api/health' })
    expect(res.statusCode).toBe(200)
    const body = res.json()
    expect(body.ok).toBe(true)
    expect(body.db).toBe('up')
    expect(body).toHaveProperty('lastTickAt', null)
    expect(body).toHaveProperty('lastTickStatus', null)
    await app.close()
  })
})
