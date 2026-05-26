import { describe, it, expect, beforeEach } from 'vitest'
import { buildApp } from '../../src/index.js'
import * as drivers from '../../src/repo/drivers.js'
import * as constructors from '../../src/repo/constructors.js'

let app: Awaited<ReturnType<typeof buildApp>>
beforeEach(async () => { app = await buildApp({ scheduler: null }) })

async function seedVerWithImages(opts: { override?: string | null; headshot?: string | null; image?: string | null }) {
  await drivers.upsertDriver({
    code: 'VER', givenName: 'Max', familyName: 'Verstappen',
    nationality: 'Dutch', permanentNumber: 33, wikipediaUrl: null,
    imageUrl: opts.image ?? null, imageUrlOverride: opts.override ?? null,
    headshotUrl: opts.headshot ?? null
  })
}

describe('GET /api/drivers/:code', () => {
  it('returns image = override when override is set', async () => {
    await seedVerWithImages({ override: 'OVER', headshot: 'HEAD', image: 'WIKI' })
    const res = await app.inject({ method: 'GET', url: '/api/drivers/VER' })
    expect(res.statusCode).toBe(200)
    expect(res.json().image).toBe('OVER')
  })
  it('returns image = headshot when override is null and headshot is set', async () => {
    await seedVerWithImages({ headshot: 'HEAD', image: 'WIKI' })
    const res = await app.inject({ method: 'GET', url: '/api/drivers/VER' })
    expect(res.json().image).toBe('HEAD')
  })
  it('returns image = imageUrl when override and headshot are both null', async () => {
    await seedVerWithImages({ image: 'WIKI' })
    const res = await app.inject({ method: 'GET', url: '/api/drivers/VER' })
    expect(res.json().image).toBe('WIKI')
  })
  it('exposes headshotUrl on the payload alongside image', async () => {
    await seedVerWithImages({ headshot: 'HEAD' })
    const res = await app.inject({ method: 'GET', url: '/api/drivers/VER' })
    expect(res.json().headshotUrl).toBe('HEAD')
  })
})

describe('GET /api/constructors/:id', () => {
  it('exposes teamColour', async () => {
    await constructors.upsertConstructor({
      id: 'red_bull', name: 'Red Bull', nationality: 'Austrian',
      wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, teamColour: '1E41FF'
    })
    const res = await app.inject({ method: 'GET', url: '/api/constructors/red_bull' })
    expect(res.statusCode).toBe(200)
    expect(res.json().teamColour).toBe('1E41FF')
  })
})
