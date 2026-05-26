import * as eventsRepo from '../repo/events.js'
import * as sessionsRepo from '../repo/sessions.js'
import * as resultsRepo from '../repo/results.js'
import * as standingsRepo from '../repo/standings.js'
import * as picksRepo from '../repo/preseasonPicks.js'
import * as preseasonStandingsRepo from '../repo/preseasonStandings.js'
import * as leagueMembersRepo from '../repo/leagueMembers.js'
import * as usersRepo from '../repo/users.js'
import {
  deriveMostDnfs, derivePolesitter, deriveMostFastestLaps,
  deriveWdcWcc, deriveFinalStandings,
} from './derive.js'
import { scorePreseasonCategory } from './index.js'
import { scoreStandings } from './standings.js'
import type { PreseasonCategory, SessionResultRow, DriverStanding, ConstructorStanding } from '../domain/types.js'
import type { StoredSession } from '../repo/sessions.js'

export type PickPair = { driverCode: string | null; constructorId: string | null }

export type ProjectedTruths = {
  surprise: PickPair | null
  disappointment: PickPair | null
  dnf: PickPair
  poles: PickPair
  fastest_lap: PickPair
  wdc_wcc: PickPair
  standings: { drivers: string[]; constructors: string[] }
}

export type CategoryProjection = {
  category: PreseasonCategory
  myPick: PickPair
  projectedTruth: PickPair | null
  projectedPoints: number
  max: number
}

export type StandingsProjection = {
  myDriverPicks: { position: number; driverCode: string }[]
  myConstructorPicks: { position: number; constructorId: string }[]
  projectedDriverOrder: string[]
  projectedConstructorOrder: string[]
  projectedPoints: number
  max: number
}

export type LeaguePreseasonView = {
  seasonYear: number
  isLocked: boolean
  me: {
    categories: CategoryProjection[]
    standings: StandingsProjection
    projectedPointsTotal: number
  }
  leaderboard: { userId: string; displayName: string; preseasonPointsProjected: number }[]
}

const ALL_CATEGORIES: PreseasonCategory[] = [
  'surprise', 'disappointment', 'dnf', 'poles', 'fastest_lap', 'wdc_wcc',
]

// Each single-pick category awards up to 4 (driver) + 4 (team) = 8 points.
const CATEGORY_MAX: Record<PreseasonCategory, number> = {
  surprise: 8,
  disappointment: 8,
  dnf: 8,
  poles: 8,
  fastest_lap: 8,
  wdc_wcc: 8,
}

const DRIVER_POINTS_PER_SLOT = 3
const CONSTRUCTOR_POINTS_PER_SLOT = 4

export function projectTruthsFromSnapshot(
  results: SessionResultRow[],
  sessions: StoredSession[],
  drivers: DriverStanding[],
  constructors: ConstructorStanding[],
): ProjectedTruths {
  const finals = deriveFinalStandings(drivers, constructors)
  return {
    surprise: null,
    disappointment: null,
    dnf:         deriveMostDnfs(results, sessions),
    poles:       derivePolesitter(results, sessions),
    fastest_lap: deriveMostFastestLaps(results, sessions),
    wdc_wcc:     deriveWdcWcc(drivers, constructors),
    standings: {
      drivers: finals.drivers.map((d) => d.entityId),
      constructors: finals.constructors.map((c) => c.entityId),
    },
  }
}

export function projectCategoryScore(
  category: PreseasonCategory,
  pick: PickPair,
  truth: PickPair | null,
): { projectedPoints: number } {
  if (truth === null) return { projectedPoints: 0 }
  const breakdown = scorePreseasonCategory(category, pick, truth)
  return { projectedPoints: breakdown.pointsTotal }
}

async function loadSeasonSnapshot(seasonYear: number) {
  const events = await eventsRepo.listForSeason(seasonYear)
  const allSessions: StoredSession[] = []
  const allResults: SessionResultRow[] = []
  for (const ev of events) {
    const sessions = await sessionsRepo.listForEvent(ev.id)
    allSessions.push(...sessions)
    for (const s of sessions) {
      const rows = await resultsRepo.listForSession(s.id)
      allResults.push(...rows)
    }
  }
  const drivers = await standingsRepo.listDriverStandings(seasonYear)
  const constructors = await standingsRepo.listConstructorStandings(seasonYear)
  return { allResults, allSessions, drivers, constructors }
}

async function getPreseasonLockTime(seasonYear: number): Promise<Date | null> {
  const ev = await eventsRepo.getByRound(seasonYear, 1)
  if (!ev) return null
  const sessions = await sessionsRepo.listForEvent(ev.id)
  if (sessions.length === 0) return null
  return sessions.sort((a, b) => a.scheduledStart.getTime() - b.scheduledStart.getTime())[0]!.scheduledStart
}

