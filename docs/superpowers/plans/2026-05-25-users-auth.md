# Users, Auth & Leagues Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add email+password user accounts, opaque DB-backed sessions, and a one-league-per-user grouping concept to the existing Fastify/Postgres backend.

**Architecture:** Slot into the existing `api → repo → db` layering. Four new tables (`user`, `app_session`, `league`, `league_member`). One new leaf module `src/auth/` (pure functions: password hashing, token generation, join-code generation). Two new route files (`auth.ts`, `leagues.ts`). One Fastify `preHandler` hook for bearer-token auth. Two per-route helper guards for league member/owner checks. One new daily cron job for expired-session sweep.

**Tech Stack:** Same as sub-project 1 — Node 22, TypeScript 5.6, Fastify 5, Drizzle ORM, pg, node-cron, zod, vitest. New dep: `bcryptjs` (pure-JS, no native build).

**Spec:** `docs/superpowers/specs/2026-05-25-users-auth-design.md`

**Spec deviation:** Spec calls for `citext` email column. Plan implements equivalent case-insensitive behavior with `text` + application-layer lowercase normalization + unique constraint. Reason: the project's drizzle-kit toolchain doesn't cleanly support custom types or `CREATE EXTENSION citext`, and lowercase-at-write is functionally identical for our query patterns. No behavior change observable to clients.

---

## File map

All paths are under `backend/`.

| Path | Status | Responsibility |
|---|---|---|
| `package.json` | Modify | Add `bcryptjs` + `@types/bcryptjs` |
| `src/db/schema.ts` | Modify | Add `user`, `appSession`, `league`, `leagueMember` table defs |
| `src/db/migrations/0002_users_auth.sql` | Create | `CREATE EXTENSION pgcrypto`, 4 tables, indexes |
| `src/db/migrations/meta/_journal.json` | Modify | Register migration 0002 |
| `src/db/migrations/meta/0002_snapshot.json` | Create | Snapshot for migration 0002 |
| `src/domain/types.ts` | Modify | Add `User`, `AppSession`, `League`, `LeagueMember` |
| `src/auth/password.ts` | Create | bcrypt wrappers |
| `src/auth/tokens.ts` | Create | Random token gen + sha256 |
| `src/auth/joinCodes.ts` | Create | 6-char [A-Z0-9] generator |
| `src/auth/sweeper.ts` | Create | Expired-session delete |
| `src/repo/users.ts` | Create | User CRUD |
| `src/repo/appSessions.ts` | Create | Session CRUD + slide expiry |
| `src/repo/leagues.ts` | Create | League CRUD + code regen |
| `src/repo/leagueMembers.ts` | Create | Membership CRUD |
| `src/api/errors.ts` | Modify | Add `FORBIDDEN`, `CONFLICT`, `VALIDATION` codes |
| `src/api/auth-context.ts` | Create | Fastify req.user augmentation + preHandler + league guards |
| `src/api/routes/auth.ts` | Create | `/api/auth/*` routes |
| `src/api/routes/leagues.ts` | Create | `/api/leagues/*` routes |
| `src/index.ts` | Modify | Register new routes; wire sweeper into Scheduler |
| `src/crawler/scheduler.ts` | Modify | Add daily sweeper cron |
| `test/helpers/db.ts` | Modify | Extend `TABLES` with 4 new tables |
| `test/helpers/factories.ts` | Create | `makeUser`, `makeLeague`, `makeSession` helpers |
| `test/unit/auth_password.test.ts` | Create | Password hash round-trip |
| `test/unit/auth_tokens.test.ts` | Create | Token gen + hash determinism |
| `test/unit/auth_joinCodes.test.ts` | Create | Code shape + collision retry |
| `test/integration/repo_users.test.ts` | Create | User repo |
| `test/integration/repo_appSessions.test.ts` | Create | Session repo |
| `test/integration/repo_leagues.test.ts` | Create | League + members repo |
| `test/integration/api_auth.test.ts` | Create | End-to-end auth routes |
| `test/integration/api_leagues.test.ts` | Create | End-to-end league routes |
| `test/integration/auth_sweeper.test.ts` | Create | Sweeper deletes expired sessions |
| `README.md` | Modify | Add auth section + new endpoints to API table |

---

### Task 1: Schema + migration

**Files:**
- Modify: `backend/package.json`
- Modify: `backend/src/db/schema.ts`
- Modify: `backend/src/domain/types.ts`
- Create: `backend/src/db/migrations/0002_users_auth.sql`
- Modify: `backend/src/db/migrations/meta/_journal.json`
- Create: `backend/src/db/migrations/meta/0002_snapshot.json`
- Modify: `backend/test/helpers/db.ts`

- [ ] **Step 1: Add `bcryptjs` dep**

In `backend/`:

```bash
npm install bcryptjs
npm install -D @types/bcryptjs
```

- [ ] **Step 2: Extend `src/db/schema.ts`**

Append to `backend/src/db/schema.ts` (keep all existing exports):

```ts
import {
  pgTable, integer, text, boolean, timestamp, pgEnum, primaryKey, uniqueIndex, index, uuid, customType
} from 'drizzle-orm/pg-core'

// ... existing tables stay as-is

const bytea = customType<{ data: Buffer; driverData: Buffer }>({
  dataType: () => 'bytea'
})

export const user = pgTable('user', {
  id: uuid('id').primaryKey().defaultRandom(),
  email: text('email').notNull(),
  passwordHash: text('password_hash').notNull(),
  displayName: text('display_name').notNull(),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow()
}, (t) => ({
  emailUq: uniqueIndex('user_email_uq').on(t.email)
}))

export const appSession = pgTable('app_session', {
  id: uuid('id').primaryKey().defaultRandom(),
  userId: uuid('user_id').notNull().references(() => user.id, { onDelete: 'cascade' }),
  tokenHash: bytea('token_hash').notNull(),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  lastUsedAt: timestamp('last_used_at', { withTimezone: true }).notNull().defaultNow(),
  expiresAt: timestamp('expires_at', { withTimezone: true }).notNull(),
  userAgent: text('user_agent')
}, (t) => ({
  tokenHashUq: uniqueIndex('app_session_token_hash_uq').on(t.tokenHash),
  userIdx: index('app_session_user_idx').on(t.userId),
  expiresIdx: index('app_session_expires_idx').on(t.expiresAt)
}))

export const league = pgTable('league', {
  id: uuid('id').primaryKey().defaultRandom(),
  ownerUserId: uuid('owner_user_id').notNull().references(() => user.id, { onDelete: 'cascade' }),
  name: text('name').notNull(),
  joinCode: text('join_code').notNull(),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow()
}, (t) => ({
  ownerUq: uniqueIndex('league_owner_uq').on(t.ownerUserId),
  joinCodeUq: uniqueIndex('league_join_code_uq').on(t.joinCode)
}))

export const leagueMember = pgTable('league_member', {
  leagueId: uuid('league_id').notNull().references(() => league.id, { onDelete: 'cascade' }),
  userId: uuid('user_id').notNull().references(() => user.id, { onDelete: 'cascade' }),
  joinedAt: timestamp('joined_at', { withTimezone: true }).notNull().defaultNow()
}, (t) => ({
  pk: primaryKey({ columns: [t.leagueId, t.userId] }),
  userIdx: index('league_member_user_idx').on(t.userId)
}))
```

- [ ] **Step 3: Extend `src/domain/types.ts`**

Append (keep existing exports):

```ts
export type User = {
  id: string
  email: string
  displayName: string
  createdAt: Date
  updatedAt: Date
}

export type UserWithSecret = User & { passwordHash: string }

export type AppSession = {
  id: string
  userId: string
  tokenHash: Buffer
  createdAt: Date
  lastUsedAt: Date
  expiresAt: Date
  userAgent: string | null
}

export type League = {
  id: string
  ownerUserId: string
  name: string
  joinCode: string
  createdAt: Date
}

export type LeagueMember = {
  leagueId: string
  userId: string
  joinedAt: Date
}
```

- [ ] **Step 4: Create migration `0002_users_auth.sql`**

Create `backend/src/db/migrations/0002_users_auth.sql`:

```sql
CREATE EXTENSION IF NOT EXISTS pgcrypto;--> statement-breakpoint
CREATE TABLE "user" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"email" text NOT NULL,
	"password_hash" text NOT NULL,
	"display_name" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX "user_email_uq" ON "user" ("email");--> statement-breakpoint
CREATE TABLE "app_session" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" uuid NOT NULL,
	"token_hash" bytea NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"last_used_at" timestamp with time zone DEFAULT now() NOT NULL,
	"expires_at" timestamp with time zone NOT NULL,
	"user_agent" text,
	CONSTRAINT "app_session_user_fk" FOREIGN KEY ("user_id") REFERENCES "user"("id") ON DELETE CASCADE
);
--> statement-breakpoint
CREATE UNIQUE INDEX "app_session_token_hash_uq" ON "app_session" ("token_hash");--> statement-breakpoint
CREATE INDEX "app_session_user_idx" ON "app_session" ("user_id");--> statement-breakpoint
CREATE INDEX "app_session_expires_idx" ON "app_session" ("expires_at");--> statement-breakpoint
CREATE TABLE "league" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"owner_user_id" uuid NOT NULL,
	"name" text NOT NULL,
	"join_code" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "league_owner_fk" FOREIGN KEY ("owner_user_id") REFERENCES "user"("id") ON DELETE CASCADE
);
--> statement-breakpoint
CREATE UNIQUE INDEX "league_owner_uq" ON "league" ("owner_user_id");--> statement-breakpoint
CREATE UNIQUE INDEX "league_join_code_uq" ON "league" ("join_code");--> statement-breakpoint
CREATE TABLE "league_member" (
	"league_id" uuid NOT NULL,
	"user_id" uuid NOT NULL,
	"joined_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "league_member_pk" PRIMARY KEY ("league_id", "user_id"),
	CONSTRAINT "league_member_league_fk" FOREIGN KEY ("league_id") REFERENCES "league"("id") ON DELETE CASCADE,
	CONSTRAINT "league_member_user_fk" FOREIGN KEY ("user_id") REFERENCES "user"("id") ON DELETE CASCADE
);
--> statement-breakpoint
CREATE INDEX "league_member_user_idx" ON "league_member" ("user_id");
```

