# Admin Tool — Plan 1: Backend Admin Read Endpoints

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `X-Admin-Token`-gated read endpoints to the backend so the admin tool can browse leagues+members, users, all sessions (fetch health), predictions, and crawl status — data the existing public/user-scoped API can't expose.

**Architecture:** New repo functions (Drizzle queries) + a new `registerAdminReadRoutes(app)` route module registered on the root Fastify app right after `registerAdminRoutes`, so the existing admin-token `preHandler` gates them. Pure additions — no existing route or table changes.

**Tech Stack:** Fastify 5, Drizzle ORM (PostgreSQL), Zod, TypeScript ESM, Vitest (integration, single-fork against a real Postgres).

## Global Constraints

- Node `>=22`, TypeScript ESM: **all relative imports use the `.js` extension** (e.g. `import { getDb } from '../db/client.js'`), even for `.ts` files.
- Admin auth: every `/admin/*` route is gated by the `preHandler` in `src/api/routes/admin.ts:45-51` (`x-admin-token` header must equal `config.adminToken`). New read routes must be registered on the **same root `app` instance** (plain function call, not an encapsulated `app.register`) so the hook covers them.
- Errors: throw `new ApiError(code, message)` from `src/api/errors.js`. Codes: `NOT_FOUND`, `BAD_REQUEST`, `VALIDATION`, `UNAUTHORIZED`, etc. (status map in `errors.ts`).
- Repo layer only — no raw SQL in route handlers. Repos use `getDb()` from `src/db/client.js` and Drizzle table objects from `src/db/schema.js` (`league`, `leagueMember`, `user`, `session`, `event`, `sessionResult`, `prediction`, `predictionPick`).
- Tests: integration tests live in `backend/test/integration/`, named `*.test.ts`. The admin token in the test env is the literal string `'local-dev-token'`. Build the app with `await buildApp({ scheduler: null })` and use `app.inject(...)`. The harness truncates all tables `beforeEach` (`test/helpers/setup.ts`). Seed via repo functions. Run the suite with `npm test` from `backend/` (or `make backend-test` from repo root).
- Don't introduce new dependencies.

## File Structure

- **Create** `backend/src/api/routes/adminReads.ts` — `registerAdminReadRoutes(app)`; all new GET `/admin/*` read handlers.
- **Modify** `backend/src/index.ts` — import and call `registerAdminReadRoutes(app)` after `registerAdminRoutes(...)`.
- **Modify** `backend/src/repo/leagues.ts` — add `listAllWithMeta()`.
- **Modify** `backend/src/repo/leagueMembers.ts` — add `listByLeagueDetailed(leagueId)`.
- **Modify** `backend/src/repo/users.ts` — add `listAllWithMeta({ query, limit, offset })` and `getDetail(id)`.
- **Modify** `backend/src/repo/sessions.ts` — add `listAllWithFetchMeta(seasonYear?)`.
- **Modify** `backend/src/repo/predictions.ts` — add `listForAdmin({ sessionId?, userId?, leagueId? })`.
- **Create** `backend/test/integration/api_admin_reads.test.ts` — covers all read endpoints + the token gate.

---

### Task 1: `GET /admin/leagues` and `GET /admin/leagues/:id`

**Files:**
- Modify: `backend/src/repo/leagues.ts`
- Modify: `backend/src/repo/leagueMembers.ts`
- Create: `backend/src/api/routes/adminReads.ts`
- Modify: `backend/src/index.ts`
- Create: `backend/test/integration/api_admin_reads.test.ts`

**Interfaces:**
- Produces:
  - `leaguesRepo.listAllWithMeta(): Promise<AdminLeagueRow[]>` where
    `AdminLeagueRow = { id: string; name: string; ownerUserId: string; ownerDisplayName: string; memberCount: number; joinCode: string; hasPassword: boolean; createdAt: Date }`
  - `leagueMembersRepo.listByLeagueDetailed(leagueId: string): Promise<AdminMemberRow[]>` where
    `AdminMemberRow = { userId: string; displayName: string; email: string; role: 'owner' | 'member'; joinedAt: Date }`
  - `registerAdminReadRoutes(app: FastifyInstance): Promise<void>`
  - Routes: `GET /admin/leagues` → `{ leagues: AdminLeagueRow[] }`; `GET /admin/leagues/:id` → `{ league: AdminLeagueRow; members: AdminMemberRow[] }` (404 if league missing).

- [ ] **Step 1: Write the failing test**

Create `backend/test/integration/api_admin_reads.test.ts`:

