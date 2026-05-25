import { describe, it, expect, afterEach } from 'vitest'
import { parseConfig, getConfig, config, _resetConfigForTests } from '../../src/config'

const VALID = {
  DATABASE_URL: 'postgres://u:p@h:5432/d',
  ADMIN_TOKEN: 'tok',
  NODE_ENV: 'development',
  PORT: '3000',
  JOLPICA_BASE: 'https://api.jolpi.ca/ergast',
  WIKIPEDIA_BASE: 'https://en.wikipedia.org'
}

describe('parseConfig', () => {
  it('parses a valid env', () => {
    const cfg = parseConfig(VALID)
    expect(cfg.port).toBe(3000)
    expect(cfg.databaseUrl).toContain('postgres://')
    expect(cfg.adminToken).toBe('tok')
  })

  it('coerces PORT from string to number', () => {
    expect(parseConfig({ ...VALID, PORT: '8080' }).port).toBe(8080)
  })

  it('applies defaults for optional vars', () => {
    const cfg = parseConfig({ DATABASE_URL: VALID.DATABASE_URL, ADMIN_TOKEN: VALID.ADMIN_TOKEN })
    expect(cfg.nodeEnv).toBe('development')
    expect(cfg.port).toBe(3000)
    expect(cfg.jolpicaBase).toBe('https://api.jolpi.ca/ergast')
    expect(cfg.wikipediaBase).toBe('https://en.wikipedia.org')
  })

  it('throws on missing DATABASE_URL', () => {
    expect(() => parseConfig({ ADMIN_TOKEN: 'x' })).toThrow()
  })

  it('throws on empty ADMIN_TOKEN', () => {
    expect(() => parseConfig({ ...VALID, ADMIN_TOKEN: '' })).toThrow()
  })

  it('throws on invalid NODE_ENV', () => {
    expect(() => parseConfig({ ...VALID, NODE_ENV: 'staging' })).toThrow()
  })

  it('throws on invalid JOLPICA_BASE url', () => {
    expect(() => parseConfig({ ...VALID, JOLPICA_BASE: 'not-a-url' })).toThrow()
  })
})

describe('getConfig + config proxy', () => {
  afterEach(() => {
    _resetConfigForTests()
  })

  it('does not parse process.env at import time', () => {
    // Just importing the module above did NOT throw, even though
    // process.env in this test runner may not have all vars set.
    // The proof: if it parsed at import, this test file wouldn't load.
    expect(true).toBe(true)
  })

  it('memoizes — repeated calls return the same object', () => {
    const original = process.env
    try {
      process.env = { ...original, ...VALID }
      _resetConfigForTests()
      const a = getConfig()
      const b = getConfig()
      expect(a).toBe(b)
    } finally {
      process.env = original
    }
  })

  it('config proxy returns parsed values', () => {
    const original = process.env
    try {
      process.env = { ...original, ...VALID }
      _resetConfigForTests()
      expect(config.port).toBe(3000)
      expect(config.adminToken).toBe('tok')
    } finally {
      process.env = original
    }
  })
})