- [ ] **Step 5: Register migration in `_journal.json`**

Read current `backend/src/db/migrations/meta/_journal.json` and append a new entry to its `entries` array:

```json
{
  "idx": 2,
  "version": "7",
  "when": <CURRENT_UNIX_MS>,
  "tag": "0002_users_auth",
  "breakpoints": true
}
```

Use the current timestamp in milliseconds for `when`. Match `version` to whatever the existing entries use (e.g. "7" — copy from entry 0 or 1).

- [ ] **Step 6: Create `meta/0002_snapshot.json`**

Copy `backend/src/db/migrations/meta/0001_snapshot.json` to `0002_snapshot.json`. Increment its top-level `"id"` field to a new UUID, set `"prevId"` to the previous snapshot's `"id"`, and add the four new tables under `"tables"`. The minimum needed for drizzle-kit's bookkeeping is correct names/columns/indexes; mirror the shape of existing entries.

(If this proves fiddly during execution, alternative: run `npm run db:generate` against a fresh DB that already has migrations 0000+0001 applied; drizzle-kit will produce a correctly-shaped 0002 + snapshot automatically. Then hand-edit the generated SQL to prepend `CREATE EXTENSION IF NOT EXISTS pgcrypto;`.)

- [ ] **Step 7: Extend `test/helpers/db.ts`**

Update the `TABLES` array (add the 4 new table names before any others, since cascade ordering matters less with `RESTART IDENTITY CASCADE` but explicit dependency order is safer):

```ts
const TABLES = [
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
```

- [ ] **Step 8: Run the migration locally to verify**

Run: `cd backend && docker compose up -d && npm run db:migrate`
Expected: `Migrations complete.`

Verify in psql:

```bash
docker exec backend-db-1 psql -U f1pg -d f1pg -c "\dt"
```

Expected: lists 12 tables including `user`, `app_session`, `league`, `league_member`.

- [ ] **Step 9: Commit**

```bash
cd backend
git add package.json package-lock.json src/db/schema.ts src/db/migrations/0002_users_auth.sql src/db/migrations/meta/_journal.json src/db/migrations/meta/0002_snapshot.json src/domain/types.ts test/helpers/db.ts
git commit -m "backend: schema + migration for users, sessions, leagues"
```

---

### Task 2: Auth primitives

**Files:**
- Create: `backend/src/auth/password.ts`
- Create: `backend/src/auth/tokens.ts`
- Create: `backend/src/auth/joinCodes.ts`
- Create: `backend/test/unit/auth_password.test.ts`
- Create: `backend/test/unit/auth_tokens.test.ts`
- Create: `backend/test/unit/auth_joinCodes.test.ts`

- [ ] **Step 1: Write `auth/password.ts` tests**

Create `backend/test/unit/auth_password.test.ts`:

```ts
import { describe, it, expect } from 'vitest'
import { hashPassword, verifyPassword } from '../../src/auth/password.js'

describe('password', () => {
  it('hashes and verifies a password', async () => {
    const hash = await hashPassword('hunter22')
    expect(hash).not.toBe('hunter22')
    expect(await verifyPassword('hunter22', hash)).toBe(true)
  })

  it('rejects a wrong password', async () => {
    const hash = await hashPassword('hunter22')
    expect(await verifyPassword('hunter23', hash)).toBe(false)
  })

  it('produces different hashes for the same input (salted)', async () => {
    const a = await hashPassword('abc')
    const b = await hashPassword('abc')
    expect(a).not.toBe(b)
  })
})
```

- [ ] **Step 2: Verify tests fail**

Run: `cd backend && npx vitest run test/unit/auth_password.test.ts`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement `auth/password.ts`**

Create `backend/src/auth/password.ts`:

```ts
import bcrypt from 'bcryptjs'

const COST = 12

export async function hashPassword(plain: string): Promise<string> {
  return bcrypt.hash(plain, COST)
}

export async function verifyPassword(plain: string, hash: string): Promise<boolean> {
  return bcrypt.compare(plain, hash)
}
```

- [ ] **Step 4: Verify password tests pass**

Run: `cd backend && npx vitest run test/unit/auth_password.test.ts`
Expected: PASS (3 tests).

- [ ] **Step 5: Write `auth/tokens.ts` tests**

Create `backend/test/unit/auth_tokens.test.ts`:

```ts
import { describe, it, expect } from 'vitest'
import { generateToken, hashToken } from '../../src/auth/tokens.js'

describe('tokens', () => {
  it('generates a base64url token of ~43 chars', () => {
    const t = generateToken()
    expect(t).toMatch(/^[A-Za-z0-9_-]+$/)
    expect(t.length).toBeGreaterThanOrEqual(42)
    expect(t.length).toBeLessThanOrEqual(44)
  })

  it('generates unique tokens', () => {
    const a = generateToken()
    const b = generateToken()
    expect(a).not.toBe(b)
  })

  it('hashes deterministically with sha256, returning a 32-byte Buffer', () => {
    const t = 'abc'
    const h1 = hashToken(t)
    const h2 = hashToken(t)
    expect(h1.equals(h2)).toBe(true)
    expect(h1.length).toBe(32)
  })
})
```

- [ ] **Step 6: Verify tests fail**

Run: `cd backend && npx vitest run test/unit/auth_tokens.test.ts`
Expected: FAIL.

- [ ] **Step 7: Implement `auth/tokens.ts`**

Create `backend/src/auth/tokens.ts`:

```ts
import { randomBytes, createHash } from 'node:crypto'

export function generateToken(): string {
  return randomBytes(32).toString('base64url')
}

export function hashToken(token: string): Buffer {
  return createHash('sha256').update(token).digest()
}
```

- [ ] **Step 8: Verify tokens tests pass**

Run: `cd backend && npx vitest run test/unit/auth_tokens.test.ts`
Expected: PASS (3 tests).

- [ ] **Step 9: Write `auth/joinCodes.ts` tests**

Create `backend/test/unit/auth_joinCodes.test.ts`:

```ts
import { describe, it, expect } from 'vitest'
import { generateJoinCode, generateUniqueJoinCode } from '../../src/auth/joinCodes.js'

describe('joinCodes', () => {
  it('generates a 6-char uppercase-alphanumeric code', () => {
    for (let i = 0; i < 50; i++) {
      const c = generateJoinCode()
      expect(c).toMatch(/^[A-Z0-9]{6}$/)
    }
  })

  it('retries on collision via isTaken callback', async () => {
    const seen = new Set<string>()
    let calls = 0
    const code = await generateUniqueJoinCode(async (c) => {
      calls++
      if (calls < 3) { seen.add(c); return true }
      return false
    })
    expect(calls).toBe(3)
    expect(seen.has(code)).toBe(false)
  })

  it('throws after 10 unique attempts', async () => {
    await expect(generateUniqueJoinCode(async () => true)).rejects.toThrow(/unique join code/i)
  })
})
```

- [ ] **Step 10: Verify tests fail**

Run: `cd backend && npx vitest run test/unit/auth_joinCodes.test.ts`
Expected: FAIL.

- [ ] **Step 11: Implement `auth/joinCodes.ts`**

Create `backend/src/auth/joinCodes.ts`:

```ts
import { randomInt } from 'node:crypto'

const ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
const LEN = 6
const MAX_ATTEMPTS = 10

export function generateJoinCode(): string {
  let out = ''
  for (let i = 0; i < LEN; i++) {
    out += ALPHABET[randomInt(0, ALPHABET.length)]
  }
  return out
}

export async function generateUniqueJoinCode(
  isTaken: (code: string) => Promise<boolean>
): Promise<string> {
  for (let i = 0; i < MAX_ATTEMPTS; i++) {
    const c = generateJoinCode()
    if (!(await isTaken(c))) return c
  }
  throw new Error('Could not generate a unique join code after ' + MAX_ATTEMPTS + ' attempts')
}
```

- [ ] **Step 12: Verify joinCodes tests pass**

Run: `cd backend && npx vitest run test/unit/auth_joinCodes.test.ts`
Expected: PASS (3 tests).

- [ ] **Step 13: Commit**

```bash
cd backend
git add src/auth/ test/unit/auth_password.test.ts test/unit/auth_tokens.test.ts test/unit/auth_joinCodes.test.ts
git commit -m "backend: auth primitives (password, tokens, join codes)"
```

---

### Task 3: Users repo

**Files:**
- Create: `backend/src/repo/users.ts`
- Create: `backend/test/integration/repo_users.test.ts`

- [ ] **Step 1: Write tests**

Create `backend/test/integration/repo_users.test.ts`:

```ts
import { describe, it, expect } from 'vitest'
import * as users from '../../src/repo/users.js'

describe('users repo', () => {
  it('inserts a user and returns it', async () => {
    const u = await users.insertUser({
      email: 'anton@example.com',
      passwordHash: 'hash',
      displayName: 'Anton'
    })
    expect(u.id).toMatch(/^[0-9a-f-]{36}$/)
    expect(u.email).toBe('anton@example.com')
    expect(u.displayName).toBe('Anton')
  })

  it('rejects duplicate email', async () => {
    await users.insertUser({ email: 'a@x.com', passwordHash: 'h', displayName: 'A' })
    await expect(
      users.insertUser({ email: 'a@x.com', passwordHash: 'h2', displayName: 'B' })
    ).rejects.toThrow(/duplicate|unique/i)
  })

  it('finds user by email (with password hash)', async () => {
    await users.insertUser({ email: 'find@x.com', passwordHash: 'secret', displayName: 'F' })
    const u = await users.findByEmailWithSecret('find@x.com')
    expect(u?.passwordHash).toBe('secret')
  })

  it('returns null for missing email', async () => {
    const u = await users.findByEmailWithSecret('nope@x.com')
    expect(u).toBeNull()
  })

  it('finds user by id (without password hash)', async () => {
    const created = await users.insertUser({ email: 'by@x.com', passwordHash: 'h', displayName: 'B' })
    const found = await users.findById(created.id)
    expect(found?.id).toBe(created.id)
    expect((found as any)?.passwordHash).toBeUndefined()
  })

  it('updates display name', async () => {
    const u = await users.insertUser({ email: 'up@x.com', passwordHash: 'h', displayName: 'Old' })
    const updated = await users.updateDisplayName(u.id, 'New')
    expect(updated.displayName).toBe('New')
  })
})
```