```ts
import { describe, it, expect } from 'vitest'
import { buildApp } from '../../src/index.js'
import * as users from '../../src/repo/users.js'
import * as leagues from '../../src/repo/leagues.js'
import * as leagueMembers from '../../src/repo/leagueMembers.js'

const TOKEN = { 'x-admin-token': 'local-dev-token' }

describe('GET /admin/leagues', () => {
  it('requires the admin token', async () => {
    const app = await buildApp({ scheduler: null })
    const res = await app.inject({ method: 'GET', url: '/admin/leagues' })
    expect(res.statusCode).toBe(401)
    await app.close()
  })

  it('lists all leagues with owner name and member count', async () => {
    const owner = await users.insertUser({ email: 'o@x.com', passwordHash: 'h', displayName: 'Owner' })
    const member = await users.insertUser({ email: 'm@x.com', passwordHash: 'h', displayName: 'Member' })
    const lg = await leagues.createLeagueWithOwner({ name: 'My League', ownerUserId: owner.id, joinCode: 'ABC123' })
    await leagueMembers.add(lg.id, member.id)

    const app = await buildApp({ scheduler: null })
    const res = await app.inject({ method: 'GET', url: '/admin/leagues', headers: TOKEN })
    expect(res.statusCode).toBe(200)
    const body = res.json()
    expect(body.leagues).toHaveLength(1)
    expect(body.leagues[0]).toMatchObject({
      id: lg.id, name: 'My League', ownerUserId: owner.id,
      ownerDisplayName: 'Owner', memberCount: 2, joinCode: 'ABC123', hasPassword: false
    })
    await app.close()
  })

  it('returns one league with its members', async () => {
    const owner = await users.insertUser({ email: 'o2@x.com', passwordHash: 'h', displayName: 'Owner2' })
    const member = await users.insertUser({ email: 'm2@x.com', passwordHash: 'h', displayName: 'Member2' })
    const lg = await leagues.createLeagueWithOwner({ name: 'L2', ownerUserId: owner.id, joinCode: 'DEF456' })
    await leagueMembers.add(lg.id, member.id)

    const app = await buildApp({ scheduler: null })
    const res = await app.inject({ method: 'GET', url: `/admin/leagues/${lg.id}`, headers: TOKEN })
    expect(res.statusCode).toBe(200)
    const body = res.json()
    expect(body.league.id).toBe(lg.id)
    expect(body.members).toHaveLength(2)
    const ownerRow = body.members.find((m: any) => m.userId === owner.id)
    expect(ownerRow).toMatchObject({ role: 'owner', email: 'o2@x.com', displayName: 'Owner2' })
    expect(body.members.find((m: any) => m.userId === member.id).role).toBe('member')
    await app.close()
  })

  it('404s an unknown league', async () => {
    const app = await buildApp({ scheduler: null })
    const res = await app.inject({
      method: 'GET',
      url: '/admin/leagues/00000000-0000-0000-0000-000000000000',
      headers: TOKEN
    })
    expect(res.statusCode).toBe(404)
    await app.close()
  })
})
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd backend && set -a && source .env && set +a && npx vitest run test/integration/api_admin_reads.test.ts`
Expected: FAIL — `buildApp` has no `/admin/leagues` route (404), and `listAllWithMeta` is undefined.

- [ ] **Step 3: Add the repo functions**

Append to `backend/src/repo/leagues.ts`:

```ts
export type AdminLeagueRow = {
  id: string
  name: string
  ownerUserId: string
  ownerDisplayName: string
  memberCount: number
  joinCode: string
  hasPassword: boolean
  createdAt: Date
}

export async function listAllWithMeta(): Promise<AdminLeagueRow[]> {
  const db = getDb()
  const rows = await db
    .select({
      id: league.id,
      name: league.name,
      ownerUserId: league.ownerUserId,
      ownerDisplayName: user.displayName,
      joinCode: league.joinCode,
      passwordHash: league.passwordHash,
      createdAt: league.createdAt,
      memberCount: sql<number>`(
        select count(*)::int from ${leagueMember}
        where ${leagueMember.leagueId} = ${league.id}
      )`
    })
    .from(league)
    .innerJoin(user, eq(user.id, league.ownerUserId))
    .orderBy(league.createdAt)
  return rows.map((r) => ({
    id: r.id,
    name: r.name,
    ownerUserId: r.ownerUserId,
    ownerDisplayName: r.ownerDisplayName,
    memberCount: r.memberCount,
    joinCode: r.joinCode,
    hasPassword: r.passwordHash !== null,
    createdAt: r.createdAt
  }))
}
```

This file already imports `eq, sql` from `drizzle-orm` and `league, leagueMember` plus `user`? Check the imports — `leagues.ts` imports `{ league, leagueMember }`. Add `user`:

Change `backend/src/repo/leagues.ts:3` from:
```ts
import { league, leagueMember } from '../db/schema.js'
```
to:
```ts
import { league, leagueMember, user } from '../db/schema.js'
```

Append to `backend/src/repo/leagueMembers.ts`:

```ts
export type AdminMemberRow = {
  userId: string
  displayName: string
  email: string
  role: 'owner' | 'member'
  joinedAt: Date
}

export async function listByLeagueDetailed(leagueId: string): Promise<AdminMemberRow[]> {
  const db = getDb()
  const rows = await db
    .select({
      userId: leagueMember.userId,
      displayName: user.displayName,
      email: user.email,
      joinedAt: leagueMember.joinedAt,
      ownerUserId: league.ownerUserId
    })
    .from(leagueMember)
    .innerJoin(user, eq(user.id, leagueMember.userId))
    .innerJoin(league, eq(league.id, leagueMember.leagueId))
    .where(eq(leagueMember.leagueId, leagueId))
    .orderBy(leagueMember.joinedAt)
  return rows.map((r) => ({
    userId: r.userId,
    displayName: r.displayName,
    email: r.email,
    role: r.userId === r.ownerUserId ? 'owner' : 'member',
    joinedAt: r.joinedAt
  }))
}
```

