import * as users from '../../src/repo/users.js'
import * as leagues from '../../src/repo/leagues.js'
import { hashPassword } from '../../src/auth/password.js'

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
