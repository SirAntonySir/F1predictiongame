import pg from 'pg'
import { drizzle } from 'drizzle-orm/node-postgres'
import { migrate } from 'drizzle-orm/node-postgres/migrator'

// Runs once before the entire vitest run. Ensures the dedicated test DB
// (TEST_DATABASE_URL) exists and has every migration applied, so individual
// integration tests can assume a clean schema and just truncate between cases.
//
// Keeping the test DB separate from the dev DB prevents the test suite's
// truncate-everything-in-beforeEach from wiping local seed data.
export async function setup(): Promise<void> {
  const testUrl = process.env.TEST_DATABASE_URL
  if (!testUrl) {
    throw new Error(
      'TEST_DATABASE_URL is not set. Add it to backend/.env (e.g. ' +
      'postgres://f1pg:f1pg_dev@localhost:5433/f1pg_test).'
    )
  }

  const url = new URL(testUrl)
  const testDbName = url.pathname.replace(/^\//, '')
  if (!testDbName) throw new Error('TEST_DATABASE_URL has no database name')

  // Connect to the cluster's admin DB to create the test DB if missing.
  // `postgres` is the conventional admin DB name; the local docker-compose ships with it.
  const adminUrl = new URL(testUrl)
  adminUrl.pathname = '/postgres'
  const adminPool = new pg.Pool({ connectionString: adminUrl.toString() })
  try {
    const r = await adminPool.query<{ datname: string }>(
      `SELECT datname FROM pg_database WHERE datname = $1`,
      [testDbName]
    )
    if (r.rowCount === 0) {
      // Database names can't be parameterized; we constructed testDbName from a parsed URL,
      // so quote it to be safe and reject anything containing a double-quote.
      if (testDbName.includes('"')) throw new Error(`Refusing to CREATE DATABASE with quote in name: ${testDbName}`)
      await adminPool.query(`CREATE DATABASE "${testDbName}"`)
    }
  } finally {
    await adminPool.end()
  }

  // Apply migrations against the test DB itself.
  const pool = new pg.Pool({ connectionString: testUrl })
  try {
    await migrate(drizzle(pool), { migrationsFolder: './src/db/migrations' })
  } finally {
    await pool.end()
  }
}