- [ ] **Step 2: Verify tests fail**

Run: `cd backend && npx vitest run test/integration/repo_users.test.ts`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement `src/repo/users.ts`**

Create `backend/src/repo/users.ts`:

```ts
import { eq, sql } from 'drizzle-orm'
import { getDb } from '../db/client.js'
import { user } from '../db/schema.js'
import type { User, UserWithSecret } from '../domain/types.js'

export type NewUser = {
  email: string
  passwordHash: string
  displayName: string
}

function toUser(row: typeof user.$inferSelect): User {
  return {
    id: row.id,
    email: row.email,
    displayName: row.displayName,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt
  }
}

export async function insertUser(n: NewUser): Promise<User> {
  const db = getDb()
  const [row] = await db.insert(user).values({
    email: n.email,
    passwordHash: n.passwordHash,
    displayName: n.displayName
  }).returning()
  return toUser(row!)
}

export async function findById(id: string): Promise<User | null> {
  const db = getDb()
  const rows = await db.select().from(user).where(eq(user.id, id)).limit(1)
  return rows[0] ? toUser(rows[0]) : null
}

export async function findByEmailWithSecret(email: string): Promise<UserWithSecret | null> {
  const db = getDb()
  const rows = await db.select().from(user).where(eq(user.email, email)).limit(1)
  const row = rows[0]
  if (!row) return null
  return { ...toUser(row), passwordHash: row.passwordHash }
}

export async function updateDisplayName(id: string, displayName: string): Promise<User> {
  const db = getDb()
  const [row] = await db
    .update(user)
    .set({ displayName, updatedAt: sql`now()` })
    .where(eq(user.id, id))
    .returning()
  if (!row) throw new Error('user not found: ' + id)
  return toUser(row)
}
```

- [ ] **Step 4: Verify tests pass**

Run: `cd backend && npx vitest run test/integration/repo_users.test.ts`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
cd backend
git add src/repo/users.ts test/integration/repo_users.test.ts
git commit -m "backend: users repo"
```

---

### Task 4: App sessions repo

**Files:**
- Create: `backend/src/repo/appSessions.ts`
- Create: `backend/test/integration/repo_appSessions.test.ts`

- [ ] **Step 1: Write tests**

Create `backend/test/integration/repo_appSessions.test.ts`:

```ts
import { describe, it, expect } from 'vitest'
import * as users from '../../src/repo/users.js'
import * as sessions from '../../src/repo/appSessions.js'
import { hashToken } from '../../src/auth/tokens.js'

async function makeUser() {
  return users.insertUser({ email: `u-${Date.now()}-${Math.random()}@x.com`, passwordHash: 'h', displayName: 'U' })
}

describe('app sessions repo', () => {
  it('inserts a session and finds it by token hash', async () => {
    const u = await makeUser()
    const th = hashToken('raw-token')
    const expiresAt = new Date(Date.now() + 90 * 24 * 60 * 60 * 1000)
    const s = await sessions.insertSession({ userId: u.id, tokenHash: th, expiresAt, userAgent: 'jest' })
    expect(s.userId).toBe(u.id)

    const found = await sessions.findByTokenHash(th)
    expect(found?.id).toBe(s.id)
  })

  it('returns null for unknown token hash', async () => {
    const found = await sessions.findByTokenHash(hashToken('nope'))
    expect(found).toBeNull()
  })

  it('slides expiry on touch', async () => {
    const u = await makeUser()
    const th = hashToken('t')
    const oldExpiry = new Date(Date.now() + 1000)
    const s = await sessions.insertSession({ userId: u.id, tokenHash: th, expiresAt: oldExpiry, userAgent: null })

    const newExpiry = new Date(Date.now() + 90 * 24 * 60 * 60 * 1000)
    await sessions.touchSession(s.id, newExpiry)

    const found = await sessions.findByTokenHash(th)
    expect(found!.expiresAt.getTime()).toBeGreaterThan(oldExpiry.getTime())
  })

  it('deletes a session by id', async () => {
    const u = await makeUser()
    const th = hashToken('d')
    const s = await sessions.insertSession({ userId: u.id, tokenHash: th, expiresAt: new Date(Date.now() + 1000), userAgent: null })
    await sessions.deleteById(s.id)
    expect(await sessions.findByTokenHash(th)).toBeNull()
  })

  it('deletes expired sessions in bulk', async () => {
    const u = await makeUser()
    await sessions.insertSession({ userId: u.id, tokenHash: hashToken('a'), expiresAt: new Date(Date.now() - 1000), userAgent: null })
    await sessions.insertSession({ userId: u.id, tokenHash: hashToken('b'), expiresAt: new Date(Date.now() - 1000), userAgent: null })
    await sessions.insertSession({ userId: u.id, tokenHash: hashToken('c'), expiresAt: new Date(Date.now() + 60_000), userAgent: null })
    const deleted = await sessions.deleteExpired()
    expect(deleted).toBe(2)
  })

  it('cascades when user is deleted', async () => {
    const u = await makeUser()
    const th = hashToken('cascade')
    await sessions.insertSession({ userId: u.id, tokenHash: th, expiresAt: new Date(Date.now() + 1000), userAgent: null })
    await users.deleteById(u.id)
    expect(await sessions.findByTokenHash(th)).toBeNull()
  })
})
```

- [ ] **Step 2: Add `deleteById` to `src/repo/users.ts`**

Append to `backend/src/repo/users.ts`:

```ts
export async function deleteById(id: string): Promise<void> {
  const db = getDb()
  await db.delete(user).where(eq(user.id, id))
}
```

- [ ] **Step 3: Verify tests fail**

Run: `cd backend && npx vitest run test/integration/repo_appSessions.test.ts`
Expected: FAIL.

- [ ] **Step 4: Implement `src/repo/appSessions.ts`**

Create `backend/src/repo/appSessions.ts`:

```ts
import { eq, lt, sql } from 'drizzle-orm'
import { getDb } from '../db/client.js'
import { appSession } from '../db/schema.js'
import type { AppSession } from '../domain/types.js'

export type NewSession = {
  userId: string
  tokenHash: Buffer
  expiresAt: Date
  userAgent: string | null
}

function toSession(row: typeof appSession.$inferSelect): AppSession {
  return {
    id: row.id,
    userId: row.userId,
    tokenHash: row.tokenHash,
    createdAt: row.createdAt,
    lastUsedAt: row.lastUsedAt,
    expiresAt: row.expiresAt,
    userAgent: row.userAgent
  }
}

export async function insertSession(n: NewSession): Promise<AppSession> {
  const db = getDb()
  const [row] = await db.insert(appSession).values({
    userId: n.userId,
    tokenHash: n.tokenHash,
    expiresAt: n.expiresAt,
    userAgent: n.userAgent
  }).returning()
  return toSession(row!)
}

export async function findByTokenHash(tokenHash: Buffer): Promise<AppSession | null> {
  const db = getDb()
  const rows = await db.select().from(appSession).where(eq(appSession.tokenHash, tokenHash)).limit(1)
  return rows[0] ? toSession(rows[0]) : null
}

export async function touchSession(id: string, newExpiresAt: Date): Promise<void> {
  const db = getDb()
  await db.update(appSession)
    .set({ lastUsedAt: sql`now()`, expiresAt: newExpiresAt })
    .where(eq(appSession.id, id))
}

export async function deleteById(id: string): Promise<void> {
  const db = getDb()
  await db.delete(appSession).where(eq(appSession.id, id))
}

export async function deleteExpired(): Promise<number> {
  const db = getDb()
  const res = await db.delete(appSession).where(lt(appSession.expiresAt, sql`now()`)).returning({ id: appSession.id })
  return res.length
}
```

- [ ] **Step 5: Verify tests pass**

Run: `cd backend && npx vitest run test/integration/repo_appSessions.test.ts`
Expected: PASS (6 tests).

- [ ] **Step 6: Commit**

```bash
cd backend
git add src/repo/users.ts src/repo/appSessions.ts test/integration/repo_appSessions.test.ts
git commit -m "backend: app sessions repo"
```

---

### Task 5: Leagues + members repo

**Files:**
- Create: `backend/src/repo/leagues.ts`
- Create: `backend/src/repo/leagueMembers.ts`
- Create: `backend/test/integration/repo_leagues.test.ts`

- [ ] **Step 1: Write tests**

Create `backend/test/integration/repo_leagues.test.ts`:

```ts
import { describe, it, expect } from 'vitest'
import * as users from '../../src/repo/users.js'
import * as leagues from '../../src/repo/leagues.js'
import * as members from '../../src/repo/leagueMembers.js'

async function makeUser(email = `u-${Date.now()}-${Math.random()}@x.com`) {
  return users.insertUser({ email, passwordHash: 'h', displayName: 'U' })
}

