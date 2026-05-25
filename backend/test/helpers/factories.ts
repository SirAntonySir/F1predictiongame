import * as users from '../../src/repo/users.js'
import * as leagues from '../../src/repo/leagues.js'
import * as sessions from '../../src/repo/sessions.js'
import * as predictionsRepo from '../../src/repo/predictions.js'
import { hashPassword } from '../../src/auth/password.js'
import type { SessionType } from '../../src/domain/types.js'

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
