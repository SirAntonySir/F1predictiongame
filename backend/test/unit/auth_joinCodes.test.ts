import { describe, it, expect } from 'vitest'
import { generateJoinCode, generateUniqueJoinCode } from '../../src/auth/joinCodes.js'

describe('joinCodes', () => {
  it('generates a 6-char uppercase-alphanumeric code', () => {
    for (let i = 0; i < 50; i++) {
      const c = generateJoinCode()
      expect(c).toMatch(/^[A-Z0-9]{8}$/)
    }
  })

  it('retries on collision via isTaken callback', async () => {
    const seen = new Set<string>()
    let calls = 0
    const code = await generateUniqueJoinCode(async (c) => {
      calls++
      if (calls < 3) { seen.add(c); return true }
      return false
    })
    expect(calls).toBe(3)
    expect(seen.has(code)).toBe(false)
  })

  it('throws after 10 unique attempts', async () => {
    await expect(generateUniqueJoinCode(async () => true)).rejects.toThrow(/unique join code/i)
  })
})
