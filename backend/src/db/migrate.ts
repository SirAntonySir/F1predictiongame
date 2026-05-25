import { migrate } from 'drizzle-orm/node-postgres/migrator'
import { getPool } from './client.js'
import { drizzle } from 'drizzle-orm/node-postgres'

async function main() {
  console.log('Running migrations...')
  const pool = getPool()
  const db = drizzle(pool)
  await migrate(db, { migrationsFolder: './src/db/migrations' })
  console.log('Migrations complete.')
  await pool.end()
}

main().catch((err) => {
  console.error('Migration failed:', err)
  process.exit(1)
})
