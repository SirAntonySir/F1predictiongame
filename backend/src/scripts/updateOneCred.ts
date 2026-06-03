/**
 * One-shot: set real email + password on a single account. Reads target from
 * env vars to keep plaintext credentials out of source. Run with:
 *   DATABASE_URL=... DISPLAY_NAME=Janine EMAIL=jagruendl@gmail.com PASSWORD=Janine_Tippspiel npx tsx src/scripts/updateOneCred.ts
 */
import { hashPassword } from '../auth/password.js'
import { getDb, _resetPoolForTests } from '../db/client.js'
import { user } from '../db/schema.js'
import { eq, sql } from 'drizzle-orm'

async function main(): Promise<number> {
  const displayName = process.env.DISPLAY_NAME
  const email = process.env.EMAIL
  const password = process.env.PASSWORD
  if (!displayName || !email || !password) {
    console.error('need DISPLAY_NAME, EMAIL, PASSWORD env vars')
    return 2
  }
  const db = getDb()
  const before = await db.select({ id: user.id, email: user.email }).from(user).where(eq(user.displayName, displayName)).limit(1)
  if (before.length === 0) {
    console.error(`no user row with displayName="${displayName}"`)
    return 1
  }
  await db.update(user).set({
    email,
    passwordHash: await hashPassword(password),
    updatedAt: sql`now()`,
  }).where(eq(user.displayName, displayName))
  console.log(`OK ${displayName}: ${before[0]!.email} → ${email}  (pw updated)`)
  return 0
}

main()
  .then(async (c) => { await _resetPoolForTests(); process.exit(c) })
  .catch(async (e) => { console.error(e); await _resetPoolForTests(); process.exit(1) })
