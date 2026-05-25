import { describe, it, expect } from 'vitest'
import * as users from '../../src/repo/users.js'

describe('users repo', () => {
  it('inserts a user and returns it', async () => {
    const u = await users.insertUser({
      email: 'anton@example.com',
      passwordHash: 'hash',
      displayName: 'Anton'
    })
    expect(u.id).toMatch(/^[0-9a-f-]{36}$/)
    expect(u.email).toBe('anton@example.com')
    expect(u.displayName).toBe('Anton')
  })

  it('rejects duplicate email', async () => {
    await users.insertUser({ email: 'a@x.com', passwordHash: 'h', displayName: 'A' })
    await expect(
      users.insertUser({ email: 'a@x.com', passwordHash: 'h2', displayName: 'B' })
    ).rejects.toThrow(/duplicate|unique/i)
  })

  it('finds user by email (with password hash)', async () => {
    await users.insertUser({ email: 'find@x.com', passwordHash: 'secret', displayName: 'F' })
    const u = await users.findByEmailWithSecret('find@x.com')
    expect(u?.passwordHash).toBe('secret')
  })

  it('returns null for missing email', async () => {
    const u = await users.findByEmailWithSecret('nope@x.com')
    expect(u).toBeNull()
  })

  it('finds user by id (without password hash)', async () => {
    const created = await users.insertUser({ email: 'by@x.com', passwordHash: 'h', displayName: 'B' })
    const found = await users.findById(created.id)
    expect(found?.id).toBe(created.id)
    expect((found as any)?.passwordHash).toBeUndefined()
  })

  it('updates display name', async () => {
    const u = await users.insertUser({ email: 'up@x.com', passwordHash: 'h', displayName: 'Old' })
    const updated = await users.updateDisplayName(u.id, 'New')
    expect(updated.displayName).toBe('New')
  })
})
