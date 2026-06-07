/**
 * Recompute and upsert scores for a single session. Point DATABASE_URL at the
 * target DB. Idempotent.
 *
 *   npx tsx src/scripts/rescoreOne.ts <sessionId>
 */
import { getPool } from '../db/client.js'
import { rescoreSession } from '../scoring/rescorer.js'

const sessionId = Number(process.argv[2] ?? process.env.SESSION_ID)

async function main() {
  if (!Number.isFinite(sessionId)) throw new Error('Usage: rescoreOne.ts <sessionId>')
  const summary = await rescoreSession(sessionId)
  console.log(`Rescored session #${sessionId}: ${summary.users} predictions, ${summary.totalPoints} total points`)
}

main()
  .then(async () => { await getPool().end() })
  .catch(async (e) => { console.error('ERROR:', e instanceof Error ? e.message : e); try { await getPool().end() } catch { /* noop */ } process.exitCode = 1 })