function truthFor(cat: PreseasonCategory, truths: ProjectedTruths): PickPair | null {
  switch (cat) {
    case 'surprise':       return truths.surprise
    case 'disappointment': return truths.disappointment
    case 'dnf':            return truths.dnf
    case 'poles':          return truths.poles
    case 'fastest_lap':    return truths.fastest_lap
    case 'wdc_wcc':        return truths.wdc_wcc
  }
}

async function aggregateMemberPreseason(
  userId: string,
  seasonYear: number,
  truths: ProjectedTruths,
  finalDriverEntries: { position: number; entityId: string }[],
  finalConstructorEntries: { position: number; entityId: string }[],
): Promise<number> {
  let total = 0
  for (const cat of ALL_CATEGORIES) {
    const pick = await picksRepo.getPick(userId, seasonYear, cat)
    const proj = projectCategoryScore(
      cat,
      { driverCode: pick?.driverCode ?? null, constructorId: pick?.constructorId ?? null },
      truthFor(cat, truths),
    )
    total += proj.projectedPoints
  }
  const dps = await preseasonStandingsRepo.listDriverPicks(userId, seasonYear)
  const cps = await preseasonStandingsRepo.listConstructorPicks(userId, seasonYear)
  total += scoreStandings(dps, cps, finalDriverEntries, finalConstructorEntries).pointsTotal
  return total
}

export async function buildLeaguePreseasonView(
  leagueId: string,
  userId: string,
  seasonYear: number,
): Promise<LeaguePreseasonView> {
  const lockAt = await getPreseasonLockTime(seasonYear)
  const isLocked = lockAt !== null && lockAt.getTime() <= Date.now()
  const snap = await loadSeasonSnapshot(seasonYear)
  const truths = projectTruthsFromSnapshot(
    snap.allResults, snap.allSessions, snap.drivers, snap.constructors,
  )
  const finals = deriveFinalStandings(snap.drivers, snap.constructors)

  // ---- me.categories
  const myCategories: CategoryProjection[] = []
  for (const cat of ALL_CATEGORIES) {
    const pick = await picksRepo.getPick(userId, seasonYear, cat)
    const myPick: PickPair = {
      driverCode: pick?.driverCode ?? null,
      constructorId: pick?.constructorId ?? null,
    }
    const truth = truthFor(cat, truths)
    const proj = projectCategoryScore(cat, myPick, truth)
    myCategories.push({
      category: cat,
      myPick,
      projectedTruth: truth,
      projectedPoints: proj.projectedPoints,
      max: CATEGORY_MAX[cat],
    })
  }

  // ---- me.standings
  const myDriverPicksRaw = await preseasonStandingsRepo.listDriverPicks(userId, seasonYear)
  const myConstructorPicksRaw = await preseasonStandingsRepo.listConstructorPicks(userId, seasonYear)
  const standingsBreakdown = scoreStandings(
    myDriverPicksRaw, myConstructorPicksRaw, finals.drivers, finals.constructors,
  )
  const standingsMax =
    snap.drivers.length * DRIVER_POINTS_PER_SLOT +
    snap.constructors.length * CONSTRUCTOR_POINTS_PER_SLOT
  const meStandings: StandingsProjection = {
    myDriverPicks: myDriverPicksRaw.map((p) => ({ position: p.position, driverCode: p.entityId })),
    myConstructorPicks: myConstructorPicksRaw.map((p) => ({ position: p.position, constructorId: p.entityId })),
    projectedDriverOrder: truths.standings.drivers,
    projectedConstructorOrder: truths.standings.constructors,
    projectedPoints: standingsBreakdown.pointsTotal,
    max: standingsMax,
  }

  const projectedPointsTotal =
    myCategories.reduce((s, c) => s + c.projectedPoints, 0) + meStandings.projectedPoints

  // ---- leaderboard (aggregate only — picks not exposed)
  const memberViews = await leagueMembersRepo.listByLeague(leagueId)
  const leaderboard: LeaguePreseasonView['leaderboard'] = []
  for (const mv of memberViews) {
    const u = await usersRepo.findById(mv.userId)
    if (!u) continue
    const total = await aggregateMemberPreseason(
      mv.userId, seasonYear, truths, finals.drivers, finals.constructors,
    )
    leaderboard.push({
      userId: mv.userId,
      displayName: u.displayName,
      preseasonPointsProjected: total,
    })
  }
  leaderboard.sort((a, b) =>
    b.preseasonPointsProjected - a.preseasonPointsProjected || a.displayName.localeCompare(b.displayName))

  return {
    seasonYear,
    isLocked,
    me: {
      categories: myCategories,
      standings: meStandings,
      projectedPointsTotal,
    },
    leaderboard,
  }
}
