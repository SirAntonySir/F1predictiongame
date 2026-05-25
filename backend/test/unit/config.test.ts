import { describe, it, expect } from 'vitest'
import { parseConfig } from '../../src/config'

describe('parseConfig', () => {
  it('parses a valid env', () => {
    const cfg = parseConfig({
      DATABASE_URL: 'postgres://u:p@h:5432/d',
      ADMIN_TOKEN: 'tok',
      NODE_ENV: 'development',
      PORT: '3000',
      JOLPICA_BASE: 'https://api.jolpi.ca/ergast',
      WIKIPEDIA_BASE: 'https://en.wikipedia.org'
    })
    expect(cfg.port).toBe(3000)
    expect(cfg.databaseUrl).toContain('postgres://')
    expect(cfg.adminToken).toBe('tok')
  })

  it('throws on missing DATABASE_URL', () => {
    expect(() => parseConfig({ ADMIN_TOKEN: 'x' })).toThrow()
  })
})