describe('leagues repo', () => {
  it('creates a league with code and adds owner as member (transaction)', async () => {
    const owner = await makeUser()
    const l = await leagues.createLeagueWithOwner({ name: 'Anton League', ownerUserId: owner.id, joinCode: 'ABC123' })
    expect(l.name).toBe('Anton League')
    expect(l.joinCode).toBe('ABC123')

    const m = await members.listByLeague(l.id)
    expect(m.map((x) => x.userId)).toContain(owner.id)
  })

  it('rejects a second league from the same owner', async () => {
    const owner = await makeUser()
    await leagues.createLeagueWithOwner({ name: 'One', ownerUserId: owner.id, joinCode: 'AAA111' })
    await expect(
      leagues.createLeagueWithOwner({ name: 'Two', ownerUserId: owner.id, joinCode: 'BBB222' })
    ).rejects.toThrow(/duplicate|unique/i)
  })

  it('rejects duplicate join code', async () => {
    const o1 = await makeUser('one@x.com')
    const o2 = await makeUser('two@x.com')
    await leagues.createLeagueWithOwner({ name: 'L1', ownerUserId: o1.id, joinCode: 'CODE01' })
    await expect(
      leagues.createLeagueWithOwner({ name: 'L2', ownerUserId: o2.id, joinCode: 'CODE01' })
    ).rejects.toThrow(/duplicate|unique/i)
  })

  it('finds a league by join code', async () => {
    const o = await makeUser()
    await leagues.createLeagueWithOwner({ name: 'L', ownerUserId: o.id, joinCode: 'FIND01' })
    const found = await leagues.findByJoinCode('FIND01')
    expect(found?.name).toBe('L')
  })

  it('updates league name', async () => {
    const o = await makeUser()
    const l = await leagues.createLeagueWithOwner({ name: 'Old', ownerUserId: o.id, joinCode: 'UPD001' })
    const updated = await leagues.updateName(l.id, 'New')
    expect(updated.name).toBe('New')
  })

  it('regenerates join code', async () => {
    const o = await makeUser()
    const l = await leagues.createLeagueWithOwner({ name: 'L', ownerUserId: o.id, joinCode: 'OLDXXX' })
    const updated = await leagues.updateJoinCode(l.id, 'NEWYYY')
    expect(updated.joinCode).toBe('NEWYYY')
  })

  it('deletes league (cascades members)', async () => {
    const o = await makeUser()
    const l = await leagues.createLeagueWithOwner({ name: 'L', ownerUserId: o.id, joinCode: 'DEL001' })
    await leagues.deleteById(l.id)
    expect(await leagues.findByJoinCode('DEL001')).toBeNull()
  })

  it('adds a member to a league', async () => {
    const o = await makeUser('o@x.com')
    const u = await makeUser('m@x.com')
    const l = await leagues.createLeagueWithOwner({ name: 'L', ownerUserId: o.id, joinCode: 'ADD001' })
    await members.add(l.id, u.id)
    const list = await members.listByLeague(l.id)
    expect(list.map((x) => x.userId).sort()).toEqual([o.id, u.id].sort())
  })

  it('rejects duplicate membership', async () => {
    const o = await makeUser('o2@x.com')
    const u = await makeUser('m2@x.com')
    const l = await leagues.createLeagueWithOwner({ name: 'L', ownerUserId: o.id, joinCode: 'DUP001' })
    await members.add(l.id, u.id)
    await expect(members.add(l.id, u.id)).rejects.toThrow(/duplicate|unique|key/i)
  })

  it('lists leagues for a user with role', async () => {
    const owner = await makeUser('owner@x.com')
    const joiner = await makeUser('joiner@x.com')
    const l1 = await leagues.createLeagueWithOwner({ name: 'L1', ownerUserId: owner.id, joinCode: 'ROL001' })
    const l2 = await leagues.createLeagueWithOwner({ name: 'L2', ownerUserId: joiner.id, joinCode: 'ROL002' })
    await members.add(l1.id, joiner.id)
    const list = await leagues.listForUser(joiner.id)
    const byId = new Map(list.map((x) => [x.id, x.role]))
    expect(byId.get(l1.id)).toBe('member')
    expect(byId.get(l2.id)).toBe('owner')
  })

  it('removes a member', async () => {
    const o = await makeUser('rm-o@x.com')
    const u = await makeUser('rm-u@x.com')
    const l = await leagues.createLeagueWithOwner({ name: 'L', ownerUserId: o.id, joinCode: 'RMV001' })
    await members.add(l.id, u.id)
    await members.remove(l.id, u.id)
    const list = await members.listByLeague(l.id)
    expect(list.map((x) => x.userId)).not.toContain(u.id)
  })

  it('checks membership', async () => {
    const o = await makeUser('chk-o@x.com')
    const u = await makeUser('chk-u@x.com')
    const stranger = await makeUser('chk-s@x.com')
    const l = await leagues.createLeagueWithOwner({ name: 'L', ownerUserId: o.id, joinCode: 'CHK001' })
    await members.add(l.id, u.id)
    expect(await members.isMember(l.id, u.id)).toBe(true)
    expect(await members.isMember(l.id, stranger.id)).toBe(false)
  })
})
```

- [ ] **Step 2: Verify tests fail**

Run: `cd backend && npx vitest run test/integration/repo_leagues.test.ts`
Expected: FAIL.

- [ ] **Step 3: Implement `src/repo/leagues.ts`**

Create `backend/src/repo/leagues.ts`:

```ts
import { eq, sql } from 'drizzle-orm'
import { getDb } from '../db/client.js'
import { league, leagueMember } from '../db/schema.js'
import type { League } from '../domain/types.js'

export type NewLeague = {
  name: string
  ownerUserId: string
  joinCode: string
}

export type LeagueWithRole = League & { role: 'owner' | 'member' }

function toLeague(row: typeof league.$inferSelect): League {
  return {
    id: row.id,
    ownerUserId: row.ownerUserId,
    name: row.name,
    joinCode: row.joinCode,
    createdAt: row.createdAt
  }
}

export async function createLeagueWithOwner(n: NewLeague): Promise<League> {
  const db = getDb()
  return db.transaction(async (tx) => {
    const [row] = await tx.insert(league).values({
      name: n.name,
      ownerUserId: n.ownerUserId,
      joinCode: n.joinCode
    }).returning()
    await tx.insert(leagueMember).values({ leagueId: row!.id, userId: n.ownerUserId })
    return toLeague(row!)
  })
}

export async function findById(id: string): Promise<League | null> {
  const db = getDb()
  const rows = await db.select().from(league).where(eq(league.id, id)).limit(1)
  return rows[0] ? toLeague(rows[0]) : null
}

export async function findByJoinCode(code: string): Promise<League | null> {
  const db = getDb()
  const rows = await db.select().from(league).where(eq(league.joinCode, code)).limit(1)
  return rows[0] ? toLeague(rows[0]) : null
}

export async function updateName(id: string, name: string): Promise<League> {
  const db = getDb()
  const [row] = await db.update(league).set({ name }).where(eq(league.id, id)).returning()
  if (!row) throw new Error('league not found: ' + id)
  return toLeague(row)
}

export async function updateJoinCode(id: string, joinCode: string): Promise<League> {
  const db = getDb()
  const [row] = await db.update(league).set({ joinCode }).where(eq(league.id, id)).returning()
  if (!row) throw new Error('league not found: ' + id)
  return toLeague(row)
}

export async function deleteById(id: string): Promise<void> {
  const db = getDb()
  await db.delete(league).where(eq(league.id, id))
}

export async function listForUser(userId: string): Promise<LeagueWithRole[]> {
  const db = getDb()
  const rows = await db
    .select({
      id: league.id,
      ownerUserId: league.ownerUserId,
      name: league.name,
      joinCode: league.joinCode,
      createdAt: league.createdAt,
      role: sql<'owner' | 'member'>`CASE WHEN ${league.ownerUserId} = ${userId} THEN 'owner' ELSE 'member' END`
    })
    .from(league)
    .innerJoin(leagueMember, eq(leagueMember.leagueId, league.id))
    .where(eq(leagueMember.userId, userId))
  return rows.map((r) => ({
    id: r.id,
    ownerUserId: r.ownerUserId,
    name: r.name,
    joinCode: r.joinCode,
    createdAt: r.createdAt,
    role: r.role
  }))
}

export async function countMembers(leagueId: string): Promise<number> {
  const db = getDb()
  const rows = await db.select({ c: sql<number>`count(*)::int` }).from(leagueMember).where(eq(leagueMember.leagueId, leagueId))
  return rows[0]?.c ?? 0
}
```

- [ ] **Step 4: Implement `src/repo/leagueMembers.ts`**

Create `backend/src/repo/leagueMembers.ts`:

```ts
import { and, eq } from 'drizzle-orm'
import { getDb } from '../db/client.js'
import { leagueMember, user } from '../db/schema.js'

export type LeagueMemberView = {
  userId: string
  displayName: string
  joinedAt: Date
}

export async function add(leagueId: string, userId: string): Promise<void> {
  const db = getDb()
  await db.insert(leagueMember).values({ leagueId, userId })
}

export async function remove(leagueId: string, userId: string): Promise<void> {
  const db = getDb()
  await db.delete(leagueMember).where(
    and(eq(leagueMember.leagueId, leagueId), eq(leagueMember.userId, userId))
  )
}

export async function isMember(leagueId: string, userId: string): Promise<boolean> {
  const db = getDb()
  const rows = await db.select({ u: leagueMember.userId }).from(leagueMember).where(
    and(eq(leagueMember.leagueId, leagueId), eq(leagueMember.userId, userId))
  ).limit(1)
  return rows.length > 0
}

export async function listByLeague(leagueId: string): Promise<LeagueMemberView[]> {
  const db = getDb()
  const rows = await db
    .select({
      userId: leagueMember.userId,
      displayName: user.displayName,
      joinedAt: leagueMember.joinedAt
    })
    .from(leagueMember)
    .innerJoin(user, eq(user.id, leagueMember.userId))
    .where(eq(leagueMember.leagueId, leagueId))
    .orderBy(leagueMember.joinedAt)
  return rows
}
```

- [ ] **Step 5: Verify tests pass**

Run: `cd backend && npx vitest run test/integration/repo_leagues.test.ts`
Expected: PASS (12 tests).

- [ ] **Step 6: Commit**

```bash
cd backend
git add src/repo/leagues.ts src/repo/leagueMembers.ts test/integration/repo_leagues.test.ts
git commit -m "backend: leagues + members repos"
```

---

### Task 6: Errors expansion + auth context

**Files:**
- Modify: `backend/src/api/errors.ts`
- Create: `backend/src/api/auth-context.ts`

- [ ] **Step 1: Extend `src/api/errors.ts`**

Replace the contents of `backend/src/api/errors.ts` with:

```ts
import type { FastifyReply } from 'fastify'

export type ApiErrorCode =
  | 'NOT_FOUND'
  | 'UPSTREAM_FAILURE'
  | 'BAD_REQUEST'
  | 'UNAUTHORIZED'
  | 'FORBIDDEN'
  | 'CONFLICT'
  | 'VALIDATION'
  | 'INTERNAL'

