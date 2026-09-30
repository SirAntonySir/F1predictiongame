import { describe, it, expect } from 'vitest'
import xlsxPkg from 'xlsx'
import { buildApp } from '../../src/index.js'
import * as seasons from '../../src/repo/seasons.js'
import * as events from '../../src/repo/events.js'
import * as sessions from '../../src/repo/sessions.js'
import * as drivers from '../../src/repo/drivers.js'
import * as constructors from '../../src/repo/constructors.js'
import * as predictions from '../../src/repo/predictions.js'
import * as results from '../../src/repo/results.js'
import { getDb } from '../../src/db/client.js'
import { prediction } from '../../src/db/schema.js'
import { eq, and } from 'drizzle-orm'

const XLSX = xlsxPkg as typeof xlsxPkg & {
  write: (wb: xlsxPkg.WorkBook, opts: { type: 'buffer'; bookType: 'xlsx' }) => Buffer
}

const YEAR = 2024

/// Season with 4 race rounds (jokers need a budget's worth of races), a
/// qualifying session on round 1, and results on the round-1 race so score
/// previews fire. Round 1 is named so the Excel header "Australia" maps to it.
async function seed() {
  await seasons.upsertSeason({ year: YEAR, isCurrent: false })
  await constructors.upsertConstructor({
    id: 'red_bull', name: 'Red Bull', nationality: null, wikipediaUrl: null,
    imageUrl: null, imageUrlOverride: null, teamColour: null
  })
  await constructors.upsertConstructor({
    id: 'ferrari', name: 'Ferrari', nationality: null, wikipediaUrl: null,
    imageUrl: null, imageUrlOverride: null, teamColour: null
  })
  for (const code of ['VER', 'NOR', 'LEC', 'HAM', 'RUS']) {
    await drivers.upsertDriver({
      code, givenName: code, familyName: code, nationality: null,
      permanentNumber: null, wikipediaUrl: null, imageUrl: null,
      imageUrlOverride: null, headshotUrl: null
    })
  }
  const raceSessions: number[] = []
  let quali = 0
  for (let round = 1; round <= 4; round++) {
    const ev = await events.upsertEvent({
      seasonYear: YEAR, round,
      name: round === 1 ? 'Australian Grand Prix' : `Round ${round} GP`,
      circuitName: 'C', country: 'XX', hasSprint: false
    })
    const rs = await sessions.upsertSession({
      eventId: ev.id, type: 'race',
      scheduledStart: new Date(YEAR, round, 2, 15),
      scheduledEnd: new Date(YEAR, round, 2, 17),
      status: 'finished', openf1SessionKey: null
    })
    raceSessions.push(rs.id)
    if (round === 1) {
      const qs = await sessions.upsertSession({
        eventId: ev.id, type: 'qualifying',
        scheduledStart: new Date(YEAR, round, 1, 15),
        scheduledEnd: new Date(YEAR, round, 1, 16),
        status: 'finished', openf1SessionKey: null
      })
      quali = qs.id
    }
  }
  const mk = (position: number, driverCode: string, constructorId: string) => ({
    sessionId: raceSessions[0]!, position, driverCode, driverName: driverCode,
    constructorId, constructorName: constructorId, raceTime: null, status: null,
    points: null, fastestLap: null, fastestLapTime: null, fastestLapSpeed: null,
    q1: null, q2: null, q3: null
  })
  await results.replaceForSession(raceSessions[0]!, [
    mk(1, 'VER', 'red_bull'), mk(2, 'NOR', 'ferrari'), mk(3, 'LEC', 'ferrari'),
    mk(4, 'HAM', 'ferrari'), mk(5, 'RUS', 'ferrari')
  ])
  return { raceSessions, quali }
}

async function newApp() {
  return buildApp({ scheduler: null } as any)
}

async function signup(app: Awaited<ReturnType<typeof newApp>>, name: string) {
  const r = await app.inject({
    method: 'POST', url: '/api/auth/signup',
    payload: {
      email: `${name.toLowerCase()}-${Date.now()}-${Math.random().toString(36).slice(2, 8)}@x.com`,
      password: 'hunter22', displayName: name
    }
  })
  return { token: r.json().token as string, userId: r.json().user.id as string }
}

const auth = (t: string) => ({ authorization: `Bearer ${t}` })

async function makeLeague(app: Awaited<ReturnType<typeof newApp>>, memberNames: string[] = []) {
  const owner = await signup(app, 'owner')
  const lc = await app.inject({
    method: 'POST', url: '/api/leagues', headers: auth(owner.token), payload: { name: 'TestL' }
  })
  const leagueId = lc.json().league.id as string
  const joinCode = lc.json().league.joinCode as string
  const members: Record<string, { token: string; userId: string }> = {}
  for (const name of memberNames) {
    const m = await signup(app, name)
    await app.inject({ method: 'POST', url: '/api/leagues/join', headers: auth(m.token), payload: { joinCode } })
    members[name] = m
  }
  return { owner, leagueId, members }
}

