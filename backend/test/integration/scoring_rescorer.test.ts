import { describe, it, expect } from 'vitest'
import * as users from '../../src/repo/users.js'
import * as seasons from '../../src/repo/seasons.js'
import * as events from '../../src/repo/events.js'
import * as sessions from '../../src/repo/sessions.js'
import * as drivers from '../../src/repo/drivers.js'
import * as constructors from '../../src/repo/constructors.js'
import * as standings from '../../src/repo/standings.js'
import * as results from '../../src/repo/results.js'
import * as predictions from '../../src/repo/predictions.js'
import * as scores from '../../src/repo/scores.js'
import { rescoreSession } from '../../src/scoring/rescorer.js'

async function seedScene() {
  await seasons.upsertSeason({ year: 2026, isCurrent: true })
  const ev = await events.upsertEvent({
    seasonYear: 2026, round: 1, name: 'Bahrain', circuitName: 'BIC', country: 'Bahrain', hasSprint: false
  })
  const ses = await sessions.upsertSession({
    eventId: ev.id, type: 'race',
    scheduledStart: new Date(2026, 2, 8, 15),
    scheduledEnd: new Date(2026, 2, 8, 17), status: 'scheduled',
  openf1SessionKey: null
  })
  for (const c of [
    { id: 'red_bull', name: 'Red Bull' },
    { id: 'mercedes', name: 'Mercedes' },
    { id: 'mclaren',  name: 'McLaren' }
  ]) {
    await constructors.upsertConstructor({ ...c, nationality: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, teamColour: null })
  }
  for (const d of [
    { code: 'VER', team: 'red_bull' }, { code: 'PER', team: 'red_bull' },
    { code: 'HAM', team: 'mercedes' }, { code: 'RUS', team: 'mercedes' },
    { code: 'NOR', team: 'mclaren' },  { code: 'PIA', team: 'mclaren' }
  ]) {
    await drivers.upsertDriver({
      code: d.code, givenName: d.code, familyName: 'X', nationality: null, permanentNumber: null,
      wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, headshotUrl: null
    })
  }
  await standings.replaceDriverStandings(2026, [
    { seasonYear: 2026, driverCode: 'VER', position: 1, points: 0, wins: 0, constructorId: 'red_bull' },
    { seasonYear: 2026, driverCode: 'PER', position: 2, points: 0, wins: 0, constructorId: 'red_bull' },
    { seasonYear: 2026, driverCode: 'HAM', position: 3, points: 0, wins: 0, constructorId: 'mercedes' },
    { seasonYear: 2026, driverCode: 'RUS', position: 4, points: 0, wins: 0, constructorId: 'mercedes' },
    { seasonYear: 2026, driverCode: 'NOR', position: 5, points: 0, wins: 0, constructorId: 'mclaren' },
    { seasonYear: 2026, driverCode: 'PIA', position: 6, points: 0, wins: 0, constructorId: 'mclaren' }
  ])
  return ses
}

function resultRow(position: number, code: string, team: string) {
  return {
    sessionId: 0,  // overwritten by replaceForSession
    position, driverCode: code, driverName: code, constructorId: team, constructorName: team,
    raceTime: null, status: 'Finished', points: null,
    fastestLap: null, fastestLapTime: null, fastestLapSpeed: null,
    q1: null, q2: null, q3: null
  }
}