const STATUS: Record<ApiErrorCode, number> = {
  NOT_FOUND: 404,
  UPSTREAM_FAILURE: 502,
  BAD_REQUEST: 400,
  UNAUTHORIZED: 401,
  FORBIDDEN: 403,
  CONFLICT: 409,
  VALIDATION: 422,
  INTERNAL: 500
}

export class ApiError extends Error {
  constructor(public code: ApiErrorCode, message: string) {
    super(message)
  }
}

export function sendError(reply: FastifyReply, err: unknown): void {
  if (err instanceof ApiError) {
    reply.status(STATUS[err.code]).send({ error: { code: err.code, message: err.message } })
    return
  }
  reply.status(500).send({ error: { code: 'INTERNAL', message: 'Internal server error' } })
}
```

- [ ] **Step 2: Create `src/api/auth-context.ts`**

Create `backend/src/api/auth-context.ts`:

```ts
import type { FastifyInstance, FastifyRequest } from 'fastify'
import { ApiError } from './errors.js'
import * as usersRepo from '../repo/users.js'
import * as sessionsRepo from '../repo/appSessions.js'
import * as leagueMembers from '../repo/leagueMembers.js'
import * as leaguesRepo from '../repo/leagues.js'
import { hashToken } from '../auth/tokens.js'
import type { User } from '../domain/types.js'

declare module 'fastify' {
  interface FastifyRequest {
    user?: User
  }
}

const SLIDE_MS = 90 * 24 * 60 * 60 * 1000

export function getCurrentUser(req: FastifyRequest): User {
  if (!req.user) throw new ApiError('UNAUTHORIZED', 'Not authenticated')
  return req.user
}

async function authenticate(req: FastifyRequest): Promise<void> {
  const header = req.headers.authorization
  if (!header || !header.startsWith('Bearer ')) {
    throw new ApiError('UNAUTHORIZED', 'Missing bearer token')
  }
  const token = header.slice('Bearer '.length).trim()
  if (!token) throw new ApiError('UNAUTHORIZED', 'Missing bearer token')

  const session = await sessionsRepo.findByTokenHash(hashToken(token))
  if (!session) throw new ApiError('UNAUTHORIZED', 'Invalid token')

  if (session.expiresAt.getTime() < Date.now()) {
    await sessionsRepo.deleteById(session.id)
    throw new ApiError('UNAUTHORIZED', 'Session expired')
  }

  await sessionsRepo.touchSession(session.id, new Date(Date.now() + SLIDE_MS))

  const user = await usersRepo.findById(session.userId)
  if (!user) throw new ApiError('UNAUTHORIZED', 'User no longer exists')
  req.user = user
}

/**
 * Register the bearer-auth preHandler on a route group via app.register prefix.
 * Skips signup/login explicitly.
 */
export function registerAuthHook(app: FastifyInstance): void {
  app.addHook('preHandler', async (req) => {
    const path = req.url.split('?')[0]
    if (path === '/api/auth/signup' || path === '/api/auth/login') return
    await authenticate(req)
  })
}

export async function requireLeagueMember(req: FastifyRequest, leagueId: string): Promise<void> {
  const u = getCurrentUser(req)
  const ok = await leagueMembers.isMember(leagueId, u.id)
  if (!ok) throw new ApiError('FORBIDDEN', 'Not a member of this league')
}

export async function requireLeagueOwner(req: FastifyRequest, leagueId: string): Promise<void> {
  const u = getCurrentUser(req)
  const l = await leaguesRepo.findById(leagueId)
  if (!l) throw new ApiError('NOT_FOUND', 'League not found')
  if (l.ownerUserId !== u.id) throw new ApiError('FORBIDDEN', 'Not the league owner')
}
```

- [ ] **Step 3: Verify the project still type-checks**

Run: `cd backend && npx tsc --noEmit`
Expected: no errors.

- [ ] **Step 4: Commit**

```bash
cd backend
git add src/api/errors.ts src/api/auth-context.ts
git commit -m "backend: error codes + auth context helpers"
```

---

### Task 7: Auth routes

**Files:**
- Create: `backend/src/api/routes/auth.ts`
- Modify: `backend/src/index.ts`
- Create: `backend/test/integration/api_auth.test.ts`

- [ ] **Step 1: Write tests**

Create `backend/test/integration/api_auth.test.ts`:

```ts
import { describe, it, expect } from 'vitest'
import { buildApp } from '../../src/index.js'

async function app() {
  return buildApp({ scheduler: null })
}

async function signup(a: Awaited<ReturnType<typeof app>>, email: string, password = 'hunter22', displayName = 'U') {
  return a.inject({ method: 'POST', url: '/api/auth/signup', payload: { email, password, displayName } })
}

describe('POST /api/auth/signup', () => {
  it('creates a user and returns a token', async () => {
    const a = await app()
    const res = await signup(a, 'a@x.com')
    expect(res.statusCode).toBe(200)
    const body = res.json()
    expect(body.user.email).toBe('a@x.com')
    expect(body.user.id).toMatch(/^[0-9a-f-]{36}$/)
    expect(body.user.passwordHash).toBeUndefined()
    expect(typeof body.token).toBe('string')
    expect(body.token.length).toBeGreaterThan(20)
  })

  it('normalizes email to lowercase', async () => {
    const a = await app()
    const res = await signup(a, 'Mixed@X.COM')
    expect(res.json().user.email).toBe('mixed@x.com')
  })

  it('rejects duplicate email with 409 CONFLICT', async () => {
    const a = await app()
    await signup(a, 'dup@x.com')
    const res = await signup(a, 'DUP@x.com')
    expect(res.statusCode).toBe(409)
    expect(res.json().error.code).toBe('CONFLICT')
  })

  it('rejects short password with 422 VALIDATION', async () => {
    const a = await app()
    const res = await signup(a, 'short@x.com', '1234')
    expect(res.statusCode).toBe(422)
    expect(res.json().error.code).toBe('VALIDATION')
  })

  it('rejects bad email with 422 VALIDATION', async () => {
    const a = await app()
    const res = await signup(a, 'not-an-email')
    expect(res.statusCode).toBe(422)
  })
})

describe('POST /api/auth/login', () => {
  it('logs in with correct password', async () => {
    const a = await app()
    await signup(a, 'log@x.com', 'rightpass')
    const res = await a.inject({ method: 'POST', url: '/api/auth/login', payload: { email: 'log@x.com', password: 'rightpass' } })
    expect(res.statusCode).toBe(200)
    expect(typeof res.json().token).toBe('string')
  })

  it('returns the same UNAUTHORIZED for wrong password or unknown user', async () => {
    const a = await app()
    await signup(a, 'log2@x.com', 'rightpass')
    const wrong = await a.inject({ method: 'POST', url: '/api/auth/login', payload: { email: 'log2@x.com', password: 'wrong' } })
    const unknown = await a.inject({ method: 'POST', url: '/api/auth/login', payload: { email: 'nope@x.com', password: 'rightpass' } })
    expect(wrong.statusCode).toBe(401)
    expect(unknown.statusCode).toBe(401)
    expect(wrong.json().error.message).toBe(unknown.json().error.message)
  })

  it('login is case-insensitive on email', async () => {
    const a = await app()
    await signup(a, 'caseme@x.com', 'rightpass')
    const res = await a.inject({ method: 'POST', url: '/api/auth/login', payload: { email: 'CASEME@x.com', password: 'rightpass' } })
    expect(res.statusCode).toBe(200)
  })
})

describe('GET /api/auth/me', () => {
  it('returns the current user when token is valid', async () => {
    const a = await app()
    const s = await signup(a, 'me@x.com')
    const token = s.json().token
    const res = await a.inject({ method: 'GET', url: '/api/auth/me', headers: { authorization: `Bearer ${token}` } })
    expect(res.statusCode).toBe(200)
    expect(res.json().user.email).toBe('me@x.com')
    expect(Array.isArray(res.json().leagues)).toBe(true)
  })

  it('401s without a token', async () => {
    const a = await app()
    const res = await a.inject({ method: 'GET', url: '/api/auth/me' })
    expect(res.statusCode).toBe(401)
  })

  it('401s with a malformed token', async () => {
    const a = await app()
    const res = await a.inject({ method: 'GET', url: '/api/auth/me', headers: { authorization: 'Bearer not-real' } })
    expect(res.statusCode).toBe(401)
  })
})

describe('PATCH /api/auth/me', () => {
  it('updates display name', async () => {
    const a = await app()
    const s = await signup(a, 'p@x.com', 'pw', 'Old')
    const token = s.json().token
    const res = await a.inject({
      method: 'PATCH', url: '/api/auth/me',
      headers: { authorization: `Bearer ${token}` },
      payload: { displayName: 'New' }
    })
    expect(res.statusCode).toBe(200)
    expect(res.json().user.displayName).toBe('New')
  })
})

describe('POST /api/auth/logout', () => {
  it('deletes the session, subsequent /me 401s', async () => {
    const a = await app()
    const s = await signup(a, 'out@x.com')
    const token = s.json().token
    const out = await a.inject({ method: 'POST', url: '/api/auth/logout', headers: { authorization: `Bearer ${token}` } })
    expect(out.statusCode).toBe(200)
    const me = await a.inject({ method: 'GET', url: '/api/auth/me', headers: { authorization: `Bearer ${token}` } })
    expect(me.statusCode).toBe(401)
  })
})
```

- [ ] **Step 2: Create `src/api/routes/auth.ts`**

Create `backend/src/api/routes/auth.ts`:

```ts
import type { FastifyInstance } from 'fastify'
import { z } from 'zod'
import { ApiError } from '../errors.js'
import * as usersRepo from '../../repo/users.js'
import * as sessionsRepo from '../../repo/appSessions.js'
import * as leaguesRepo from '../../repo/leagues.js'
import { hashPassword, verifyPassword } from '../../auth/password.js'
import { generateToken, hashToken } from '../../auth/tokens.js'
import { getCurrentUser, registerAuthHook } from '../auth-context.js'