Update `backend/src/repo/leagueMembers.ts:3` to import `league` too:
```ts
import { leagueMember, user, league } from '../db/schema.js'
```

- [ ] **Step 4: Create the route module**

Create `backend/src/api/routes/adminReads.ts`:

```ts
import type { FastifyInstance } from 'fastify'
import { ApiError } from '../errors.js'
import * as leaguesRepo from '../../repo/leagues.js'
import * as leagueMembersRepo from '../../repo/leagueMembers.js'

// Read-only admin endpoints. Registered on the root app after
// registerAdminRoutes, so the /admin/* token preHandler defined there gates
// every route here too.
export async function registerAdminReadRoutes(app: FastifyInstance): Promise<void> {
  app.get('/admin/leagues', async () => {
    const leagues = await leaguesRepo.listAllWithMeta()
    return { leagues }
  })

  app.get<{ Params: { id: string } }>('/admin/leagues/:id', async (req) => {
    const all = await leaguesRepo.listAllWithMeta()
    const league = all.find((l) => l.id === req.params.id)
    if (!league) throw new ApiError('NOT_FOUND', `League ${req.params.id} not found`)
    const members = await leagueMembersRepo.listByLeagueDetailed(req.params.id)
    return { league, members }
  })
}
```

- [ ] **Step 5: Register the module in `index.ts`**

Add the import after line 18 (`registerDeviceRoutes` import) in `backend/src/index.ts`:
```ts
import { registerAdminReadRoutes } from './api/routes/adminReads.js'
```

Add the call immediately after `registerAdminRoutes(...)` (currently `backend/src/index.ts:45`):
```ts
  await registerAdminReadRoutes(app)
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `cd backend && set -a && source .env && set +a && npx vitest run test/integration/api_admin_reads.test.ts`
Expected: PASS (4 tests).

- [ ] **Step 7: Commit**

```bash
git add backend/src/repo/leagues.ts backend/src/repo/leagueMembers.ts \
  backend/src/api/routes/adminReads.ts backend/src/index.ts \
  backend/test/integration/api_admin_reads.test.ts
git commit -m "feat(admin): GET /admin/leagues and /admin/leagues/:id"
```

---

### Task 2: `GET /admin/users` and `GET /admin/users/:id`

**Files:**
- Modify: `backend/src/repo/users.ts`
- Modify: `backend/src/api/routes/adminReads.ts`
- Modify: `backend/test/integration/api_admin_reads.test.ts`

**Interfaces:**
- Consumes: `registerAdminReadRoutes` (Task 1).
- Produces:
  - `usersRepo.listAllWithMeta(opts: { query?: string; limit: number; offset: number }): Promise<{ rows: AdminUserRow[]; total: number }>` where
    `AdminUserRow = { id: string; email: string; displayName: string; createdAt: Date; leagueCount: number }`
  - `usersRepo.getDetail(id: string): Promise<AdminUserDetail | null>` where
    `AdminUserDetail = { id: string; email: string; displayName: string; createdAt: Date; updatedAt: Date; leagues: { id: string; name: string; role: 'owner' | 'member' }[]; predictionCount: number }`
  - Routes: `GET /admin/users?query=&limit=&offset=` → `{ users: AdminUserRow[]; total: number }`; `GET /admin/users/:id` → `{ user: AdminUserDetail }` (404 if missing).

- [ ] **Step 1: Write the failing test**

Append to `backend/test/integration/api_admin_reads.test.ts`:

```ts
import * as sessions from '../../src/repo/sessions.js'
import * as events from '../../src/repo/events.js'
import * as seasons from '../../src/repo/seasons.js'
import * as drivers from '../../src/repo/drivers.js'
import * as predictions from '../../src/repo/predictions.js'

