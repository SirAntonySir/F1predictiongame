import { describe, it, expect } from 'vitest'
import * as users from '../../src/repo/users.js'
import * as sessions from '../../src/repo/appSessions.js'
import { hashToken } from '../../src/auth/tokens.js'

async function makeUser() {
  return users.insertUser({ email: `u-${Date.now()}-${Math.random()}@x.com`, passwordHash: 'h', displayName: 'U' })
}

describe('app sessions repo', () => {
  it('inserts a session and finds it by token hash', async () => {
    const u = await makeUser()
    const th = hashToken('raw-token')
    const expiresAt = new Date(Date.now() + 90 * 24 * 60 * 60 * 1000)
    const s = await sessions.insertSession({ userId: u.id, tokenHash: th, expiresAt, userAgent: 'jest' })
    expect(s.userId).toBe(u.id)

    const found = await sessions.findByTokenHash(th)
    expect(found?.id).toBe(s.id)
  })

  it('returns null for unknown token hash', async () => {
    const found = await sessions.findByTokenHash(hashToken('nope'))
    expect(found).toBeNull()
  })

  it('slides expiry on touch', async () => {
    const u = await makeUser()
    const th = hashToken('t')
    const oldExpiry = new Date(Date.now() + 1000)
    const s = await sessions.insertSession({ userId: u.id, tokenHash: th, expiresAt: oldExpiry, userAgent: null })

    const newExpiry = new Date(Date.now() + 90 * 24 * 60 * 60 * 1000)
    await sessions.touchSession(s.id, newExpiry)

    const found = await sessions.findByTokenHash(th)
    expect(found!.expiresAt.getTime()).toBeGreaterThan(oldExpiry.getTime())
  })

  it('deletes a session by id', async () => {
    const u = await makeUser()
    const th = hashToken('d')
    const s = await sessions.insertSession({ userId: u.id, tokenHash: th, expiresAt: new Date(Date.now() + 1000), userAgent: null })
    await sessions.deleteById(s.id)
    expect(await sessions.findByTokenHash(th)).toBeNull()
  })

  it('deletes expired sessions in bulk', async () => {
    const u = await makeUser()
    await sessions.insertSession({ userId: u.id, tokenHash: hashToken('a'), expiresAt: new Date(Date.now() - 1000), userAgent: null })
    await sessions.insertSession({ userId: u.id, tokenHash: hashToken('b'), expiresAt: new Date(Date.now() - 1000), userAgent: null })
    await sessions.insertSession({ userId: u.id, tokenHash: hashToken('c'), expiresAt: new Date(Date.now() + 60_000), userAgent: null })
    const deleted = await sessions.deleteExpired()
    expect(deleted).toBe(2)
  })

  it('cascades when user is deleted', async () => {
    const u = await makeUser()
    const th = hashToken('cascade')
    await sessions.insertSession({ userId: u.id, tokenHash: th, expiresAt: new Date(Date.now() + 1000), userAgent: null })
    await users.deleteById(u.id)
    expect(await sessions.findByTokenHash(th)).toBeNull()
  })
})