const SLIDE_MS = 90 * 24 * 60 * 60 * 1000

const signupBody = z.object({
  email: z.string().email().trim(),
  password: z.string().min(8),
  displayName: z.string().trim().min(1).max(40)
})

const loginBody = z.object({
  email: z.string().email().trim(),
  password: z.string().min(1)
})

const patchMeBody = z.object({
  displayName: z.string().trim().min(1).max(40).optional()
})

function parse<T>(schema: z.ZodType<T>, body: unknown): T {
  const r = schema.safeParse(body)
  if (!r.success) {
    const first = r.error.issues[0]
    throw new ApiError('VALIDATION', first?.message ?? 'Invalid request body')
  }
  return r.data
}

function publicUser(u: { id: string; email: string; displayName: string; createdAt: Date }) {
  return { id: u.id, email: u.email, displayName: u.displayName, createdAt: u.createdAt }
}

async function issueSession(userId: string, userAgent: string | null) {
  const token = generateToken()
  const tokenHash = hashToken(token)
  await sessionsRepo.insertSession({
    userId,
    tokenHash,
    expiresAt: new Date(Date.now() + SLIDE_MS),
    userAgent
  })
  return token
}

export async function registerAuthRoutes(app: FastifyInstance): Promise<void> {
  registerAuthHook(app)

  app.post('/api/auth/signup', async (req, reply) => {
    const body = parse(signupBody, req.body)
    const email = body.email.toLowerCase()
    const existing = await usersRepo.findByEmailWithSecret(email)
    if (existing) throw new ApiError('CONFLICT', 'Email already registered')

    const passwordHash = await hashPassword(body.password)
    const user = await usersRepo.insertUser({ email, passwordHash, displayName: body.displayName })
    const token = await issueSession(user.id, (req.headers['user-agent'] as string) ?? null)
    reply.send({ user: publicUser(user), token })
  })

  app.post('/api/auth/login', async (req, reply) => {
    const body = parse(loginBody, req.body)
    const email = body.email.toLowerCase()
    const u = await usersRepo.findByEmailWithSecret(email)
    if (!u || !(await verifyPassword(body.password, u.passwordHash))) {
      throw new ApiError('UNAUTHORIZED', 'Invalid email or password')
    }
    const token = await issueSession(u.id, (req.headers['user-agent'] as string) ?? null)
    reply.send({ user: publicUser(u), token })
  })

  app.get('/api/auth/me', async (req) => {
    const u = getCurrentUser(req)
    const leagues = await leaguesRepo.listForUser(u.id)
    return {
      user: publicUser(u),
      leagues: leagues.map((l) => ({ id: l.id, name: l.name, role: l.role }))
    }
  })

  app.patch('/api/auth/me', async (req) => {
    const u = getCurrentUser(req)
    const body = parse(patchMeBody, req.body)
    let user = u
    if (body.displayName !== undefined) {
      user = await usersRepo.updateDisplayName(u.id, body.displayName)
    }
    return { user: publicUser(user) }
  })

  app.post('/api/auth/logout', async (req) => {
    const header = req.headers.authorization!
    const token = header.slice('Bearer '.length).trim()
    const session = await sessionsRepo.findByTokenHash(hashToken(token))
    if (session) await sessionsRepo.deleteById(session.id)
    return { ok: true }
  })
}
```

- [ ] **Step 3: Wire into `src/index.ts`**

Edit `backend/src/index.ts`. Add import near the other route imports:

```ts
import { registerAuthRoutes } from './api/routes/auth.js'
```

Inside `buildApp`, before `app.get('/api/health', ...)`, register the new route group. Use `register` with no prefix so the hook scope is limited to this plugin (signup/login still match their full paths inside the hook):

```ts
await app.register(registerAuthRoutes)
```

- [ ] **Step 4: Verify tests pass**

Run: `cd backend && npx vitest run test/integration/api_auth.test.ts`
Expected: PASS (all tests).

- [ ] **Step 5: Commit**

```bash
cd backend
git add src/api/routes/auth.ts src/index.ts test/integration/api_auth.test.ts
git commit -m "backend: /api/auth/* routes (signup, login, me, logout)"
```

---

### Task 8: League routes

**Files:**
- Create: `backend/src/api/routes/leagues.ts`
- Modify: `backend/src/index.ts`
- Create: `backend/test/integration/api_leagues.test.ts`

- [ ] **Step 1: Write tests**

Create `backend/test/integration/api_leagues.test.ts`:

```ts
import { describe, it, expect } from 'vitest'
import { buildApp } from '../../src/index.js'

async function app() { return buildApp({ scheduler: null }) }

async function signupAndToken(a: Awaited<ReturnType<typeof app>>, email: string) {
  const r = await a.inject({ method: 'POST', url: '/api/auth/signup', payload: { email, password: 'hunter22', displayName: email.split('@')[0] } })
  return { token: r.json().token as string, userId: r.json().user.id as string }
}

function auth(token: string) { return { authorization: `Bearer ${token}` } }

describe('POST /api/leagues', () => {
  it('creates a league owned by the caller', async () => {
    const a = await app()
    const { token } = await signupAndToken(a, 'o@x.com')
    const res = await a.inject({ method: 'POST', url: '/api/leagues', headers: auth(token), payload: { name: 'Friends' } })
    expect(res.statusCode).toBe(200)
    const body = res.json()
    expect(body.league.name).toBe('Friends')
    expect(body.league.joinCode).toMatch(/^[A-Z0-9]{6}$/)
    expect(body.league.memberCount).toBe(1)
  })

  it('409s if caller already owns a league', async () => {
    const a = await app()
    const { token } = await signupAndToken(a, 'o2@x.com')
    await a.inject({ method: 'POST', url: '/api/leagues', headers: auth(token), payload: { name: 'L1' } })
    const res = await a.inject({ method: 'POST', url: '/api/leagues', headers: auth(token), payload: { name: 'L2' } })
    expect(res.statusCode).toBe(409)
  })

  it('401 without token', async () => {
    const a = await app()
    const res = await a.inject({ method: 'POST', url: '/api/leagues', payload: { name: 'x' } })
    expect(res.statusCode).toBe(401)
  })
})

describe('GET /api/leagues/mine', () => {
  it('returns leagues with role', async () => {
    const a = await app()
    const owner = await signupAndToken(a, 'own@x.com')
    const joiner = await signupAndToken(a, 'join@x.com')
    const created = await a.inject({ method: 'POST', url: '/api/leagues', headers: auth(owner.token), payload: { name: 'Owners' } })
    const joinerOwned = await a.inject({ method: 'POST', url: '/api/leagues', headers: auth(joiner.token), payload: { name: 'JoinerOwn' } })
    const code = created.json().league.joinCode
    await a.inject({ method: 'POST', url: '/api/leagues/join', headers: auth(joiner.token), payload: { joinCode: code } })

    const res = await a.inject({ method: 'GET', url: '/api/leagues/mine', headers: auth(joiner.token) })
    expect(res.statusCode).toBe(200)
    const byName = new Map(res.json().leagues.map((l: any) => [l.name, l.role]))
    expect(byName.get('Owners')).toBe('member')
    expect(byName.get('JoinerOwn')).toBe('owner')
  })
})

describe('GET /api/leagues/:id', () => {
  it('returns league + members for a member; hides joinCode if not owner', async () => {
    const a = await app()
    const owner = await signupAndToken(a, 'go@x.com')
    const joiner = await signupAndToken(a, 'gj@x.com')
    const created = await a.inject({ method: 'POST', url: '/api/leagues', headers: auth(owner.token), payload: { name: 'L' } })
    const id = created.json().league.id
    const code = created.json().league.joinCode
    await a.inject({ method: 'POST', url: '/api/leagues/join', headers: auth(joiner.token), payload: { joinCode: code } })

    const asOwner = await a.inject({ method: 'GET', url: `/api/leagues/${id}`, headers: auth(owner.token) })
    expect(asOwner.json().league.joinCode).toBe(code)

    const asMember = await a.inject({ method: 'GET', url: `/api/leagues/${id}`, headers: auth(joiner.token) })
    expect(asMember.json().league.joinCode).toBeUndefined()
    expect(asMember.json().members).toHaveLength(2)
  })

  it('403 for non-members', async () => {
    const a = await app()
    const owner = await signupAndToken(a, 'fo@x.com')
    const stranger = await signupAndToken(a, 'fs@x.com')
    const created = await a.inject({ method: 'POST', url: '/api/leagues', headers: auth(owner.token), payload: { name: 'L' } })
    const id = created.json().league.id
    const res = await a.inject({ method: 'GET', url: `/api/leagues/${id}`, headers: auth(stranger.token) })
    expect(res.statusCode).toBe(403)
  })
})

describe('PATCH /api/leagues/:id', () => {
  it('renames when owner', async () => {
    const a = await app()
    const owner = await signupAndToken(a, 'r@x.com')
    const created = await a.inject({ method: 'POST', url: '/api/leagues', headers: auth(owner.token), payload: { name: 'Old' } })
    const id = created.json().league.id
    const res = await a.inject({ method: 'PATCH', url: `/api/leagues/${id}`, headers: auth(owner.token), payload: { name: 'New' } })
    expect(res.statusCode).toBe(200)
    expect(res.json().league.name).toBe('New')
  })

  it('403 when not owner', async () => {
    const a = await app()
    const owner = await signupAndToken(a, 'r2@x.com')
    const joiner = await signupAndToken(a, 'j2@x.com')
    const created = await a.inject({ method: 'POST', url: '/api/leagues', headers: auth(owner.token), payload: { name: 'L' } })
    const id = created.json().league.id
    const code = created.json().league.joinCode
    await a.inject({ method: 'POST', url: '/api/leagues/join', headers: auth(joiner.token), payload: { joinCode: code } })
    const res = await a.inject({ method: 'PATCH', url: `/api/leagues/${id}`, headers: auth(joiner.token), payload: { name: 'Hack' } })
    expect(res.statusCode).toBe(403)
  })
})