describe('GET /admin/users', () => {
  it('lists users with league counts and supports search', async () => {
    const a = await users.insertUser({ email: 'alice@x.com', passwordHash: 'h', displayName: 'Alice' })
    await users.insertUser({ email: 'bob@x.com', passwordHash: 'h', displayName: 'Bob' })
    await leagues.createLeagueWithOwner({ name: 'AL', ownerUserId: a.id, joinCode: 'AAA111' })

    const app = await buildApp({ scheduler: null })
    const all = await app.inject({ method: 'GET', url: '/admin/users', headers: TOKEN })
    expect(all.statusCode).toBe(200)
    expect(all.json().total).toBe(2)
    const alice = all.json().users.find((u: any) => u.id === a.id)
    expect(alice.leagueCount).toBe(1)

    const search = await app.inject({ method: 'GET', url: '/admin/users?query=bob', headers: TOKEN })
    expect(search.json().total).toBe(1)
    expect(search.json().users[0].displayName).toBe('Bob')
    await app.close()
  })

  it('returns user detail with leagues and prediction count', async () => {
    const u = await users.insertUser({ email: 'd@x.com', passwordHash: 'h', displayName: 'Dee' })
    await leagues.createLeagueWithOwner({ name: 'DL', ownerUserId: u.id, joinCode: 'DDD111' })
    await seasons.upsertSeason({ year: 2026, isCurrent: true })
    const ev = await events.upsertEvent({ seasonYear: 2026, round: 1, name: 'GP', circuitName: 'C', country: 'X', hasSprint: false })
    const ses = await sessions.upsertSession({ eventId: ev.id, type: 'race', scheduledStart: new Date('2026-03-01T14:00:00Z'), scheduledEnd: new Date('2026-03-01T16:00:00Z'), status: 'scheduled', openf1SessionKey: null })
    await drivers.upsertDriver({ code: 'VER', givenName: 'M', familyName: 'V', nationality: null, permanentNumber: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, headshotUrl: null })
    await predictions.upsertPredictionWithPicks(u.id, ses.id, [{ position: 1, driverCode: 'VER' }])

    const app = await buildApp({ scheduler: null })
    const res = await app.inject({ method: 'GET', url: `/admin/users/${u.id}`, headers: TOKEN })
    expect(res.statusCode).toBe(200)
    const body = res.json()
    expect(body.user.email).toBe('d@x.com')
    expect(body.user.leagues).toHaveLength(1)
    expect(body.user.leagues[0].role).toBe('owner')
    expect(body.user.predictionCount).toBe(1)
    await app.close()
  })

  it('404s an unknown user', async () => {
    const app = await buildApp({ scheduler: null })
    const res = await app.inject({ method: 'GET', url: '/admin/users/00000000-0000-0000-0000-000000000000', headers: TOKEN })
    expect(res.statusCode).toBe(404)
    await app.close()
  })
})
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd backend && set -a && source .env && set +a && npx vitest run test/integration/api_admin_reads.test.ts -t "admin/users"`
Expected: FAIL — no `/admin/users` route; `listAllWithMeta`/`getDetail` undefined.

- [ ] **Step 3: Add the repo functions**

Append to `backend/src/repo/users.ts` (the file imports `eq, sql`; add `ilike, and, count` usage via `sql`). Replace the import line `backend/src/repo/users.ts:1`:
```ts
import { eq, sql, ilike, or, asc } from 'drizzle-orm'
```
Add `import { league, leagueMember, prediction } from '../db/schema.js'` after the existing `user` import (line 3 imports `{ user }` — change to):
```ts
import { user, league, leagueMember, prediction } from '../db/schema.js'
```

Then append:
```ts
export type AdminUserRow = {
  id: string
  email: string
  displayName: string
  createdAt: Date
  leagueCount: number
}

export async function listAllWithMeta(
  opts: { query?: string; limit: number; offset: number }
): Promise<{ rows: AdminUserRow[]; total: number }> {
  const db = getDb()
  const where = opts.query && opts.query.trim() !== ''
    ? or(ilike(user.email, `%${opts.query}%`), ilike(user.displayName, `%${opts.query}%`))
    : undefined

  const rows = await db
    .select({
      id: user.id,
      email: user.email,
      displayName: user.displayName,
      createdAt: user.createdAt,
      leagueCount: sql<number>`(
        select count(*)::int from ${leagueMember}
        where ${leagueMember.userId} = ${user.id}
      )`
    })
    .from(user)
    .where(where)
    .orderBy(asc(user.createdAt))
    .limit(opts.limit)
    .offset(opts.offset)

  const totalRows = await db.select({ c: sql<number>`count(*)::int` }).from(user).where(where)
  return { rows, total: totalRows[0]?.c ?? 0 }
}

export type AdminUserDetail = {
  id: string
  email: string
  displayName: string
  createdAt: Date
  updatedAt: Date
  leagues: { id: string; name: string; role: 'owner' | 'member' }[]
  predictionCount: number
}

export async function getDetail(id: string): Promise<AdminUserDetail | null> {
  const db = getDb()
  const rows = await db.select().from(user).where(eq(user.id, id)).limit(1)
  const row = rows[0]
  if (!row) return null

  const leagueRows = await db
    .select({
      id: league.id,
      name: league.name,
      ownerUserId: league.ownerUserId
    })
    .from(leagueMember)
    .innerJoin(league, eq(league.id, leagueMember.leagueId))
    .where(eq(leagueMember.userId, id))

  const predCount = await db
    .select({ c: sql<number>`count(*)::int` })
    .from(prediction)
    .where(eq(prediction.userId, id))

  return {
    id: row.id,
    email: row.email,
    displayName: row.displayName,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    leagues: leagueRows.map((l) => ({
      id: l.id,
      name: l.name,
      role: l.ownerUserId === id ? 'owner' : 'member'
    })),
    predictionCount: predCount[0]?.c ?? 0
  }
}
```

- [ ] **Step 4: Add the routes**

In `backend/src/api/routes/adminReads.ts`, add the import:
```ts
import * as usersRepo from '../../repo/users.js'
```
and inside `registerAdminReadRoutes`, append:
```ts
  app.get<{ Querystring: { query?: string; limit?: string; offset?: string } }>(
    '/admin/users',
    async (req) => {
      const limit = Math.min(Number(req.query.limit) || 50, 200)
      const offset = Number(req.query.offset) || 0
      const { rows, total } = await usersRepo.listAllWithMeta({ query: req.query.query, limit, offset })
      return { users: rows, total }
    }
  )

  app.get<{ Params: { id: string } }>('/admin/users/:id', async (req) => {
    const user = await usersRepo.getDetail(req.params.id)
    if (!user) throw new ApiError('NOT_FOUND', `User ${req.params.id} not found`)
    return { user }
  })
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd backend && set -a && source .env && set +a && npx vitest run test/integration/api_admin_reads.test.ts`
Expected: PASS (all `admin/users` + Task 1 tests).

- [ ] **Step 6: Commit**

```bash
git add backend/src/repo/users.ts backend/src/api/routes/adminReads.ts \
  backend/test/integration/api_admin_reads.test.ts
