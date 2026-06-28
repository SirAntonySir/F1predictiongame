import { sql } from 'drizzle-orm'
import { getDb } from '../../src/db/client.js'

// IMPORTANT: keep this list in sync with src/db/schema.ts as tables are added.
const TABLES = [
  'notification_log',
  'notification_pref',
  'device_token',
  'subjective_truth',
  'preseason_pick_standings_constructor',
  'preseason_pick_standings_driver',
  'preseason_pick',
  'score',
  'prediction_pick',
  'prediction',
  'league_member',
  'app_session',
  'league',
  'user',
  'session_result',
  'driver_standing',
  'constructor_standing',
  'session',
  'event',
  'season',
  'driver',
  'constructor'
] as const

export async function truncateAll(): Promise<void> {
  const list = TABLES.map((t) => `"${t}"`).join(', ')
  // Use the lazy db Proxy; this auto-initializes the pool on first call.
  const db = getDb()
  await db.execute(sql.raw(`TRUNCATE TABLE ${list} RESTART IDENTITY CASCADE`))
}
