import * as users from '../../src/repo/users.js'
import * as leagues from '../../src/repo/leagues.js'
import * as sessions from '../../src/repo/sessions.js'
import * as predictionsRepo from '../../src/repo/predictions.js'
import * as preseasonPicks from '../../src/repo/preseasonPicks.js'
import * as preseasonStandingsRepo from '../../src/repo/preseasonStandings.js'
import * as subjectiveTruthRepo from '../../src/repo/subjectiveTruth.js'
import { hashPassword } from '../../src/auth/password.js'
import type { SessionType, PreseasonCategory } from '../../src/domain/types.js'

let n = 0
const seq = () => ++n

export async function makeUser(overrides: Partial<{ email: string; password: string; displayName: string }> = {}) {
  const i = seq()
  const password = overrides.password ?? 'hunter22'
  return users.insertUser({
    email: overrides.email ?? `user${i}-${Date.now()}@example.com`,
    passwordHash: await hashPassword(password),
    displayName: overrides.displayName ?? `User ${i}`
  })
}

export async function makeLeague(ownerUserId: string, overrides: Partial<{ name: string; joinCode: string }> = {}) {
  const i = seq()
  return leagues.createLeagueWithOwner({
    name: overrides.name ?? `League ${i}`,
    ownerUserId,
    joinCode: overrides.joinCode ?? `LG${String(i).padStart(4, '0')}`.slice(0, 6)
  })
}

export async function makeSession(
  eventId: number,
  type: SessionType = 'race',
  overrides: Partial<{ scheduledStart: Date; scheduledEnd: Date }> = {}
) {
  const start = overrides.scheduledStart ?? new Date(Date.now() + 24 * 60 * 60 * 1000)
  const end = overrides.scheduledEnd ?? new Date(start.getTime() + 2 * 60 * 60 * 1000)
  return sessions.upsertSession({
    eventId, type, scheduledStart: start, scheduledEnd: end, status: 'scheduled'
  })
}

export async function makePrediction(
  userId: string,
  sessionId: number,
  picks: { position: number; driverCode: string }[]
) {
  return predictionsRepo.upsertPredictionWithPicks(userId, sessionId, picks)
}

export async function makePreseasonPick(
  userId: string,
  seasonYear: number,
  category: PreseasonCategory,
  values: { driverCode?: string | null; constructorId?: string | null } = {}
) {
  return preseasonPicks.upsertPick(userId, seasonYear, category, {
    driverCode: values.driverCode ?? null,
    constructorId: values.constructorId ?? null
  })
}

export async function makePreseasonStandings(
  userId: string,
  seasonYear: number,
  kind: 'driver' | 'constructor',
  orderedIds: string[]
) {
  const picks = orderedIds.map((id, i) => ({ position: i + 1, entityId: id }))
  if (kind === 'driver') return preseasonStandingsRepo.replaceDriverPicks(userId, seasonYear, picks)
  return preseasonStandingsRepo.replaceConstructorPicks(userId, seasonYear, picks)
}

export async function setSubjectiveTruth(
  seasonYear: number,
  fields: Partial<{
    surpriseDriverCode: string
    surpriseConstructorId: string
    disappointmentDriverCode: string
    disappointmentConstructorId: string
  }>
) {
  return subjectiveTruthRepo.upsertTruth(seasonYear, {
    surpriseDriverCode: fields.surpriseDriverCode ?? null,
    surpriseConstructorId: fields.surpriseConstructorId ?? null,
    disappointmentDriverCode: fields.disappointmentDriverCode ?? null,
    disappointmentConstructorId: fields.disappointmentConstructorId ?? null
  })
}