describe('POST /api/leagues/:id/regenerate-code', () => {
  it('owner regenerates; old code no longer works', async () => {
    const a = await app()
    const owner = await signupAndToken(a, 'rc@x.com')
    const joiner = await signupAndToken(a, 'rcj@x.com')
    const created = await a.inject({ method: 'POST', url: '/api/leagues', headers: auth(owner.token), payload: { name: 'L' } })
    const id = created.json().league.id
    const oldCode = created.json().league.joinCode

    const regen = await a.inject({ method: 'POST', url: `/api/leagues/${id}/regenerate-code`, headers: auth(owner.token) })
    expect(regen.statusCode).toBe(200)
    expect(regen.json().joinCode).not.toBe(oldCode)

    const tryOld = await a.inject({ method: 'POST', url: '/api/leagues/join', headers: auth(joiner.token), payload: { joinCode: oldCode } })
    expect(tryOld.statusCode).toBe(404)
  })
})

describe('POST /api/leagues/join', () => {
  it('joins via code, idempotent rejection on second join', async () => {
    const a = await app()
    const owner = await signupAndToken(a, 'jo@x.com')
    const joiner = await signupAndToken(a, 'jj@x.com')
    const created = await a.inject({ method: 'POST', url: '/api/leagues', headers: auth(owner.token), payload: { name: 'L' } })
    const code = created.json().league.joinCode

    const j1 = await a.inject({ method: 'POST', url: '/api/leagues/join', headers: auth(joiner.token), payload: { joinCode: code } })
    expect(j1.statusCode).toBe(200)

    const j2 = await a.inject({ method: 'POST', url: '/api/leagues/join', headers: auth(joiner.token), payload: { joinCode: code } })
    expect(j2.statusCode).toBe(409)
  })

  it('404 for unknown code', async () => {
    const a = await app()
    const u = await signupAndToken(a, 'u@x.com')
    const res = await a.inject({ method: 'POST', url: '/api/leagues/join', headers: auth(u.token), payload: { joinCode: 'ZZZZZZ' } })
    expect(res.statusCode).toBe(404)
  })

  it('409 if joining own league', async () => {
    const a = await app()
    const owner = await signupAndToken(a, 'self@x.com')
    const created = await a.inject({ method: 'POST', url: '/api/leagues', headers: auth(owner.token), payload: { name: 'Mine' } })
    const code = created.json().league.joinCode
    const res = await a.inject({ method: 'POST', url: '/api/leagues/join', headers: auth(owner.token), payload: { joinCode: code } })
    expect(res.statusCode).toBe(409)
  })
})

describe('DELETE /api/leagues/:id/members/me', () => {
  it('member can leave; owner cannot use this endpoint', async () => {
    const a = await app()
    const owner = await signupAndToken(a, 'lo@x.com')
    const joiner = await signupAndToken(a, 'lj@x.com')
    const created = await a.inject({ method: 'POST', url: '/api/leagues', headers: auth(owner.token), payload: { name: 'L' } })
    const id = created.json().league.id
    const code = created.json().league.joinCode
    await a.inject({ method: 'POST', url: '/api/leagues/join', headers: auth(joiner.token), payload: { joinCode: code } })

    const leave = await a.inject({ method: 'DELETE', url: `/api/leagues/${id}/members/me`, headers: auth(joiner.token) })
    expect(leave.statusCode).toBe(200)

    const ownerLeaves = await a.inject({ method: 'DELETE', url: `/api/leagues/${id}/members/me`, headers: auth(owner.token) })
    expect(ownerLeaves.statusCode).toBe(409)
  })
})

describe('DELETE /api/leagues/:id/members/:userId', () => {
  it('owner kicks member; cannot kick self', async () => {
    const a = await app()
    const owner = await signupAndToken(a, 'ko@x.com')
    const m = await signupAndToken(a, 'km@x.com')
    const created = await a.inject({ method: 'POST', url: '/api/leagues', headers: auth(owner.token), payload: { name: 'L' } })
    const id = created.json().league.id
    const code = created.json().league.joinCode
    await a.inject({ method: 'POST', url: '/api/leagues/join', headers: auth(m.token), payload: { joinCode: code } })

    const kick = await a.inject({ method: 'DELETE', url: `/api/leagues/${id}/members/${m.userId}`, headers: auth(owner.token) })
    expect(kick.statusCode).toBe(200)

    const self = await a.inject({ method: 'DELETE', url: `/api/leagues/${id}/members/${owner.userId}`, headers: auth(owner.token) })
    expect(self.statusCode).toBe(400)
  })
})

describe('DELETE /api/leagues/:id', () => {
  it('owner deletes league and members are gone', async () => {
    const a = await app()
    const owner = await signupAndToken(a, 'do@x.com')
    const created = await a.inject({ method: 'POST', url: '/api/leagues', headers: auth(owner.token), payload: { name: 'L' } })
    const id = created.json().league.id
    const del = await a.inject({ method: 'DELETE', url: `/api/leagues/${id}`, headers: auth(owner.token) })
    expect(del.statusCode).toBe(200)
    const get = await a.inject({ method: 'GET', url: `/api/leagues/${id}`, headers: auth(owner.token) })
    expect(get.statusCode).toBe(404)
  })
})
```

- [ ] **Step 2: Create `src/api/routes/leagues.ts`**

Create `backend/src/api/routes/leagues.ts`:

```ts
import type { FastifyInstance } from 'fastify'
import { z } from 'zod'
import { ApiError } from '../errors.js'
import * as leaguesRepo from '../../repo/leagues.js'
import * as members from '../../repo/leagueMembers.js'
import { generateUniqueJoinCode } from '../../auth/joinCodes.js'
import { getCurrentUser, registerAuthHook, requireLeagueMember, requireLeagueOwner } from '../auth-context.js'

const createBody = z.object({ name: z.string().trim().min(1).max(60) })
const patchBody = z.object({ name: z.string().trim().min(1).max(60).optional() })
const joinBody = z.object({ joinCode: z.string().trim().min(1).max(20) })

function parse<T>(schema: z.ZodType<T>, body: unknown): T {
  const r = schema.safeParse(body)
  if (!r.success) throw new ApiError('VALIDATION', r.error.issues[0]?.message ?? 'Invalid request body')
  return r.data
}

async function leagueViewForCaller(leagueId: string, callerUserId: string) {
  const l = await leaguesRepo.findById(leagueId)
  if (!l) throw new ApiError('NOT_FOUND', 'League not found')
  const memberCount = await leaguesRepo.countMembers(l.id)
  const isOwner = l.ownerUserId === callerUserId
  return {
    id: l.id,
    name: l.name,
    ownerUserId: l.ownerUserId,
    memberCount,
    createdAt: l.createdAt,
    ...(isOwner ? { joinCode: l.joinCode } : {})
  }
}

export async function registerLeagueRoutes(app: FastifyInstance): Promise<void> {
  registerAuthHook(app)

  app.post('/api/leagues', async (req) => {
    const u = getCurrentUser(req)
    const body = parse(createBody, req.body)

    const existing = await leaguesRepo.listForUser(u.id)
    if (existing.some((l) => l.role === 'owner')) {
      throw new ApiError('CONFLICT', 'You already own a league')
    }

    const joinCode = await generateUniqueJoinCode(async (c) => {
      return (await leaguesRepo.findByJoinCode(c)) !== null
    })
    const l = await leaguesRepo.createLeagueWithOwner({ name: body.name, ownerUserId: u.id, joinCode })
    return { league: await leagueViewForCaller(l.id, u.id) }
  })

  app.get('/api/leagues/mine', async (req) => {
    const u = getCurrentUser(req)
    const list = await leaguesRepo.listForUser(u.id)
    return {
      leagues: list.map((l) => ({
        id: l.id,
        name: l.name,
        ownerUserId: l.ownerUserId,
        role: l.role,
        createdAt: l.createdAt,
        ...(l.role === 'owner' ? { joinCode: l.joinCode } : {})
      }))
    }
  })

  app.get<{ Params: { id: string } }>('/api/leagues/:id', async (req) => {
    const u = getCurrentUser(req)
    await requireLeagueMember(req, req.params.id)
    const league = await leagueViewForCaller(req.params.id, u.id)
    const list = await members.listByLeague(req.params.id)
    const ownerId = league.ownerUserId
    return {
      league,
      members: list.map((m) => ({
        userId: m.userId,
        displayName: m.displayName,
        role: m.userId === ownerId ? 'owner' : 'member',
        joinedAt: m.joinedAt
      }))
    }
  })

  app.patch<{ Params: { id: string } }>('/api/leagues/:id', async (req) => {
    const u = getCurrentUser(req)
    await requireLeagueOwner(req, req.params.id)
    const body = parse(patchBody, req.body)
    if (body.name !== undefined) {
      await leaguesRepo.updateName(req.params.id, body.name)
    }
    return { league: await leagueViewForCaller(req.params.id, u.id) }
  })

  app.post<{ Params: { id: string } }>('/api/leagues/:id/regenerate-code', async (req) => {
    await requireLeagueOwner(req, req.params.id)
    const code = await generateUniqueJoinCode(async (c) => (await leaguesRepo.findByJoinCode(c)) !== null)
    await leaguesRepo.updateJoinCode(req.params.id, code)
    return { joinCode: code }
  })

  app.delete<{ Params: { id: string } }>('/api/leagues/:id', async (req) => {
    await requireLeagueOwner(req, req.params.id)
    await leaguesRepo.deleteById(req.params.id)
    return { ok: true }
  })

  app.post('/api/leagues/join', async (req) => {
    const u = getCurrentUser(req)
    const body = parse(joinBody, req.body)
    const code = body.joinCode.toUpperCase()
    const l = await leaguesRepo.findByJoinCode(code)
    if (!l) throw new ApiError('NOT_FOUND', 'Unknown join code')
    if (l.ownerUserId === u.id) throw new ApiError('CONFLICT', 'You already own this league')
    if (await members.isMember(l.id, u.id)) throw new ApiError('CONFLICT', 'Already a member')
    await members.add(l.id, u.id)
    return { league: await leagueViewForCaller(l.id, u.id) }
  })

  app.delete<{ Params: { id: string } }>('/api/leagues/:id/members/me', async (req) => {
    const u = getCurrentUser(req)
    const l = await leaguesRepo.findById(req.params.id)
    if (!l) throw new ApiError('NOT_FOUND', 'League not found')
    if (l.ownerUserId === u.id) throw new ApiError('CONFLICT', 'Owner must delete the league instead of leaving')
    if (!(await members.isMember(l.id, u.id))) throw new ApiError('NOT_FOUND', 'Not a member')
    await members.remove(l.id, u.id)
    return { ok: true }
  })

  app.delete<{ Params: { id: string; userId: string } }>('/api/leagues/:id/members/:userId', async (req) => {
    await requireLeagueOwner(req, req.params.id)
    const l = await leaguesRepo.findById(req.params.id)
    if (l!.ownerUserId === req.params.userId) {
      throw new ApiError('BAD_REQUEST', 'Cannot kick the league owner')
    }
    await members.remove(req.params.id, req.params.userId)
    return { ok: true }
  })
}
```

- [ ] **Step 3: Register routes in `src/index.ts`**

In `backend/src/index.ts`, add import and registration:

```ts
import { registerLeagueRoutes } from './api/routes/leagues.js'
```

And inside `buildApp`, after `await app.register(registerAuthRoutes)`:

```ts
await app.register(registerLeagueRoutes)
```

- [ ] **Step 4: Verify tests pass**

Run: `cd backend && npx vitest run test/integration/api_leagues.test.ts`
Expected: PASS (all tests).

- [ ] **Step 5: Commit**

```bash
cd backend
git add src/api/routes/leagues.ts src/index.ts test/integration/api_leagues.test.ts
git commit -m "backend: /api/leagues/* routes (CRUD + membership)"
```

---

### Task 9: Session sweeper + scheduler

**Files:**
- Create: `backend/src/auth/sweeper.ts`
- Modify: `backend/src/crawler/scheduler.ts`
- Create: `backend/test/integration/auth_sweeper.test.ts`

- [ ] **Step 1: Write sweeper test**

Create `backend/test/integration/auth_sweeper.test.ts`:

```ts
import { describe, it, expect } from 'vitest'
import * as users from '../../src/repo/users.js'
import * as sessions from '../../src/repo/appSessions.js'
import { hashToken } from '../../src/auth/tokens.js'
import { sweepExpiredSessions } from '../../src/auth/sweeper.js'

