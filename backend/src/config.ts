import { z } from 'zod'

const Env = z.object({
  DATABASE_URL: z.string().url(),
  ADMIN_TOKEN: z.string().min(1),
  NODE_ENV: z.enum(['development', 'production', 'test']).default('development'),
  PORT: z.coerce.number().int().positive().default(3000),
  JOLPICA_BASE: z.string().url().default('https://api.jolpi.ca/ergast'),
  WIKIPEDIA_BASE: z.string().url().default('https://en.wikipedia.org')
})

export type Config = {
  databaseUrl: string
  adminToken: string
  nodeEnv: 'development' | 'production' | 'test'
  port: number
  jolpicaBase: string
  wikipediaBase: string
}

export function parseConfig(env: Record<string, string | undefined>): Config {
  const parsed = Env.parse(env)
  return {
    databaseUrl: parsed.DATABASE_URL,
    adminToken: parsed.ADMIN_TOKEN,
    nodeEnv: parsed.NODE_ENV,
    port: parsed.PORT,
    jolpicaBase: parsed.JOLPICA_BASE,
    wikipediaBase: parsed.WIKIPEDIA_BASE
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