git commit -m "feat(admin): GET /admin/users and /admin/users/:id"
```

---

### Task 3: `GET /admin/sessions` (fetch-health view)

**Files:**
- Modify: `backend/src/repo/sessions.ts`
- Modify: `backend/src/api/routes/adminReads.ts`
- Modify: `backend/test/integration/api_admin_reads.test.ts`

**Interfaces:**
- Consumes: `registerAdminReadRoutes` (Task 1).
- Produces:
  - `sessionsRepo.listAllWithFetchMeta(seasonYear?: number): Promise<AdminSessionRow[]>` where
    `AdminSessionRow = { id: number; seasonYear: number; round: number; eventName: string; type: string; status: 'scheduled' | 'finished'; scheduledStart: Date; scheduledEnd: Date; lastReconciledAt: Date | null; resultCount: number; provisional: boolean }`
    (`provisional` = has ≥1 result row with `source='openf1'`.)
  - Route: `GET /admin/sessions?season=YYYY` → `{ sessions: AdminSessionRow[] }` (all seasons when `season` omitted), ordered by `scheduledStart` ascending.

- [ ] **Step 1: Write the failing test**

Append to `backend/test/integration/api_admin_reads.test.ts`:

```ts
import * as results from '../../src/repo/results.js'
import * as constructors from '../../src/repo/constructors.js'

describe('GET /admin/sessions', () => {
  it('lists sessions with event metadata, result count and provisional flag', async () => {
    await seasons.upsertSeason({ year: 2026, isCurrent: true })
    const ev = await events.upsertEvent({ seasonYear: 2026, round: 1, name: 'Bahrain GP', circuitName: 'Sakhir', country: 'BH', hasSprint: false })
    const ses = await sessions.upsertSession({ eventId: ev.id, type: 'race', scheduledStart: new Date('2026-03-01T14:00:00Z'), scheduledEnd: new Date('2026-03-01T16:00:00Z'), status: 'finished', openf1SessionKey: 999 })
    await constructors.upsertConstructor({ id: 'red_bull', name: 'Red Bull', nationality: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, teamColour: null })
    await drivers.upsertDriver({ code: 'VER', givenName: 'M', familyName: 'V', nationality: null, permanentNumber: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, headshotUrl: null })
    await results.replaceForSession(ses.id, [{
      sessionId: ses.id, position: 1, driverCode: 'VER', driverName: 'Max Verstappen',
      constructorId: 'red_bull', constructorName: 'Red Bull', raceTime: null, status: 'Finished',
      points: 25, fastestLap: null, fastestLapTime: null, fastestLapSpeed: null, q1: null, q2: null, q3: null,
      source: 'openf1'
    }])

    const app = await buildApp({ scheduler: null })
    const res = await app.inject({ method: 'GET', url: '/admin/sessions?season=2026', headers: TOKEN })
    expect(res.statusCode).toBe(200)
    const rows = res.json().sessions
    expect(rows).toHaveLength(1)
    expect(rows[0]).toMatchObject({
      id: ses.id, seasonYear: 2026, round: 1, eventName: 'Bahrain GP',
      type: 'race', status: 'finished', resultCount: 1, provisional: true
    })
    await app.close()
  })
})
```

> Note: confirm the exact `replaceForSession` row shape against `backend/src/repo/results.ts` before running — adjust field names if the repo's input type differs. The fields above mirror the `session_result` columns.

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd backend && set -a && source .env && set +a && npx vitest run test/integration/api_admin_reads.test.ts -t "admin/sessions"`
Expected: FAIL — no `/admin/sessions` route; `listAllWithFetchMeta` undefined.

- [ ] **Step 3: Add the repo function**

Append to `backend/src/repo/sessions.ts`. Add `event` and `sessionResult` to the schema import (line 3 imports `{ session }` — change to):
```ts
import { session, event, sessionResult } from '../db/schema.js'
```

Then append:
```ts
export type AdminSessionRow = {
  id: number
  seasonYear: number
  round: number
  eventName: string
  type: string
  status: 'scheduled' | 'finished'
  scheduledStart: Date
  scheduledEnd: Date
  lastReconciledAt: Date | null
  resultCount: number
  provisional: boolean
}

export async function listAllWithFetchMeta(seasonYear?: number): Promise<AdminSessionRow[]> {
  const db = getDb()
  const rows = await db
    .select({
      id: session.id,
      seasonYear: event.seasonYear,
      round: event.round,
      eventName: event.name,
      type: session.type,
      status: session.status,
      scheduledStart: session.scheduledStart,
      scheduledEnd: session.scheduledEnd,
      lastReconciledAt: session.lastReconciledAt,
      resultCount: sql<number>`(
        select count(*)::int from ${sessionResult}
        where ${sessionResult.sessionId} = ${session.id}
      )`,
      provisional: sql<boolean>`exists(
        select 1 from ${sessionResult}
        where ${sessionResult.sessionId} = ${session.id}
          and ${sessionResult.source} = 'openf1'
      )`
    })
    .from(session)
    .innerJoin(event, eq(event.id, session.eventId))
    .where(seasonYear === undefined ? undefined : eq(event.seasonYear, seasonYear))
    .orderBy(asc(session.scheduledStart))
  return rows as AdminSessionRow[]
}
```

