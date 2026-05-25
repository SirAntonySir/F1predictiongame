import { describe, it, expect } from 'vitest'
import * as users from '../../src/repo/users.js'
import * as sessions from '../../src/repo/appSessions.js'
import { hashToken } from '../../src/auth/tokens.js'
import { sweepExpiredSessions } from '../../src/auth/sweeper.js'

describe('session sweeper', () => {
  it('deletes only expired sessions', async () => {
    const u = await users.insertUser({ email: 'sw@x.com', passwordHash: 'h', displayName: 'S' })
    await sessions.insertSession({ userId: u.id, tokenHash: hashToken('exp1'), expiresAt: new Date(Date.now() - 1000), userAgent: null })
    await sessions.insertSession({ userId: u.id, tokenHash: hashToken('exp2'), expiresAt: new Date(Date.now() - 1000), userAgent: null })
    await sessions.insertSession({ userId: u.id, tokenHash: hashToken('live'), expiresAt: new Date(Date.now() + 60_000), userAgent: null })

    const removed = await sweepExpiredSessions()
    expect(removed).toBe(2)

    expect(await sessions.findByTokenHash(hashToken('exp1'))).toBeNull()
    expect(await sessions.findByTokenHash(hashToken('live'))).not.toBeNull()
  })
})
