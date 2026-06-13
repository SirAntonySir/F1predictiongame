import { describe, it, expect } from 'vitest'
import { buildApp } from '../../src/index.js'
import * as circuitsRepo from '../../src/repo/circuits.js'

async function newApp() {
  return buildApp({ scheduler: null } as any)
}

const SAMPLE_SVG = '<svg xmlns="http://www.w3.org/2000/svg"><path d="M0 0"/></svg>'

async function seed() {
  await circuitsRepo.upsertCircuit({
    id: 'monaco', name: 'Circuit de Monaco', countryId: 'monaco',
    latitude: 43.7347, longitude: 7.4206, currentLayoutId: 'monaco-6'
  })
  await circuitsRepo.upsertSvg({
    circuitId: 'monaco', layoutId: 'monaco-6',
    detail: 'detailed', variant: 'white', svg: SAMPLE_SVG
  })
}

describe('GET /api/circuits', () => {
  it('lists circuits', async () => {
    await seed()
    const app = await newApp()
    const r = await app.inject({ method: 'GET', url: '/api/circuits' })
    expect(r.statusCode).toBe(200)
    expect(r.json().some((c: any) => c.id === 'monaco')).toBe(true)
  })
})

describe('GET /api/circuits/:id', () => {
  it('returns the circuit', async () => {
    await seed()
    const app = await newApp()
    const r = await app.inject({ method: 'GET', url: '/api/circuits/monaco' })
    expect(r.statusCode).toBe(200)
    expect(r.json().name).toBe('Circuit de Monaco')
    expect(r.json().currentLayoutId).toBe('monaco-6')
  })

  it('404s for unknown ids', async () => {
    const app = await newApp()
    const r = await app.inject({ method: 'GET', url: '/api/circuits/unobtanium' })
    expect(r.statusCode).toBe(404)
  })
})

describe('GET /api/circuits/:id/svg', () => {
  it('returns the SVG with the right Content-Type when defaults match', async () => {
    await seed()
    const app = await newApp()
    const r = await app.inject({ method: 'GET', url: '/api/circuits/monaco/svg' })
    expect(r.statusCode).toBe(200)
    expect(r.headers['content-type']).toContain('image/svg+xml')
    expect(r.body).toContain('<svg')
  })

  it('404s when the requested variant is not stored', async () => {
    await seed()
    const app = await newApp()
    const r = await app.inject({
      method: 'GET',
      url: '/api/circuits/monaco/svg?detail=minimal&variant=black-outline'
    })
    expect(r.statusCode).toBe(404)
  })
})