- [ ] **Step 4: Add the route**

In `backend/src/api/routes/adminReads.ts`, add the import:
```ts
import * as sessionsRepo from '../../repo/sessions.js'
```
and inside `registerAdminReadRoutes`, append:
```ts
  app.get<{ Querystring: { season?: string } }>('/admin/sessions', async (req) => {
    const season = req.query.season ? Number(req.query.season) : undefined
    if (season !== undefined && !Number.isFinite(season)) {
      throw new ApiError('BAD_REQUEST', 'season must be a number')
    }
    const sessions = await sessionsRepo.listAllWithFetchMeta(season)
    return { sessions }
  })
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd backend && set -a && source .env && set +a && npx vitest run test/integration/api_admin_reads.test.ts`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add backend/src/repo/sessions.ts backend/src/api/routes/adminReads.ts \
  backend/test/integration/api_admin_reads.test.ts
git commit -m "feat(admin): GET /admin/sessions fetch-health view"
```

---

### Task 4: `GET /admin/predictions`

**Files:**
- Modify: `backend/src/repo/predictions.ts`
- Modify: `backend/src/api/routes/adminReads.ts`
- Modify: `backend/test/integration/api_admin_reads.test.ts`

**Interfaces:**
- Consumes: `registerAdminReadRoutes` (Task 1).
- Produces:
  - `predictionsRepo.listForAdmin(filter: { sessionId?: number; userId?: string; leagueId?: string }): Promise<AdminPredictionRow[]>` where
    `AdminPredictionRow = { predictionId: string; userId: string; displayName: string; sessionId: number; source: string; updatedAt: Date; picks: { position: number; driverCode: string }[] }`
  - Route: `GET /admin/predictions?sessionId=&userId=&leagueId=` → `{ predictions: AdminPredictionRow[] }`. At least one filter required (else `BAD_REQUEST`).

- [ ] **Step 1: Write the failing test**

Append to `backend/test/integration/api_admin_reads.test.ts`:

```ts
describe('GET /admin/predictions', () => {
  it('requires at least one filter', async () => {
    const app = await buildApp({ scheduler: null })
    const res = await app.inject({ method: 'GET', url: '/admin/predictions', headers: TOKEN })
    expect(res.statusCode).toBe(400)
    await app.close()
  })

  it('lists predictions for a session with picks and display names', async () => {
    const u = await users.insertUser({ email: 'p@x.com', passwordHash: 'h', displayName: 'Pat' })
    await seasons.upsertSeason({ year: 2026, isCurrent: true })
    const ev = await events.upsertEvent({ seasonYear: 2026, round: 1, name: 'GP', circuitName: 'C', country: 'X', hasSprint: false })
    const ses = await sessions.upsertSession({ eventId: ev.id, type: 'race', scheduledStart: new Date('2026-03-01T14:00:00Z'), scheduledEnd: new Date('2026-03-01T16:00:00Z'), status: 'scheduled', openf1SessionKey: null })
    await drivers.upsertDriver({ code: 'VER', givenName: 'M', familyName: 'V', nationality: null, permanentNumber: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, headshotUrl: null })
    await predictions.upsertPredictionWithPicks(u.id, ses.id, [{ position: 1, driverCode: 'VER' }])

    const app = await buildApp({ scheduler: null })
    const res = await app.inject({ method: 'GET', url: `/admin/predictions?sessionId=${ses.id}`, headers: TOKEN })
    expect(res.statusCode).toBe(200)
    const rows = res.json().predictions
    expect(rows).toHaveLength(1)
    expect(rows[0]).toMatchObject({ userId: u.id, displayName: 'Pat', sessionId: ses.id, source: 'app' })
    expect(rows[0].picks).toEqual([{ position: 1, driverCode: 'VER' }])
    await app.close()
  })
})
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd backend && set -a && source .env && set +a && npx vitest run test/integration/api_admin_reads.test.ts -t "admin/predictions"`
Expected: FAIL — no route; `listForAdmin` undefined.

- [ ] **Step 3: Add the repo function**

Append to `backend/src/repo/predictions.ts` (it already imports `and, eq, inArray, sql` and `leagueMember, prediction, predictionPick, user`; add `desc`):

Change `backend/src/repo/predictions.ts:1` to:
```ts
import { and, eq, inArray, sql, desc } from 'drizzle-orm'
```

Then append:
```ts
export type AdminPredictionRow = {
  predictionId: string
  userId: string
  displayName: string
  sessionId: number
  source: string
  updatedAt: Date
  picks: { position: number; driverCode: string }[]
}

