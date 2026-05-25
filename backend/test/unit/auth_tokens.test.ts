import { describe, it, expect } from 'vitest'
import { generateToken, hashToken } from '../../src/auth/tokens.js'

describe('tokens', () => {
  it('generates a base64url token of ~43 chars', () => {
    const t = generateToken()
    expect(t).toMatch(/^[A-Za-z0-9_-]+$/)
    expect(t.length).toBeGreaterThanOrEqual(42)
    expect(t.length).toBeLessThanOrEqual(44)
  })

  it('generates unique tokens', () => {
    const a = generateToken()
    const b = generateToken()
    expect(a).not.toBe(b)
  })

  it('hashes deterministically with sha256, returning a 32-byte Buffer', () => {
    const t = 'abc'
    const h1 = hashToken(t)
    const h2 = hashToken(t)
    expect(h1.equals(h2)).toBe(true)
    expect(h1.length).toBe(32)
  })
})
