import * as eventsRepo from '../repo/events.js'
import * as sessionsRepo from '../repo/sessions.js'
import * as resultsRepo from '../repo/results.js'
import * as standingsRepo from '../repo/standings.js'
import * as picksRepo from '../repo/preseasonPicks.js'
import * as preseasonStandingsRepo from '../repo/preseasonStandings.js'
import * as truthRepo from '../repo/subjectiveTruth.js'
import * as scoresRepo from '../repo/scores.js'
import { scorePreseasonCategory, scoreStandings } from './index.js'
import {
  deriveMostDnfs, derivePolesitter, deriveMostFastestLaps, deriveWdcWcc, deriveFinalStandings
} from './derive.js'
import type { PreseasonCategory } from '../domain/types.js'

export type RescoreSummary = { users: number; totalPoints: number }

const ALL_SINGLE_CATEGORIES: PreseasonCategory[] = [
  'surprise', 'disappointment', 'dnf', 'poles', 'fastest_lap', 'wdc_wcc'
]

export async function rescorePreseasonForSeason(seasonYear: number): Promise<RescoreSummary> {
  // Need events + sessions of the season for the derive layer (which gates by session type)
  const events = await eventsRepo.listForSeason(seasonYear)
  if (events.length === 0) return { users: 0, totalPoints: 0 }
  const allSessions: Awaited<ReturnType<typeof sessionsRepo.listForEvent>> = []
  const allResults = []
  for (const ev of events) {
    const sessions = await sessionsRepo.listForEvent(ev.id)
    allSessions.push(...sessions)
    for (const s of sessions) {
      const rows = await resultsRepo.listForSession(s.id)
      allResults.push(...rows)
    }
  }
  const driverStandings = await standingsRepo.listDriverStandings(seasonYear)
  const constructorStandings = await standingsRepo.listConstructorStandings(seasonYear)

  // Derive observed truths
  const dnfPair    = deriveMostDnfs(allResults, allSessions)
  const polesPair  = derivePolesitter(allResults, allSessions)
  const flPair     = deriveMostFastestLaps(allResults, allSessions)
  const wdcWccPair = deriveWdcWcc(driverStandings, constructorStandings)
  const finalStandings = deriveFinalStandings(driverStandings, constructorStandings)

  // Subjective truth (may be null)
  const subjective = await truthRepo.getTruth(seasonYear)
  const surpriseTruth = {
    driverCode: subjective?.surpriseDriverCode ?? null,
    constructorId: subjective?.surpriseConstructorId ?? null
  }
  const disappointmentTruth = {
    driverCode: subjective?.disappointmentDriverCode ?? null,
    constructorId: subjective?.disappointmentConstructorId ?? null
  }

  // Find all users with at least one preseason pick (single or standings) for this season
  const allPicks = await picksRepo.listForSeason(seasonYear)
  const usersWithPicks = new Set(allPicks.map((p) => p.userId))
  // Also include users with standings picks (the listForSeason query above only sees single-picks)
  // Cheap approach: query the standings tables and union
  const standingsDriverUsers = await usersWithDriverStandings(seasonYear)
  const standingsCtorUsers = await usersWithConstructorStandings(seasonYear)
  for (const id of standingsDriverUsers) usersWithPicks.add(id)
  for (const id of standingsCtorUsers) usersWithPicks.add(id)

  let totalPoints = 0
  for (const userId of usersWithPicks) {
    // 6 single-pick categories
    for (const category of ALL_SINGLE_CATEGORIES) {
      const pick = await picksRepo.getPick(userId, seasonYear, category)
      const truth = truthForCategory(category, { dnfPair, polesPair, flPair, wdcWccPair, surpriseTruth, disappointmentTruth })
      const pickInput = {
        driverCode: pick?.driverCode ?? null,
        constructorId: pick?.constructorId ?? null
      }
      const breakdown = scorePreseasonCategory(category, pickInput, truth)
      await scoresRepo.upsertPreseasonScore(userId, seasonYear, category, breakdown.pointsTotal, breakdown)
      totalPoints += breakdown.pointsTotal
    }
    // Standings category
    const driverPicks = await preseasonStandingsRepo.listDriverPicks(userId, seasonYear)
    const constructorPicks = await preseasonStandingsRepo.listConstructorPicks(userId, seasonYear)
    const standingsBreakdown = scoreStandings(driverPicks, constructorPicks, finalStandings.drivers, finalStandings.constructors)
    await scoresRepo.upsertPreseasonScore(userId, seasonYear, 'standings', standingsBreakdown.pointsTotal, standingsBreakdown)
    totalPoints += standingsBreakdown.pointsTotal
  }

  return { users: usersWithPicks.size, totalPoints }
}

function truthForCategory(
  category: PreseasonCategory,
  data: {
    dnfPair: { driverCode: string | null; constructorId: string | null }
    polesPair: { driverCode: string | null; constructorId: string | null }
    flPair: { driverCode: string | null; constructorId: string | null }
    wdcWccPair: { driverCode: string | null; constructorId: string | null }
    surpriseTruth: { driverCode: string | null; constructorId: string | null }
    disappointmentTruth: { driverCode: string | null; constructorId: string | null }
  }
): { driverCode: string | null; constructorId: string | null } {
  switch (category) {
    case 'surprise':       return data.surpriseTruth
    case 'disappointment': return data.disappointmentTruth
    case 'dnf':            return data.dnfPair
    case 'poles':          return data.polesPair
    case 'fastest_lap':    return data.flPair
    case 'wdc_wcc':        return data.wdcWccPair
  }
}

// Small helpers — could live in standings repo but only used here. Inline for now.
async function usersWithDriverStandings(seasonYear: number): Promise<string[]> {
  const { getDb } = await import('../db/client.js')
  const { sql } = await import('drizzle-orm')
  const { preseasonPickStandingsDriver } = await import('../db/schema.js')
  const db = getDb()
  const rows = await db.execute(sql`SELECT DISTINCT user_id::text AS "userId" FROM ${preseasonPickStandingsDriver} WHERE season_year = ${seasonYear}`)
  return (rows as unknown as { rows: { userId: string }[] }).rows.map((r) => r.userId)
}

async function usersWithConstructorStandings(seasonYear: number): Promise<string[]> {
  const { getDb } = await import('../db/client.js')
  const { sql } = await import('drizzle-orm')
  const { preseasonPickStandingsConstructor } = await import('../db/schema.js')
  const db = getDb()
  const rows = await db.execute(sql`SELECT DISTINCT user_id::text AS "userId" FROM ${preseasonPickStandingsConstructor} WHERE season_year = ${seasonYear}`)
  return (rows as unknown as { rows: { userId: string }[] }).rows.map((r) => r.userId)
}