export async function listForAdmin(
  filter: { sessionId?: number; userId?: string; leagueId?: string }
): Promise<AdminPredictionRow[]> {
  const db = getDb()
  const conds = []
  if (filter.sessionId !== undefined) conds.push(eq(prediction.sessionId, filter.sessionId))
  if (filter.userId !== undefined) conds.push(eq(prediction.userId, filter.userId))
  if (filter.leagueId !== undefined) {
    const memberRows = await db
      .select({ userId: leagueMember.userId })
      .from(leagueMember)
      .where(eq(leagueMember.leagueId, filter.leagueId))
    const ids = memberRows.map((m) => m.userId)
    // No members → no predictions. inArray on [] throws, so short-circuit.
    if (ids.length === 0) return []
    conds.push(inArray(prediction.userId, ids))
  }

  const rows = await db
    .select({
      predictionId: prediction.id,
      userId: prediction.userId,
      displayName: user.displayName,
      sessionId: prediction.sessionId,
      source: prediction.source,
      updatedAt: prediction.updatedAt,
      position: predictionPick.position,
      driverCode: predictionPick.driverCode
    })
    .from(prediction)
    .innerJoin(user, eq(user.id, prediction.userId))
    .leftJoin(predictionPick, eq(predictionPick.predictionId, prediction.id))
    .where(and(...conds))
    .orderBy(desc(prediction.updatedAt))

  const byPrediction = new Map<string, AdminPredictionRow>()
  for (const r of rows) {
    let p = byPrediction.get(r.predictionId)
    if (!p) {
      p = {
        predictionId: r.predictionId,
        userId: r.userId,
        displayName: r.displayName,
        sessionId: r.sessionId,
        source: r.source,
        updatedAt: r.updatedAt,
        picks: []
      }
      byPrediction.set(r.predictionId, p)
    }
    if (r.position !== null && r.driverCode !== null) {
      p.picks.push({ position: r.position, driverCode: r.driverCode })
    }
  }
  for (const p of byPrediction.values()) p.picks.sort((a, b) => a.position - b.position)
  return Array.from(byPrediction.values())
}
```

> `prediction.source` exists on the table (`'app' | 'import'`). If the Drizzle column is named differently, adjust the select key.

- [ ] **Step 4: Add the route**

In `backend/src/api/routes/adminReads.ts`, add the import:
```ts
import * as predictionsRepo from '../../repo/predictions.js'
```
and inside `registerAdminReadRoutes`, append:
```ts
  app.get<{ Querystring: { sessionId?: string; userId?: string; leagueId?: string } }>(
    '/admin/predictions',
    async (req) => {
      const { sessionId, userId, leagueId } = req.query
      if (!sessionId && !userId && !leagueId) {
        throw new ApiError('BAD_REQUEST', 'provide at least one of sessionId, userId, leagueId')
      }
      const predictions = await predictionsRepo.listForAdmin({
        sessionId: sessionId ? Number(sessionId) : undefined,
        userId: userId || undefined,
        leagueId: leagueId || undefined
      })
      return { predictions }
    }
  )
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd backend && set -a && source .env && set +a && npx vitest run test/integration/api_admin_reads.test.ts`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add backend/src/repo/predictions.ts backend/src/api/routes/adminReads.ts \
  backend/test/integration/api_admin_reads.test.ts
git commit -m "feat(admin): GET /admin/predictions with session/user/league filters"
```

---

### Task 5: `GET /admin/crawl/status`

**Files:**
- Modify: `backend/src/api/routes/adminReads.ts`
- Modify: `backend/src/index.ts` (pass scheduler into the read routes)
- Modify: `backend/test/integration/api_admin_reads.test.ts`

**Interfaces:**
- Consumes: `sessionsRepo.listCandidates()` (existing), `sessionsRepo.listAllWithFetchMeta()` (Task 3), `Scheduler.status()` (existing, returns `{ lastTickAt: Date | null; lastTickStatus: 'ok' | 'error' | null }`).
- Produces:
  - `registerAdminReadRoutes(app, deps: { scheduler: Scheduler | null })` — **signature changes** to accept the scheduler.
  - Route: `GET /admin/crawl/status` → `{ lastTickAt, lastTickStatus, pendingCandidates: { id, type }[], provisionalSessions: { id, eventName, type }[] }`.

- [ ] **Step 1: Write the failing test**

Append to `backend/test/integration/api_admin_reads.test.ts`:

```ts
describe('GET /admin/crawl/status', () => {
  it('reports tick status, pending candidates and provisional sessions', async () => {
    await seasons.upsertSeason({ year: 2026, isCurrent: true })
    const ev = await events.upsertEvent({ seasonYear: 2026, round: 1, name: 'GP', circuitName: 'C', country: 'X', hasSprint: false })
    // A finished session with an openf1-sourced result => provisional.
    const fin = await sessions.upsertSession({ eventId: ev.id, type: 'race', scheduledStart: new Date('2026-03-01T14:00:00Z'), scheduledEnd: new Date('2026-03-01T16:00:00Z'), status: 'finished', openf1SessionKey: 7 })
    await constructors.upsertConstructor({ id: 'red_bull', name: 'Red Bull', nationality: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, teamColour: null })
    await drivers.upsertDriver({ code: 'VER', givenName: 'M', familyName: 'V', nationality: null, permanentNumber: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, headshotUrl: null })
    await results.replaceForSession(fin.id, [{
      sessionId: fin.id, position: 1, driverCode: 'VER', driverName: 'Max Verstappen',
      constructorId: 'red_bull', constructorName: 'Red Bull', raceTime: null, status: 'Finished',
      points: 25, fastestLap: null, fastestLapTime: null, fastestLapSpeed: null, q1: null, q2: null, q3: null, source: 'openf1'
    }])

    const app = await buildApp({ scheduler: null })
    const res = await app.inject({ method: 'GET', url: '/admin/crawl/status', headers: TOKEN })
    expect(res.statusCode).toBe(200)
    const body = res.json()
    expect(body.lastTickAt).toBeNull()
    expect(Array.isArray(body.pendingCandidates)).toBe(true)
    expect(body.provisionalSessions.map((s: any) => s.id)).toContain(fin.id)
    await app.close()
  })
})
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd backend && set -a && source .env && set +a && npx vitest run test/integration/api_admin_reads.test.ts -t "crawl/status"`
Expected: FAIL — no `/admin/crawl/status` route.

