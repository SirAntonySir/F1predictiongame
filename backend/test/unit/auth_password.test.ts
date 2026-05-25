import { describe, it, expect } from 'vitest'
import { hashPassword, verifyPassword } from '../../src/auth/password.js'

describe('password', () => {
  it('hashes and verifies a password', async () => {
    const hash = await hashPassword('hunter22')
    expect(hash).not.toBe('hunter22')
    expect(await verifyPassword('hunter22', hash)).toBe(true)
  })

  it('rejects a wrong password', async () => {
    const hash = await hashPassword('hunter22')
    expect(await verifyPassword('hunter23', hash)).toBe(false)
  })

  it('produces different hashes for the same input (salted)', async () => {
    const a = await hashPassword('abc')
    const b = await hashPassword('abc')
    expect(a).not.toBe(b)
  })
})
