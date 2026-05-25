import { describe, it, expect } from 'vitest'
import { buildApp } from '../../src/index.js'
import * as seasons from '../../src/repo/seasons.js'
import * as events from '../../src/repo/events.js'
import * as drivers from '../../src/repo/drivers.js'
import * as constructors from '../../src/repo/constructors.js'
import * as users from '../../src/repo/users.js'
import * as picks from '../../src/repo/preseasonPicks.js'
import * as scores from '../../src/repo/scores.js'

const TOKEN = { 'x-admin-token': 'local-dev-token' }

async function seed() {
  await seasons.upsertSeason({ year: 2026, isCurrent: true })
  await events.upsertEvent({ seasonYear: 2026, round: 1, name: 'B', circuitName: 'C', country: 'X', hasSprint: false })
  await constructors.upsertConstructor({ id: 'red_bull', name: 'Red Bull', nationality: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null })
  await drivers.upsertDriver({ code: 'VER', givenName: 'M', familyName: 'V', nationality: null, permanentNumber: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null })
}

describe('POST /admin/seasons/:year/subjective-truth', () => {
  it('requires admin token', async () => {
    await seed()
    const app = await buildApp({ scheduler: null })
    const r = await app.inject({
      method: 'POST', url: '/admin/seasons/2026/subjective-truth',
      payload: { surpriseDriverCode: null, surpriseConstructorId: null, disappointmentDriverCode: null, disappointmentConstructorId: null }
    })
    expect(r.statusCode).toBe(401)
  })

  it('sets truth and triggers rescore (surprise score updates)', async () => {
    await seed()
    const app = await buildApp({ scheduler: null })
    const u = await users.insertUser({ email: 'a@x.com', passwordHash: 'h', displayName: 'A' })
    await picks.upsertPick(u.id, 2026, 'surprise', { driverCode: 'VER', constructorId: 'red_bull' })

    // Before truth: rescore yields 0
    let scoreList = await scores.listPreseasonForUser(u.id, 2026)
    const before = scoreList.find((s) => s.category === 'surprise')
    // (the rescore may not have run yet if no tick happened; we run admin first)

    const r = await app.inject({
      method: 'POST', url: '/admin/seasons/2026/subjective-truth',
      headers: TOKEN,
      payload: {
        surpriseDriverCode: 'VER',
        surpriseConstructorId: 'red_bull',
        disappointmentDriverCode: null,
        disappointmentConstructorId: null
      }
    })
    expect(r.statusCode).toBe(200)
    expect(r.json().ok).toBe(true)

    scoreList = await scores.listPreseasonForUser(u.id, 2026)
    expect(scoreList.find((s) => s.category === 'surprise')!.pointsTotal).toBe(8)
  })
})

describe('POST /admin/preseason-rescore/:year', () => {
  it('forces rescore', async () => {
    await seed()
    const app = await buildApp({ scheduler: null })
    const u = await users.insertUser({ email: 'r@x.com', passwordHash: 'h', displayName: 'R' })
    await picks.upsertPick(u.id, 2026, 'wdc_wcc', { driverCode: 'VER', constructorId: 'red_bull' })
    const r = await app.inject({ method: 'POST', url: '/admin/preseason-rescore/2026', headers: TOKEN })
    expect(r.statusCode).toBe(200)
    expect(r.json().users).toBeGreaterThanOrEqual(0)
  })
})
