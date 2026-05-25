import * as sessionsRepo from '../repo/appSessions.js'

export async function sweepExpiredSessions(): Promise<number> {
  return sessionsRepo.deleteExpired()
}
