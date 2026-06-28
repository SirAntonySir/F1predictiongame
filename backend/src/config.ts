import { z } from 'zod'

const Env = z.object({
  DATABASE_URL: z.string().url(),
  TEST_DATABASE_URL: z.string().url().optional(),
  ADMIN_TOKEN: z.string().min(1),
  NODE_ENV: z.enum(['development', 'production', 'test']).default('development'),
  PORT: z.coerce.number().int().positive().default(3000),
  JOLPICA_BASE: z.string().url().default('https://api.jolpi.ca/ergast'),
  WIKIPEDIA_BASE: z.string().url().default('https://en.wikipedia.org'),
  OPENF1_BASE: z.string().url().default('https://api.openf1.org/v1'),
  // Static-asset source for F1 circuit metadata + SVGs (julesr0y repo on
  // GitHub). Override in tests to point at a local fixture server.
  CIRCUITS_BASE: z.string().url().default('https://raw.githubusercontent.com/julesr0y/f1-circuits-svg/main'),
  // Firebase service-account JSON (one line) for FCM sends. Unset → the
  // notification dispatcher runs but skips sending (local dev / not yet wired).
  FIREBASE_SERVICE_ACCOUNT: z.string().optional()
})

export type Config = {
  databaseUrl: string
  adminToken: string
  nodeEnv: 'development' | 'production' | 'test'
  port: number
  jolpicaBase: string
  wikipediaBase: string
  openf1Base: string
  circuitsBase: string
  firebaseServiceAccount?: string
}

export function parseConfig(env: Record<string, string | undefined>): Config {
  const parsed = Env.parse(env)
  // When running under vitest (or any NODE_ENV=test invocation), prefer the
  // dedicated test DB if configured. This keeps the dev DB from being wiped
  // by integration tests that truncate every table between cases.
  const databaseUrl = parsed.NODE_ENV === 'test' && parsed.TEST_DATABASE_URL
    ? parsed.TEST_DATABASE_URL
    : parsed.DATABASE_URL
  return {
    databaseUrl,
    adminToken: parsed.ADMIN_TOKEN,
    nodeEnv: parsed.NODE_ENV,
    port: parsed.PORT,
    jolpicaBase: parsed.JOLPICA_BASE,
    wikipediaBase: parsed.WIKIPEDIA_BASE,
    openf1Base: parsed.OPENF1_BASE,
    circuitsBase: parsed.CIRCUITS_BASE,
    firebaseServiceAccount: parsed.FIREBASE_SERVICE_ACCOUNT
  }
}

let _cached: Config | undefined
export function getConfig(): Config {
  return _cached ??= parseConfig(process.env)
}

// Test-only: clear the memoized config so a subsequent getConfig()
// re-reads process.env. Not for production code.
export function _resetConfigForTests(): void {
  _cached = undefined
}

// Lazy proxy: consumers can write `config.databaseUrl` without
// triggering a process.env parse at import time. The parse runs on
// first field access.
export const config: Config = new Proxy({} as Config, {
  get(_target, key) {
    return getConfig()[key as keyof Config]
  }
})