describe('rescoreSession', () => {
  it('writes score rows with breakdown for each predicting user', async () => {
    const ses = await seedScene()
    const u1 = await users.insertUser({ email: 'a@x.com', passwordHash: 'h', displayName: 'A' })
    const u2 = await users.insertUser({ email: 'b@x.com', passwordHash: 'h', displayName: 'B' })

    await predictions.upsertPredictionWithPicks(u1.id, ses.id, [
      { position: 1, driverCode: 'VER' },
      { position: 2, driverCode: 'HAM' },
      { position: 3, driverCode: 'NOR' },
      { position: 4, driverCode: 'PIA' },
      { position: 5, driverCode: 'RUS' }
    ])
    await predictions.upsertPredictionWithPicks(u2.id, ses.id, [
      { position: 1, driverCode: 'HAM' },
      { position: 2, driverCode: 'VER' },
      { position: 3, driverCode: 'NOR' },
      { position: 4, driverCode: 'PIA' },
      { position: 5, driverCode: 'RUS' }
    ])

    await results.replaceForSession(ses.id, [
      resultRow(1, 'VER', 'red_bull'),
      resultRow(2, 'HAM', 'mercedes'),
      resultRow(3, 'NOR', 'mclaren'),
      resultRow(4, 'PIA', 'mclaren'),
      resultRow(5, 'RUS', 'mercedes')
    ])

    const summary = await rescoreSession(ses.id)
    expect(summary.users).toBe(2)

    const u1Scores = await scores.listForUser(u1.id, 2026)
    expect(u1Scores[0]!.pointsTotal).toBe(17)  // all 5 exact + team bonus 2
    const u2Scores = await scores.listForUser(u2.id, 2026)
    // u2 swapped P1/P2 -> wrongPos+wrongPos (1+1) + 3+3+3 exact P3-5 + no team bonus (HAM is mercedes, winner VER is red_bull) = 11
    expect(u2Scores[0]!.pointsTotal).toBe(11)
  })

  it('is idempotent: re-running overwrites scores', async () => {
    const ses = await seedScene()
    const u = await users.insertUser({ email: 'i@x.com', passwordHash: 'h', displayName: 'I' })
    await predictions.upsertPredictionWithPicks(u.id, ses.id, [
      { position: 1, driverCode: 'VER' },
      { position: 2, driverCode: 'HAM' },
      { position: 3, driverCode: 'NOR' },
      { position: 4, driverCode: 'PIA' },
      { position: 5, driverCode: 'RUS' }
    ])
    await results.replaceForSession(ses.id, [resultRow(1, 'VER', 'red_bull')])
    await rescoreSession(ses.id)
    const first = (await scores.listForUser(u.id, 2026))[0]!.pointsTotal

    // Add more results - should change the score
    await results.replaceForSession(ses.id, [
      resultRow(1, 'VER', 'red_bull'),
      resultRow(2, 'HAM', 'mercedes'),
      resultRow(3, 'NOR', 'mclaren'),
      resultRow(4, 'PIA', 'mclaren'),
      resultRow(5, 'RUS', 'mercedes')
    ])
    await rescoreSession(ses.id)
    const second = (await scores.listForUser(u.id, 2026))[0]!.pointsTotal
    expect(second).toBeGreaterThan(first)
  })

  it('no-ops if session has no results', async () => {
    const ses = await seedScene()
    const u = await users.insertUser({ email: 'n@x.com', passwordHash: 'h', displayName: 'N' })
    await predictions.upsertPredictionWithPicks(u.id, ses.id, [
      { position: 1, driverCode: 'VER' },
      { position: 2, driverCode: 'HAM' },
      { position: 3, driverCode: 'NOR' },
      { position: 4, driverCode: 'PIA' },
      { position: 5, driverCode: 'RUS' }
    ])
    const summary = await rescoreSession(ses.id)
    expect(summary).toEqual({ users: 0, totalPoints: 0 })
    expect(await scores.listForUser(u.id, 2026)).toEqual([])
  })

  it('no-ops if session type is not scorable', async () => {
    await seasons.upsertSeason({ year: 2026, isCurrent: true })
    const ev = await events.upsertEvent({
      seasonYear: 2026, round: 1, name: 'Bahrain', circuitName: 'BIC', country: 'B', hasSprint: false
    })
    const fp = await sessions.upsertSession({
      eventId: ev.id, type: 'fp1',
      scheduledStart: new Date(2026, 0, 1), scheduledEnd: new Date(2026, 0, 1, 1), status: 'scheduled',
    openf1SessionKey: null
    })
    const summary = await rescoreSession(fp.id)
    expect(summary).toEqual({ users: 0, totalPoints: 0 })
  })

  it('team bonus uses standings for DNF picks', async () => {
    const ses = await seedScene()
    const u = await users.insertUser({ email: 't@x.com', passwordHash: 'h', displayName: 'T' })
    // User picks PER for P1; PER DNF; teammate VER wins -> team bonus should apply
    await predictions.upsertPredictionWithPicks(u.id, ses.id, [
      { position: 1, driverCode: 'PER' },
      { position: 2, driverCode: 'HAM' },
      { position: 3, driverCode: 'NOR' },
      { position: 4, driverCode: 'PIA' },
      { position: 5, driverCode: 'RUS' }
    ])
    // PER is absent from results (DNF before classification)
    await results.replaceForSession(ses.id, [
      resultRow(1, 'VER', 'red_bull'),
      resultRow(2, 'HAM', 'mercedes'),
      resultRow(3, 'NOR', 'mclaren'),
      resultRow(4, 'PIA', 'mclaren'),
      resultRow(5, 'RUS', 'mercedes')
    ])
    await rescoreSession(ses.id)
    const sc = (await scores.listForUser(u.id, 2026))[0]!
    // P1 PER no points (DNF, no exact, no wrongPos because not in finishers); P2-P5 all exact = 3*4 = 12; team bonus 2
    expect(sc.pointsTotal).toBe(14)
    expect(sc.breakdown.teamBonus).toEqual({ applied: true, points: 2 })
  })
})