const importBody = (leagueId: string, predictionRows: unknown[], overwrite = false) => ({
  schemaVersion: 1,
  league: { id: leagueId, name: 'TestL' },
  seasonYear: YEAR,
  overwrite,
  predictions: predictionRows
})

describe('imports: partial pick sets', () => {
  it('plans and applies a partial race set; engine scores the filled slots', async () => {
    const app = await newApp()
    const { raceSessions } = await seed()
    const { owner, leagueId, members } = await makeLeague(app, ['Pia'])
    const uid = members['Pia']!.userId

    const rows = [{
      userId: uid, sessionId: raceSessions[0],
      picks: [{ position: 1, driverCode: 'VER' }, { position: 2, driverCode: 'NOR' }]
    }]
    const dry = await app.inject({
      method: 'POST', url: `/api/leagues/${leagueId}/imports?dryRun=1`,
      headers: auth(owner.token), payload: importBody(leagueId, rows)
    })
    expect(dry.statusCode).toBe(200)
    expect(dry.json().skipped).toHaveLength(0)
    expect(dry.json().plan).toHaveLength(1)
    // VER exact (3) + NOR exact (3) + team bonus (2) = 8
    expect(dry.json().plan[0].previewPoints).toBe(8)

    const apply = await app.inject({
      method: 'POST', url: `/api/leagues/${leagueId}/imports`,
      headers: auth(owner.token), payload: importBody(leagueId, rows)
    })
    expect(apply.statusCode).toBe(200)
    expect(apply.json().applied.predictions).toBe(1)
    await app.close()
  })

  it('still rejects too many picks', async () => {
    const app = await newApp()
    const { quali } = await seed()
    const { owner, leagueId, members } = await makeLeague(app, ['Overfill'])
    const rows = [{
      userId: members['Overfill']!.userId, sessionId: quali,
      picks: [1, 2, 3].map((p, i) => ({ position: p, driverCode: ['VER', 'NOR', 'LEC'][i]! }))
    }]
    const dry = await app.inject({
      method: 'POST', url: `/api/leagues/${leagueId}/imports?dryRun=1`,
      headers: auth(owner.token), payload: importBody(leagueId, rows)
    })
    expect(dry.json().plan).toHaveLength(0)
    expect(dry.json().skipped[0].reason).toMatch(/too many picks/)
    await app.close()
  })
})

