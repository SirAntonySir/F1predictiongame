import { drizzle } from 'drizzle-orm/node-postgres'
import pg from 'pg'
import { config } from '../config.js'

let _pool: pg.Pool | undefined
export function getPool(): pg.Pool {
  return _pool ??= new pg.Pool({ connectionString: config.databaseUrl })
}

// Backward-compat lazy accessor — preserves `pool.query(...)` consumer API.
export const pool: pg.Pool = new Proxy({} as pg.Pool, {
  get(_t, key) {
    const target = getPool() as unknown as Record<PropertyKey, unknown>
    const value = target[key]
    return typeof value === 'function' ? (value as Function).bind(target) : value
  }
})

let _db: ReturnType<typeof drizzle> | undefined
function getDb() {
  return _db ??= drizzle(getPool())
}

export const db: ReturnType<typeof drizzle> = new Proxy({} as ReturnType<typeof drizzle>, {
  get(_t, key) {
    const target = getDb() as unknown as Record<PropertyKey, unknown>
    const value = target[key]
    return typeof value === 'function' ? (value as Function).bind(target) : value
  }
})

export async function pingDb(): Promise<boolean> {
  try {
    await getPool().query('SELECT 1')
    return true
  } catch {
    return false
  }
}

// Test-only: close the pool so process can exit cleanly between test files.
export async function _resetPoolForTests(): Promise<void> {
  if (_pool) {
    await _pool.end()
    _pool = undefined
    _db = undefined
  }
}