- [ ] **Step 3: Change the route module signature and add the route**

Replace the top of `backend/src/api/routes/adminReads.ts`'s function signature and add imports. The new function signature:

```ts
import type { FastifyInstance } from 'fastify'
import type { Scheduler } from '../../crawler/scheduler.js'
import { ApiError } from '../errors.js'
import * as leaguesRepo from '../../repo/leagues.js'
import * as leagueMembersRepo from '../../repo/leagueMembers.js'
import * as usersRepo from '../../repo/users.js'
import * as sessionsRepo from '../../repo/sessions.js'
import * as predictionsRepo from '../../repo/predictions.js'

export async function registerAdminReadRoutes(
  app: FastifyInstance,
  deps: { scheduler: Scheduler | null }
): Promise<void> {
```

Then append the new route inside the function:
```ts
  app.get('/admin/crawl/status', async () => {
    const sched = deps.scheduler?.status() ?? { lastTickAt: null, lastTickStatus: null }
    const candidates = await sessionsRepo.listCandidates()
    const all = await sessionsRepo.listAllWithFetchMeta()
    return {
      lastTickAt: sched.lastTickAt,
      lastTickStatus: sched.lastTickStatus,
      pendingCandidates: candidates.map((c) => ({ id: c.id, type: c.type })),
      provisionalSessions: all
        .filter((s) => s.provisional)
        .map((s) => ({ id: s.id, eventName: s.eventName, type: s.type }))
    }
  })
```

- [ ] **Step 4: Update the call site in `index.ts`**

Change `backend/src/index.ts`'s call from:
```ts
  await registerAdminReadRoutes(app)
```
to:
```ts
  await registerAdminReadRoutes(app, { scheduler: opts.scheduler })
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd backend && set -a && source .env && set +a && npx vitest run test/integration/api_admin_reads.test.ts`
Expected: PASS (whole file).

- [ ] **Step 6: Run the full backend suite (no regressions)**

Run: `make backend-test`
Expected: all tests pass (existing + new `api_admin_reads`).

- [ ] **Step 7: Commit**

```bash
git add backend/src/api/routes/adminReads.ts backend/src/index.ts \
  backend/test/integration/api_admin_reads.test.ts
git commit -m "feat(admin): GET /admin/crawl/status"
```

---

## Self-Review

**Spec coverage (read layer, spec §4.1):**
- `/admin/leagues` + `/admin/leagues/:id` → Task 1 ✓
- `/admin/users` + `/admin/users/:id` → Task 2 ✓
- `/admin/sessions` (fetch health: status, source/provisional, lastReconciledAt) → Task 3 ✓
- `/admin/predictions` (sessionId/userId/leagueId filters) → Task 4 ✓
- `/admin/crawl/status` (expands `/api/health`) → Task 5 ✓
- Token gate covered by the first test in Task 1 (401 without token) ✓

**Type consistency:** `AdminLeagueRow`, `AdminMemberRow`, `AdminUserRow`, `AdminUserDetail`, `AdminSessionRow`, `AdminPredictionRow` are each defined once in their repo and consumed by exactly one route. `registerAdminReadRoutes` gains its `deps` param in Task 5; the `index.ts` call site is updated in the same task.

**Open verification flags for the implementer:**
- Task 3 / Task 5 use `results.replaceForSession(...)` with an inline row shape mirroring `session_result`. Before running, open `backend/src/repo/results.ts` and match the exact input type (field names/nullability). This is the one spot the plan asserts a shape it didn't read.
- Confirm `prediction.source` is the Drizzle column name in `schema.ts` (Task 4 select).

## Next plans in this sequence

This is plan 1 of the admin-tool series (spec: `docs/superpowers/specs/2026-06-28-admin-tool-design.md`, build order §9):

2. **Admin app scaffold** — Vite + React + TS + Radix, ported theme tokens, `AppShell`, `TokenGate`, API client, TanStack Query.
3. **Fetch dashboard** — crawl-status view + trigger buttons over existing admin routes.
4. **Session result editing** — backend `PATCH/POST/DELETE /admin/sessions/:id/results...` + `SessionDetail` inline grid.
5. **Leagues admin** — backend cross-user league write routes + `Leagues`/`LeagueDetail`.
6. **Season management + remaining pages** — `Seasons`, drivers/constructors edit, users, predictions, standings, notifications.