describe('imports: jokers', () => {
  const fivePicks = ['VER', 'NOR', 'LEC', 'HAM', 'RUS'].map((c, i) => ({ position: i + 1, driverCode: c }))

  it('applies joker rows with source=joker', async () => {
    const app = await newApp()
    const { raceSessions } = await seed()
    const { owner, leagueId, members } = await makeLeague(app, ['Joko'])
    const uid = members['Joko']!.userId

    const r = await app.inject({
      method: 'POST', url: `/api/leagues/${leagueId}/imports`,
      headers: auth(owner.token),
      payload: importBody(leagueId, [{ userId: uid, sessionId: raceSessions[1], picks: fivePicks, joker: true }])
    })
    expect(r.statusCode).toBe(200)
    const db = getDb()
    const [row] = await db.select({ source: prediction.source }).from(prediction)
      .where(and(eq(prediction.userId, uid), eq(prediction.sessionId, raceSessions[1]!)))
    expect(row!.source).toBe('joker')
    await app.close()
  })

  it('rejects joker on a non-race session', async () => {
    const app = await newApp()
    const { quali } = await seed()
    const { owner, leagueId, members } = await makeLeague(app, ['QJok'])
    const r = await app.inject({
      method: 'POST', url: `/api/leagues/${leagueId}/imports?dryRun=1`,
      headers: auth(owner.token),
      payload: importBody(leagueId, [{
        userId: members['QJok']!.userId, sessionId: quali,
        picks: [{ position: 1, driverCode: 'VER' }, { position: 2, driverCode: 'NOR' }], joker: true
      }])
    })
    expect(r.json().skipped[0].reason).toMatch(/joker only valid on race/)
    await app.close()
  })

  it('enforces the 3-per-season budget, counting jokers already in the DB', async () => {
    const app = await newApp()
    const { raceSessions } = await seed()
    const { owner, leagueId, members } = await makeLeague(app, ['Budget'])
    const uid = members['Budget']!.userId
    // One joker already spent outside this upload (round 1).
    await predictions.upsertPredictionWithPicks(uid, raceSessions[0]!, fivePicks, { source: 'joker' })

    const rows = [1, 2, 3].map((i) => ({ userId: uid, sessionId: raceSessions[i], picks: fivePicks, joker: true }))
    const dry = await app.inject({
      method: 'POST', url: `/api/leagues/${leagueId}/imports?dryRun=1`,
      headers: auth(owner.token), payload: importBody(leagueId, rows)
    })
    // budget 3, 1 used → rounds 2+3 kept, round 4 skipped
    expect(dry.json().plan).toHaveLength(2)
    expect(dry.json().skipped).toHaveLength(1)
    expect(dry.json().skipped[0].reason).toMatch(/joker budget exceeded/)
    expect(dry.json().skipped[0].sessionId).toBe(raceSessions[3])
    await app.close()
  })

  it('warns when non-joker race picks are identical to the previous race', async () => {
    const app = await newApp()
    const { raceSessions } = await seed()
    const { owner, leagueId, members } = await makeLeague(app, ['Copycat'])
    const uid = members['Copycat']!.userId
    await predictions.upsertPredictionWithPicks(uid, raceSessions[0]!, fivePicks)

    const dry = await app.inject({
      method: 'POST', url: `/api/leagues/${leagueId}/imports?dryRun=1`,
      headers: auth(owner.token),
      payload: importBody(leagueId, [{ userId: uid, sessionId: raceSessions[1], picks: fivePicks }])
    })
    expect(dry.json().warnings).toHaveLength(1)
    expect(dry.json().warnings[0].reason).toMatch(/identical to the previous race/)

    // Same row flagged as joker → no warning.
    const dry2 = await app.inject({
      method: 'POST', url: `/api/leagues/${leagueId}/imports?dryRun=1`,
      headers: auth(owner.token),
      payload: importBody(leagueId, [{ userId: uid, sessionId: raceSessions[1], picks: fivePicks, joker: true }])
    })
    expect(dry2.json().warnings).toHaveLength(0)
    await app.close()
  })

  it('re-uploads are no-ops: identical picks skip as unchanged, joker labels survive', async () => {
    const app = await newApp()
    const { raceSessions } = await seed()
    const { owner, leagueId, members } = await makeLeague(app, ['Rerun'])
    const uid = members['Rerun']!.userId
    // Existing joker row (e.g. set by the Baku fix) whose picks the Excel
    // also carries — a full-sheet re-upload must NOT flip it back to import.
    await predictions.upsertPredictionWithPicks(uid, raceSessions[1]!, fivePicks, { source: 'joker' })

    const r = await app.inject({
      method: 'POST', url: `/api/leagues/${leagueId}/imports`,
      headers: auth(owner.token),
      payload: importBody(leagueId, [{ userId: uid, sessionId: raceSessions[1], picks: fivePicks }])
    })
    expect(r.statusCode).toBe(200)
    expect(r.json().applied.predictions).toBe(0)
    expect(r.json().skipped[0].reason).toMatch(/existing joker row kept/)
    const db = getDb()
    const [row] = await db.select({ source: prediction.source }).from(prediction)
      .where(and(eq(prediction.userId, uid), eq(prediction.sessionId, raceSessions[1]!)))
    expect(row!.source).toBe('joker')

    // Identical picks + joker:true over a non-joker row IS applied (label fix).
    await predictions.upsertPredictionWithPicks(uid, raceSessions[2]!, fivePicks, { source: 'import' })
    const r2 = await app.inject({
      method: 'POST', url: `/api/leagues/${leagueId}/imports`,
      headers: auth(owner.token),
      payload: importBody(leagueId, [{ userId: uid, sessionId: raceSessions[2], picks: fivePicks, joker: true }])
    })
    expect(r2.json().applied.predictions).toBe(1)
    const [row2] = await db.select({ source: prediction.source }).from(prediction)
      .where(and(eq(prediction.userId, uid), eq(prediction.sessionId, raceSessions[2]!)))
    expect(row2!.source).toBe('joker')
    await app.close()
  })

  it('replaces an existing joker row silently (no overwrite flag needed)', async () => {
    const app = await newApp()
    const { raceSessions } = await seed()
    const { owner, leagueId, members } = await makeLeague(app, ['Silent'])
    const uid = members['Silent']!.userId
    await predictions.upsertPredictionWithPicks(uid, raceSessions[1]!, fivePicks, { source: 'joker' })

    const r = await app.inject({
      method: 'POST', url: `/api/leagues/${leagueId}/imports`,
      headers: auth(owner.token),
      payload: importBody(leagueId, [{
        userId: uid, sessionId: raceSessions[1],
        picks: [{ position: 1, driverCode: 'LEC' }, { position: 2, driverCode: 'HAM' }]
      }])
    })
    expect(r.statusCode).toBe(200)
    expect(r.json().applied.predictions).toBe(1)
    const db = getDb()
    const [row] = await db.select({ source: prediction.source }).from(prediction)
      .where(and(eq(prediction.userId, uid), eq(prediction.sessionId, raceSessions[1]!)))
    expect(row!.source).toBe('import')  // real picks replaced the joker → joker refunded
    await app.close()
  })
})

