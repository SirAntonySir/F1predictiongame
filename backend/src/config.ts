import { z } from 'zod'

const Env = z.object({
  DATABASE_URL: z.string().url().or(z.string().startsWith('postgres://')),
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

export const config: Config = parseConfig(process.env)