describe('session sweeper', () => {
  it('deletes only expired sessions', async () => {
    const u = await users.insertUser({ email: 'sw@x.com', passwordHash: 'h', displayName: 'S' })
    await sessions.insertSession({ userId: u.id, tokenHash: hashToken('exp1'), expiresAt: new Date(Date.now() - 1000), userAgent: null })
    await sessions.insertSession({ userId: u.id, tokenHash: hashToken('exp2'), expiresAt: new Date(Date.now() - 1000), userAgent: null })
    await sessions.insertSession({ userId: u.id, tokenHash: hashToken('live'), expiresAt: new Date(Date.now() + 60_000), userAgent: null })

    const removed = await sweepExpiredSessions()
    expect(removed).toBe(2)

    expect(await sessions.findByTokenHash(hashToken('exp1'))).toBeNull()
    expect(await sessions.findByTokenHash(hashToken('live'))).not.toBeNull()
  })
})
```

- [ ] **Step 2: Implement `src/auth/sweeper.ts`**

Create `backend/src/auth/sweeper.ts`:

```ts
import * as sessionsRepo from '../repo/appSessions.js'

export async function sweepExpiredSessions(): Promise<number> {
  return sessionsRepo.deleteExpired()
}
```

- [ ] **Step 3: Verify sweeper test passes**

Run: `cd backend && npx vitest run test/integration/auth_sweeper.test.ts`
Expected: PASS.

- [ ] **Step 4: Wire sweeper into `src/crawler/scheduler.ts`**

Modify `backend/src/crawler/scheduler.ts`:

1. Add import at the top alongside the other imports:

```ts
import { sweepExpiredSessions } from '../auth/sweeper.js'
```

2. Add a new private field next to `tickJob` / `weeklyJob`:

```ts
  private sweepJob: ScheduledTask | null = null
```

3. Inside `start()`, after the existing `weeklyJob` line, append:

```ts
    // Daily 04:00 UTC — delete expired sessions
    this.sweepJob = cron.schedule('0 4 * * *', () => { void this.sweepOnce() }, { timezone: 'UTC' })
```

4. Inside `stop()`, after `this.weeklyJob = null`, add:

```ts
    this.sweepJob?.stop()
    this.sweepJob = null
```

5. Add a new method on the class next to `weeklyOnce`:

```ts
  async sweepOnce(): Promise<void> {
    try {
      const removed = await sweepExpiredSessions()
      console.log('Session sweep complete', { removed })
    } catch (err) {
      console.error('Session sweep failed', err)
    }
  }
```

- [ ] **Step 5: Verify the full test suite still passes**

Run: `cd backend && npm test`
Expected: all tests PASS.

- [ ] **Step 6: Commit**

```bash
cd backend
git add src/auth/sweeper.ts src/crawler/scheduler.ts test/integration/auth_sweeper.test.ts
git commit -m "backend: daily session sweeper"
```

---

### Task 10: Test factories + README + final verification

**Files:**
- Create: `backend/test/helpers/factories.ts`
- Modify: `backend/README.md`

- [ ] **Step 1: Create `test/helpers/factories.ts`**

Create `backend/test/helpers/factories.ts`:

```ts
import * as users from '../../src/repo/users.js'
import * as leagues from '../../src/repo/leagues.js'
import { hashPassword } from '../../src/auth/password.js'

let n = 0
const seq = () => ++n

export async function makeUser(overrides: Partial<{ email: string; password: string; displayName: string }> = {}) {
  const i = seq()
  const password = overrides.password ?? 'hunter22'
  return users.insertUser({
    email: overrides.email ?? `user${i}-${Date.now()}@example.com`,
    passwordHash: await hashPassword(password),
    displayName: overrides.displayName ?? `User ${i}`
  })
}

export async function makeLeague(ownerUserId: string, overrides: Partial<{ name: string; joinCode: string }> = {}) {
  const i = seq()
  return leagues.createLeagueWithOwner({
    name: overrides.name ?? `League ${i}`,
    ownerUserId,
    joinCode: overrides.joinCode ?? `LG${String(i).padStart(4, '0')}`.slice(0, 6)
  })
}
```

(Factories aren't used by the tests written in earlier tasks — they're a tool for future test files in subsequent sub-projects. Adding them now while the patterns are fresh.)

- [ ] **Step 2: Update `backend/README.md`**

Append two new sections to `backend/README.md`. After the existing API table, add the new endpoints (insert appropriate rows alphabetically by path):

```
| POST | `/api/auth/signup` | Create account, returns `{ user, token }` |
| POST | `/api/auth/login` | Login, returns `{ user, token }` |
| POST | `/api/auth/logout` | Revoke caller's session (bearer) |
| GET  | `/api/auth/me` | Current user + caller's leagues (bearer) |
| PATCH | `/api/auth/me` | Update display name (bearer) |
| POST | `/api/leagues` | Create caller's league (bearer, 1-per-user) |
| GET  | `/api/leagues/mine` | List leagues caller belongs to (bearer) |
| GET  | `/api/leagues/:id` | League + members; `joinCode` visible to owner only (bearer + member) |
| PATCH | `/api/leagues/:id` | Rename (bearer + owner) |
| POST | `/api/leagues/:id/regenerate-code` | New join code (bearer + owner) |
| DELETE | `/api/leagues/:id` | Delete league (bearer + owner) |
| POST | `/api/leagues/join` | Join via `{ joinCode }` (bearer) |
| DELETE | `/api/leagues/:id/members/me` | Leave league (bearer + member, not owner) |
| DELETE | `/api/leagues/:id/members/:userId` | Kick member (bearer + owner) |
```

Under the "What's NOT in this sub-project" section, replace the line that lists user accounts/auth (since they now exist) — leave only "predictions, scoring engine, pre-season questionnaire, Flutter UI changes" as still-deferred.

Add a one-line note near the top about authentication:

> Authenticated endpoints require `Authorization: Bearer <token>` where `<token>` comes from `/api/auth/signup` or `/api/auth/login`. Sessions slide a 90-day expiry on every request.

- [ ] **Step 3: Run the full test suite**

Run: `cd backend && npm test`
Expected: all tests PASS.

- [ ] **Step 4: Type-check the whole project**

Run: `cd backend && npx tsc --noEmit`
Expected: no errors.

- [ ] **Step 5: Manual end-to-end smoke test**

Start the dev server (`cd backend && npm run dev`), then in another shell:

```bash
# Signup
TOKEN=$(curl -s -X POST http://localhost:3000/api/auth/signup \
  -H 'content-type: application/json' \
  -d '{"email":"smoke@x.com","password":"hunter22","displayName":"Smoke"}' | jq -r .token)

# Me
curl -s -H "authorization: Bearer $TOKEN" http://localhost:3000/api/auth/me | jq

# Create league
CODE=$(curl -s -X POST http://localhost:3000/api/leagues \
  -H "authorization: Bearer $TOKEN" -H 'content-type: application/json' \
  -d '{"name":"Smoke League"}' | jq -r .league.joinCode)

echo "Join code: $CODE"

# List mine
curl -s -H "authorization: Bearer $TOKEN" http://localhost:3000/api/leagues/mine | jq
```

Expected: each step returns 2xx and the data echoes through correctly.

- [ ] **Step 6: Commit**

```bash
cd backend
git add test/helpers/factories.ts README.md
git commit -m "backend: test factories + README update for auth + leagues"
```

---

## Done

All ten tasks complete means:

- Migration 0002 applied (`user`, `app_session`, `league`, `league_member` tables exist)
- All unit + integration tests pass
- `npx tsc --noEmit` is clean
- Manual smoke test exercises signup → me → create league → list mine without errors
- README documents the new endpoints

Hand-off: the Flutter team (parallel track) can now build the signup, login, and league-join screens against this backend without further backend changes. The next backend sub-project (predictions) will read the `user_id` from `req.user` exactly the way these routes do.