// ---- Excel upload ------------------------------------------------------------

/// Minimal but layout-correct Tippspiel workbook: race header "Australia" at
/// R68/C3, player "Jan" (first in PLAYERS_IN_ORDER) with quali + race picks
/// at rows 72/74, and the mandatory 11-constructor standings block for every
/// player. Driver standings + preseason labels stay empty (parser tolerates).
function buildWorkbook(): Buffer {
  const ws: Record<string, unknown> = {}
  const set = (row: number, col: number, v: string) => {
    ws[xlsxPkg.utils.encode_cell({ r: row - 1, c: col - 1 })] = { t: 's', v }
  }
  set(68, 3, 'Australia')
  // Jan: quali P1/P2 + race P1..P5 (P3 left blank → partial race set)
  set(72, 3, 'Ver'); set(72, 4, 'Nor')
  set(74, 3, 'Ver'); set(74, 4, 'Nor'); set(74, 6, 'Ham'); set(74, 7, 'Rus')
  const teams = ['McLaren', 'Merc', 'Ferrari', 'RedBull', 'Alpine', 'Haas', 'Vcarb', 'Audi', 'Williams', 'Cadillac', 'Aston']
  for (let player = 0; player < 11; player++) {
    for (let i = 0; i < 11; i++) set(33 + i, 3 + player * 4, teams[i]!)
  }
  ws['!ref'] = 'A1:CZ160'
  const wb: xlsxPkg.WorkBook = { SheetNames: [`Tippspiel ${YEAR}`], Sheets: { [`Tippspiel ${YEAR}`]: ws as xlsxPkg.WorkSheet } }
  return XLSX.write(wb, { type: 'buffer', bookType: 'xlsx' })
}

describe('POST /api/leagues/:id/imports/excel', () => {
  it('parses the workbook and runs it through the same pipeline', async () => {
    const app = await newApp()
    await seed()
    const { owner, leagueId } = await makeLeague(app, ['Jan'])

    const dry = await app.inject({
      method: 'POST', url: `/api/leagues/${leagueId}/imports/excel?season=${YEAR}&dryRun=1`,
      headers: { ...auth(owner.token), 'content-type': 'application/octet-stream' },
      payload: buildWorkbook()
    })
    expect(dry.statusCode).toBe(200)
    const body = dry.json()
    // Jan's quali + partial race row planned; other 10 Excel players unknown.
    expect(body.plan).toHaveLength(2)
    const race = body.plan.find((x: { sessionType: string }) => x.sessionType === 'race')
    expect(race.picks).toHaveLength(4)
    // VER +3, NOR +3, HAM P4 exact +3, RUS P5 exact +3, team bonus +2 = 14
    expect(race.previewPoints).toBe(14)
    expect(body.skipped.filter((s: { kind: string }) => s.kind === 'excel_player')).toHaveLength(10)

    const apply = await app.inject({
      method: 'POST', url: `/api/leagues/${leagueId}/imports/excel?season=${YEAR}`,
      headers: { ...auth(owner.token), 'content-type': 'application/octet-stream' },
      payload: buildWorkbook()
    })
    expect(apply.statusCode).toBe(200)
    expect(apply.json().applied.predictions).toBe(2)
    await app.close()
  })

  it('rejects a body that is not a workbook', async () => {
    const app = await newApp()
    await seed()
    const { owner, leagueId } = await makeLeague(app)
    const r = await app.inject({
      method: 'POST', url: `/api/leagues/${leagueId}/imports/excel?season=${YEAR}&dryRun=1`,
      headers: { ...auth(owner.token), 'content-type': 'application/octet-stream' },
      payload: Buffer.from('definitely not an xlsx')
    })
    expect(r.statusCode).toBeGreaterThanOrEqual(400)
    expect(r.statusCode).toBeLessThan(500)
    await app.close()
  })

  it('rejects non-owner', async () => {
    const app = await newApp()
    await seed()
    const { leagueId, members } = await makeLeague(app, ['Jan'])
    const r = await app.inject({
      method: 'POST', url: `/api/leagues/${leagueId}/imports/excel?season=${YEAR}&dryRun=1`,
      headers: { ...auth(members['Jan']!.token), 'content-type': 'application/octet-stream' },
      payload: buildWorkbook()
    })
    expect(r.statusCode).toBe(403)
    await app.close()
  })
})
