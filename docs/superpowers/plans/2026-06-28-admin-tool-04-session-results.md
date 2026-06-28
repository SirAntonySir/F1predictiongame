# Admin Tool — Plan 4: Session Result Editing

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let an admin correct fetched results: new validated `X-Admin-Token` write endpoints to edit / add / delete a `session_result` row (auto-rescoring the session), and a `SessionDetail` admin page with a Sessions list, a results grid, inline edit/add/delete, and per-session Re-fetch / Re-score buttons.

**Architecture:** Backend additions (Fastify + Drizzle): single-row result repo helpers + a token-gated `adminSessionResults` route module (`PATCH/POST/DELETE /admin/sessions/:id/results...`) that validates FKs + position, then calls the existing `rescoreSession`. Frontend additions (admin SPA): a Sessions list page and a SessionDetail page that reads via the existing public `/api/sessions/:id` + `/api/sessions/:id/results`, edits via the new admin writes, and reuses `ActionButton` for refetch/rescore.

**Tech Stack:** Backend — Fastify 5, Drizzle, Zod, Vitest (integration, real Postgres). Frontend — React 18, TypeScript, Radix Themes, TanStack Query v5, Vitest + RTL + jsdom.

## Global Constraints

- **Concurrency:** another session actively edits `backend/`/`lib/` and pushes `main`. Execute in an isolated worktree. NEVER `git add -A`/`git add .`/`git commit -a`. Stage only the exact paths each task names.
- Backend (`backend/`): Node ≥22, TS ESM — all relative imports use the `.js` extension. Errors via `new ApiError(code, msg)` from `errors.js`. Repo layer only (no raw SQL in handlers). New admin routes register on the root `app` (plain function call, after `registerAdminReadRoutes`) so the existing `/admin/*` token preHandler gates them. Integration tests in `backend/test/integration/`, admin token literal `'local-dev-token'`, `buildApp({ scheduler: null })` + `app.inject`, harness truncates `beforeEach`, seed via repo functions. Backend tests run with the Postgres container up (`make db-up`). No new backend deps.
- Frontend (`admin/`): TS strict, build gate `npm run build`, tests `npm test`, no new npm deps. Keep `className="display"`/`className="label"` typography. Reuse the existing client (`apiFetch`/`ApiError`), `useToast`, `ActionButton`, `useAdminAction`.
- `session_result` schema: composite PK `(sessionId, position)`; NOT NULL: `driverCode` (FK→driver.code), `driverName`, `constructorId` (FK→constructor.id), `constructorName`, `position`; nullable: `raceTime`, `status`, `points`, `fastestLap*`, `q1`, `q2`, `q3`; `source` defaults `'jolpica'`. **PATCH does not change `position`** (it is row identity — move a row by editing its `driverCode`, or delete+add).
- `SessionResultRow` (backend `domain/types.ts`) fields: `sessionId, position, driverCode, driverName, constructorId, constructorName, raceTime, status, points, fastestLap, fastestLapTime, fastestLapSpeed, q1, q2, q3`.
- Every result write auto-rescores via `rescoreSession(sessionId)` (returns `{ users, totalPoints }`).

## File Structure

Backend:
- Modify `backend/src/repo/results.ts` — add `getResult`, `updateResultFields`, `insertResult`, `deleteResult`.
- Create `backend/src/api/routes/adminSessionResults.ts` — `registerAdminSessionResultRoutes(app, deps)`.
- Modify `backend/src/index.ts` — register the module.
- Create `backend/test/integration/repo_results_singlerow.test.ts`, `backend/test/integration/api_admin_session_results.test.ts`.

Frontend:
- Modify `admin/src/api/types.ts` — add `AdminSessionRow`, `SessionResultRow`, `SessionMeta`.
- Create `admin/src/api/sessions.ts` — `useAdminSessions`, `useSession`, `useSessionResults`, plus result mutations.
- Create `admin/src/pages/Sessions.tsx`, `admin/src/pages/SessionDetail.tsx`, `admin/src/components/ResultEditDialog.tsx`.
- Modify `admin/src/router.tsx` — `/sessions` → Sessions, `/sessions/:id` → SessionDetail.
- Create `admin/src/test/Sessions.test.tsx`, `admin/src/test/SessionDetail.test.tsx`, `admin/src/test/ResultEditDialog.test.tsx`.

---

### Task 1: Single-row result repo helpers (backend)

**Files:**
- Modify: `backend/src/repo/results.ts`
- Create: `backend/test/integration/repo_results_singlerow.test.ts`

**Interfaces:**
- Produces (in `results.ts`):
  - `getResult(sessionId: number, position: number): Promise<SessionResultRow | null>`
  - `updateResultFields(sessionId: number, position: number, fields: Partial<Omit<SessionResultRow, 'sessionId' | 'position'>>): Promise<SessionResultRow>` (throws `Error` if the row is missing)
  - `insertResult(row: SessionResultRow): Promise<SessionResultRow>`
  - `deleteResult(sessionId: number, position: number): Promise<void>`

- [ ] **Step 1: Write the failing test**

`backend/test/integration/repo_results_singlerow.test.ts`:
```ts
import { describe, it, expect, beforeEach } from 'vitest'
import * as seasons from '../../src/repo/seasons.js'
import * as events from '../../src/repo/events.js'
import * as sessions from '../../src/repo/sessions.js'
import * as drivers from '../../src/repo/drivers.js'
import * as constructors from '../../src/repo/constructors.js'
import * as results from '../../src/repo/results.js'

async function seed() {
  await seasons.upsertSeason({ year: 2026, isCurrent: true })
  const ev = await events.upsertEvent({ seasonYear: 2026, round: 1, name: 'GP', circuitName: 'C', country: 'X', hasSprint: false })
  const ses = await sessions.upsertSession({ eventId: ev.id, type: 'race', scheduledStart: new Date('2026-03-01T14:00:00Z'), scheduledEnd: new Date('2026-03-01T16:00:00Z'), status: 'finished', openf1SessionKey: null })
  await constructors.upsertConstructor({ id: 'red_bull', name: 'Red Bull', nationality: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, teamColour: null })
  await constructors.upsertConstructor({ id: 'ferrari', name: 'Ferrari', nationality: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, teamColour: null })
  await drivers.upsertDriver({ code: 'VER', givenName: 'M', familyName: 'V', nationality: null, permanentNumber: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, headshotUrl: null })
  await drivers.upsertDriver({ code: 'LEC', givenName: 'C', familyName: 'L', nationality: null, permanentNumber: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, headshotUrl: null })
  return ses.id
}

function row(sessionId: number, position: number, driverCode: string, driverName: string, constructorId: string, constructorName: string) {
  return { sessionId, position, driverCode, driverName, constructorId, constructorName, raceTime: null, status: 'Finished', points: null, fastestLap: null, fastestLapTime: null, fastestLapSpeed: null, q1: null, q2: null, q3: null }
}

describe('single-row result helpers', () => {
  let sid: number
  beforeEach(async () => { sid = await seed() })

  it('inserts, gets, updates and deletes a row', async () => {
    await results.insertResult(row(sid, 1, 'VER', 'Max Verstappen', 'red_bull', 'Red Bull'))
    const got = await results.getResult(sid, 1)
    expect(got?.driverCode).toBe('VER')

    const updated = await results.updateResultFields(sid, 1, { points: 25, status: 'Finished' })
    expect(updated.points).toBe(25)

    await results.deleteResult(sid, 1)
    expect(await results.getResult(sid, 1)).toBeNull()
  })

  it('updateResultFields throws when the row is missing', async () => {
    await expect(results.updateResultFields(sid, 99, { points: 1 })).rejects.toThrow()
  })
})
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd backend && set -a && source .env && set +a && npx vitest run test/integration/repo_results_singlerow.test.ts`
Expected: FAIL — the new helpers are undefined.

- [ ] **Step 3: Implement the helpers**

Append to `backend/src/repo/results.ts` (it imports `eq, asc, sql` from `drizzle-orm`, `sessionResult` from schema, `SessionResultRow` type; add `and` to the drizzle import — change the first import line to `import { eq, and, asc, sql } from 'drizzle-orm'`):

```ts
export async function getResult(sessionId: number, position: number): Promise<SessionResultRow | null> {
  const db = getDb()
  const rows = await db.select().from(sessionResult)
    .where(and(eq(sessionResult.sessionId, sessionId), eq(sessionResult.position, position)))
    .limit(1)
  return (rows[0] as SessionResultRow) ?? null
}

export async function updateResultFields(
  sessionId: number,
  position: number,
  fields: Partial<Omit<SessionResultRow, 'sessionId' | 'position'>>
): Promise<SessionResultRow> {
  const db = getDb()
  const [updated] = await db.update(sessionResult)
    .set(fields)
    .where(and(eq(sessionResult.sessionId, sessionId), eq(sessionResult.position, position)))
    .returning()
  if (!updated) throw new Error(`result not found: session ${sessionId} position ${position}`)
  return updated as SessionResultRow
}

export async function insertResult(row: SessionResultRow): Promise<SessionResultRow> {
  const db = getDb()
  const [inserted] = await db.insert(sessionResult).values(row).returning()
  return inserted as SessionResultRow
}

export async function deleteResult(sessionId: number, position: number): Promise<void> {
  const db = getDb()
  await db.delete(sessionResult)
    .where(and(eq(sessionResult.sessionId, sessionId), eq(sessionResult.position, position)))
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd backend && set -a && source .env && set +a && npx vitest run test/integration/repo_results_singlerow.test.ts`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add backend/src/repo/results.ts backend/test/integration/repo_results_singlerow.test.ts
git commit -m "feat(admin): single-row session_result repo helpers"
```

---

### Task 2: Admin result write endpoints (backend)

**Files:**
- Create: `backend/src/api/routes/adminSessionResults.ts`
- Modify: `backend/src/index.ts`
- Create: `backend/test/integration/api_admin_session_results.test.ts`

**Interfaces:**
- Consumes: `resultsRepo` (Task 1 + existing), `sessionsRepo.getById`, `driversRepo.exists`, `constructorsRepo.exists`, `rescoreSession`, `ApiError`.
- Produces:
  - `registerAdminSessionResultRoutes(app: FastifyInstance): Promise<void>`
  - `PATCH /admin/sessions/:id/results/:position` — body = partial of `{ driverCode, driverName, constructorId, constructorName, points, status, raceTime, q1, q2, q3 }`. Validates the session + row exist; if `driverCode`/`constructorId` present, validates they exist (else `VALIDATION`). Updates, rescores. Returns `{ ok: true, result, rescored }`.
  - `POST /admin/sessions/:id/results` — body = `{ position, driverCode, driverName, constructorId, constructorName, points?, status?, raceTime?, q1?, q2?, q3? }`. Validates session exists, FKs exist, position free (else `CONFLICT`). Inserts (`source: 'jolpica'`), rescores. Returns `{ ok: true, result, rescored }`.
  - `DELETE /admin/sessions/:id/results/:position` — validates the row exists; deletes, rescores. Returns `{ ok: true, rescored }`.

- [ ] **Step 1: Write the failing test**

`backend/test/integration/api_admin_session_results.test.ts`:
```ts
import { describe, it, expect, beforeEach } from 'vitest'
import { buildApp } from '../../src/index.js'
import * as seasons from '../../src/repo/seasons.js'
import * as events from '../../src/repo/events.js'
import * as sessions from '../../src/repo/sessions.js'
import * as drivers from '../../src/repo/drivers.js'
import * as constructors from '../../src/repo/constructors.js'
import * as results from '../../src/repo/results.js'

const TOKEN = { 'x-admin-token': 'local-dev-token' }

async function seed() {
  await seasons.upsertSeason({ year: 2026, isCurrent: true })
  const ev = await events.upsertEvent({ seasonYear: 2026, round: 1, name: 'GP', circuitName: 'C', country: 'X', hasSprint: false })
  const ses = await sessions.upsertSession({ eventId: ev.id, type: 'race', scheduledStart: new Date('2026-03-01T14:00:00Z'), scheduledEnd: new Date('2026-03-01T16:00:00Z'), status: 'finished', openf1SessionKey: null })
  for (const c of [['red_bull', 'Red Bull'], ['ferrari', 'Ferrari']]) {
    await constructors.upsertConstructor({ id: c[0], name: c[1], nationality: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, teamColour: null })
  }
  for (const d of ['VER', 'LEC']) {
    await drivers.upsertDriver({ code: d, givenName: d, familyName: d, nationality: null, permanentNumber: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, headshotUrl: null })
  }
  await results.insertResult({ sessionId: ses.id, position: 1, driverCode: 'VER', driverName: 'Max Verstappen', constructorId: 'red_bull', constructorName: 'Red Bull', raceTime: null, status: 'Finished', points: 25, fastestLap: null, fastestLapTime: null, fastestLapSpeed: null, q1: null, q2: null, q3: null })
  return ses.id
}

describe('admin session result writes', () => {
  let sid: number
  beforeEach(async () => { sid = await seed() })

  it('requires the admin token', async () => {
    const app = await buildApp({ scheduler: null })
    const r = await app.inject({ method: 'PATCH', url: `/admin/sessions/${sid}/results/1`, payload: { points: 18 } })
    expect(r.statusCode).toBe(401)
    await app.close()
  })

  it('PATCH edits a row and rescores', async () => {
    const app = await buildApp({ scheduler: null })
    const r = await app.inject({ method: 'PATCH', url: `/admin/sessions/${sid}/results/1`, headers: TOKEN, payload: { points: 18, status: 'Penalty' } })
    expect(r.statusCode).toBe(200)
    expect(r.json().result.points).toBe(18)
    expect(r.json().result.status).toBe('Penalty')
    expect(r.json().rescored).toBeDefined()
    const got = await results.getResult(sid, 1)
    expect(got?.points).toBe(18)
    await app.close()
  })

  it('PATCH rejects an unknown driver code', async () => {
    const app = await buildApp({ scheduler: null })
    const r = await app.inject({ method: 'PATCH', url: `/admin/sessions/${sid}/results/1`, headers: TOKEN, payload: { driverCode: 'NOPE' } })
    expect(r.statusCode).toBe(422)
    await app.close()
  })

  it('PATCH 404s a missing row', async () => {
    const app = await buildApp({ scheduler: null })
    const r = await app.inject({ method: 'PATCH', url: `/admin/sessions/${sid}/results/9`, headers: TOKEN, payload: { points: 1 } })
    expect(r.statusCode).toBe(404)
    await app.close()
  })

  it('POST adds a row, DELETE removes it', async () => {
    const app = await buildApp({ scheduler: null })
    const add = await app.inject({ method: 'POST', url: `/admin/sessions/${sid}/results`, headers: TOKEN, payload: { position: 2, driverCode: 'LEC', driverName: 'Charles Leclerc', constructorId: 'ferrari', constructorName: 'Ferrari', points: 18 } })
    expect(add.statusCode).toBe(200)
    expect(await results.getResult(sid, 2)).not.toBeNull()

    const dup = await app.inject({ method: 'POST', url: `/admin/sessions/${sid}/results`, headers: TOKEN, payload: { position: 2, driverCode: 'LEC', driverName: 'X', constructorId: 'ferrari', constructorName: 'Ferrari' } })
    expect(dup.statusCode).toBe(409)

    const del = await app.inject({ method: 'DELETE', url: `/admin/sessions/${sid}/results/2`, headers: TOKEN })
    expect(del.statusCode).toBe(200)
    expect(await results.getResult(sid, 2)).toBeNull()
    await app.close()
  })
})
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd backend && set -a && source .env && set +a && npx vitest run test/integration/api_admin_session_results.test.ts`
Expected: FAIL — routes return 404 (not registered).

- [ ] **Step 3: Create `backend/src/api/routes/adminSessionResults.ts`**

```ts
import type { FastifyInstance } from 'fastify'
import { z } from 'zod'
import { ApiError } from '../errors.js'
import * as resultsRepo from '../../repo/results.js'
import * as sessionsRepo from '../../repo/sessions.js'
import * as driversRepo from '../../repo/drivers.js'
import * as constructorsRepo from '../../repo/constructors.js'
import { rescoreSession } from '../../scoring/rescorer.js'

const patchBody = z.object({
  driverCode: z.string().min(1).max(10).optional(),
  driverName: z.string().min(1).optional(),
  constructorId: z.string().min(1).max(50).optional(),
  constructorName: z.string().min(1).optional(),
  points: z.number().int().nullable().optional(),
  status: z.string().nullable().optional(),
  raceTime: z.string().nullable().optional(),
  q1: z.string().nullable().optional(),
  q2: z.string().nullable().optional(),
  q3: z.string().nullable().optional()
})

const postBody = patchBody.extend({
  position: z.number().int().min(1).max(40),
  driverCode: z.string().min(1).max(10),
  driverName: z.string().min(1),
  constructorId: z.string().min(1).max(50),
  constructorName: z.string().min(1)
})

async function assertFks(driverCode?: string, constructorId?: string): Promise<void> {
  if (driverCode !== undefined && !(await driversRepo.exists(driverCode))) {
    throw new ApiError('VALIDATION', `Driver ${driverCode} does not exist`)
  }
  if (constructorId !== undefined && !(await constructorsRepo.exists(constructorId))) {
    throw new ApiError('VALIDATION', `Constructor ${constructorId} does not exist`)
  }
}

export async function registerAdminSessionResultRoutes(app: FastifyInstance): Promise<void> {
  app.patch<{ Params: { id: string; position: string } }>(
    '/admin/sessions/:id/results/:position',
    async (req) => {
      const id = Number(req.params.id)
      const position = Number(req.params.position)
      if (!Number.isFinite(id) || !Number.isFinite(position)) throw new ApiError('BAD_REQUEST', 'id/position must be numbers')
      const parsed = patchBody.safeParse(req.body)
      if (!parsed.success) throw new ApiError('VALIDATION', parsed.error.issues[0]?.message ?? 'Invalid body')

      if (!(await sessionsRepo.getById(id))) throw new ApiError('NOT_FOUND', `Session ${id} not found`)
      if (!(await resultsRepo.getResult(id, position))) throw new ApiError('NOT_FOUND', `Result at position ${position} not found`)
      await assertFks(parsed.data.driverCode, parsed.data.constructorId)

      const result = await resultsRepo.updateResultFields(id, position, parsed.data)
      const rescored = await rescoreSession(id)
      return { ok: true, result, rescored }
    }
  )

  app.post<{ Params: { id: string } }>('/admin/sessions/:id/results', async (req) => {
    const id = Number(req.params.id)
    if (!Number.isFinite(id)) throw new ApiError('BAD_REQUEST', 'id must be a number')
    const parsed = postBody.safeParse(req.body)
    if (!parsed.success) throw new ApiError('VALIDATION', parsed.error.issues[0]?.message ?? 'Invalid body')

    if (!(await sessionsRepo.getById(id))) throw new ApiError('NOT_FOUND', `Session ${id} not found`)
    if (await resultsRepo.getResult(id, parsed.data.position)) throw new ApiError('CONFLICT', `Position ${parsed.data.position} already exists`)
    await assertFks(parsed.data.driverCode, parsed.data.constructorId)

    const result = await resultsRepo.insertResult({
      sessionId: id,
      position: parsed.data.position,
      driverCode: parsed.data.driverCode,
      driverName: parsed.data.driverName,
      constructorId: parsed.data.constructorId,
      constructorName: parsed.data.constructorName,
      raceTime: parsed.data.raceTime ?? null,
      status: parsed.data.status ?? null,
      points: parsed.data.points ?? null,
      fastestLap: null,
      fastestLapTime: null,
      fastestLapSpeed: null,
      q1: parsed.data.q1 ?? null,
      q2: parsed.data.q2 ?? null,
      q3: parsed.data.q3 ?? null
    })
    const rescored = await rescoreSession(id)
    return { ok: true, result, rescored }
  })

  app.delete<{ Params: { id: string; position: string } }>(
    '/admin/sessions/:id/results/:position',
    async (req) => {
      const id = Number(req.params.id)
      const position = Number(req.params.position)
      if (!Number.isFinite(id) || !Number.isFinite(position)) throw new ApiError('BAD_REQUEST', 'id/position must be numbers')
      if (!(await resultsRepo.getResult(id, position))) throw new ApiError('NOT_FOUND', `Result at position ${position} not found`)
      await resultsRepo.deleteResult(id, position)
      const rescored = await rescoreSession(id)
      return { ok: true, rescored }
    }
  )
}
```

- [ ] **Step 4: Register in `backend/src/index.ts`**

Add the import after the `registerAdminReadRoutes` import:
```ts
import { registerAdminSessionResultRoutes } from './api/routes/adminSessionResults.js'
```
Add the call immediately after the `await registerAdminReadRoutes(app, { scheduler: opts.scheduler })` line:
```ts
  await registerAdminSessionResultRoutes(app)
```

- [ ] **Step 5: Run to verify it passes**

Run: `cd backend && set -a && source .env && set +a && npx vitest run test/integration/api_admin_session_results.test.ts`
Expected: PASS (5 tests).

- [ ] **Step 6: Full backend suite (no regressions)**

Run: `cd backend && set -a && source .env && set +a && npm test`
Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git add backend/src/api/routes/adminSessionResults.ts backend/src/index.ts backend/test/integration/api_admin_session_results.test.ts
git commit -m "feat(admin): PATCH/POST/DELETE session result endpoints with rescore"
```

---

### Task 3: Sessions list page (frontend)

**Files:**
- Modify: `admin/src/api/types.ts`
- Create: `admin/src/api/sessions.ts`, `admin/src/pages/Sessions.tsx`, `admin/src/test/Sessions.test.tsx`
- Modify: `admin/src/router.tsx`

**Interfaces:**
- Produces:
  - `types.ts`: `AdminSessionRow` (`{ id, seasonYear, round, eventName, type, status, scheduledStart, lastReconciledAt, resultCount, provisional }`), `SessionResultRow` (`{ position, driverCode, driverName, constructorId, constructorName, points, status, raceTime, q1, q2, q3 }`), `SessionMeta` (`{ id, eventId, type, scheduledStart, scheduledEnd, status }`).
  - `sessions.ts`: `useAdminSessions(): UseQueryResult<AdminSessionRow[]>` (key `['admin-sessions']`, `apiFetch<{ sessions: AdminSessionRow[] }>('/admin/sessions')` → `.sessions`).
  - `Sessions.tsx`: `<Sessions/>` — a table of sessions, each row a `Link` to `/sessions/:id`, showing round, event, type, status, a provisional badge, and result count.
  - Router: `/sessions` renders `<Sessions/>`.

- [ ] **Step 1: Write the failing test**

`admin/src/test/Sessions.test.tsx`:
```tsx
import { describe, it, expect, afterEach, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { Sessions } from '../pages/Sessions'
import { setToken } from '../api/client'

afterEach(() => { localStorage.clear(); vi.restoreAllMocks() })

function wrap(ui: React.ReactNode) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return <QueryClientProvider client={qc}><MemoryRouter>{ui}</MemoryRouter></QueryClientProvider>
}

describe('Sessions', () => {
  it('lists sessions from /admin/sessions', async () => {
    setToken('tok')
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(new Response(JSON.stringify({
      sessions: [{ id: 5, seasonYear: 2026, round: 1, eventName: 'Bahrain GP', type: 'race', status: 'finished', scheduledStart: '2026-03-01T14:00:00Z', lastReconciledAt: null, resultCount: 20, provisional: true }]
    }), { status: 200 })))

    render(wrap(<Sessions />))
    expect(await screen.findByText('Bahrain GP')).toBeInTheDocument()
    const link = screen.getByRole('link', { name: /bahrain gp/i })
    expect(link).toHaveAttribute('href', '/sessions/5')
  })
})
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd admin && npx vitest run src/test/Sessions.test.tsx`
Expected: FAIL — `../pages/Sessions` does not exist.

- [ ] **Step 3: Add the types**

Append to `admin/src/api/types.ts`:
```ts
export type AdminSessionRow = {
  id: number
  seasonYear: number
  round: number
  eventName: string
  type: string
  status: 'scheduled' | 'finished'
  scheduledStart: string
  lastReconciledAt: string | null
  resultCount: number
  provisional: boolean
}

export type SessionResultRow = {
  position: number
  driverCode: string
  driverName: string
  constructorId: string
  constructorName: string
  points: number | null
  status: string | null
  raceTime: string | null
  q1: string | null
  q2: string | null
  q3: string | null
}

export type SessionMeta = {
  id: number
  eventId: number
  type: string
  scheduledStart: string
  scheduledEnd: string
  status: 'scheduled' | 'finished'
}
```

- [ ] **Step 4: Create `admin/src/api/sessions.ts`**

```ts
import { useQuery } from '@tanstack/react-query'
import { apiFetch } from './client'
import type { AdminSessionRow, SessionMeta, SessionResultRow } from './types'

export function useAdminSessions() {
  return useQuery({
    queryKey: ['admin-sessions'],
    queryFn: async () => (await apiFetch<{ sessions: AdminSessionRow[] }>('/admin/sessions')).sessions
  })
}

export function useSession(id: number) {
  return useQuery({
    queryKey: ['session', id],
    queryFn: () => apiFetch<SessionMeta>(`/api/sessions/${id}`)
  })
}

export function useSessionResults(id: number) {
  return useQuery({
    queryKey: ['session-results', id],
    queryFn: () => apiFetch<SessionResultRow[]>(`/api/sessions/${id}/results`)
  })
}
```

- [ ] **Step 5: Create `admin/src/pages/Sessions.tsx`**

```tsx
import { Link } from 'react-router-dom'
import { Badge, Flex, Heading, Table, Text } from '@radix-ui/themes'
import { useAdminSessions } from '../api/sessions'

export function Sessions() {
  const { data, isLoading, error } = useAdminSessions()
  return (
    <Flex direction="column" gap="4">
      <Heading size="6" className="display">Sessions</Heading>
      {isLoading && <Text size="2">Loading…</Text>}
      {error && <Text size="2" color="red">Failed to load sessions.</Text>}
      {data && (
        <Table.Root variant="surface">
          <Table.Header>
            <Table.Row>
              <Table.ColumnHeaderCell>Round</Table.ColumnHeaderCell>
              <Table.ColumnHeaderCell>Event</Table.ColumnHeaderCell>
              <Table.ColumnHeaderCell>Type</Table.ColumnHeaderCell>
              <Table.ColumnHeaderCell>Status</Table.ColumnHeaderCell>
              <Table.ColumnHeaderCell>Results</Table.ColumnHeaderCell>
            </Table.Row>
          </Table.Header>
          <Table.Body>
            {data.map((s) => (
              <Table.Row key={s.id}>
                <Table.Cell>{s.round}</Table.Cell>
                <Table.Cell><Link to={`/sessions/${s.id}`}>{s.eventName}</Link></Table.Cell>
                <Table.Cell>{s.type}</Table.Cell>
                <Table.Cell>
                  <Flex gap="1">
                    <Badge color={s.status === 'finished' ? 'gray' : 'blue'}>{s.status}</Badge>
                    {s.provisional && <Badge color="orange">provisional</Badge>}
                  </Flex>
                </Table.Cell>
                <Table.Cell>{s.resultCount}</Table.Cell>
              </Table.Row>
            ))}
          </Table.Body>
        </Table.Root>
      )}
    </Flex>
  )
}
```

- [ ] **Step 6: Wire the router**

In `admin/src/router.tsx`, add the import `import { Sessions } from './pages/Sessions'` and change the `{ path: 'sessions', element: <Placeholder title="Sessions" /> }` entry to `{ path: 'sessions', element: <Sessions /> }`.

- [ ] **Step 7: Run the test + build**

Run: `cd admin && npx vitest run src/test/Sessions.test.tsx`
Expected: PASS. Then `cd admin && npm run build` → clean.

- [ ] **Step 8: Commit**

```bash
git add admin/src/api/types.ts admin/src/api/sessions.ts admin/src/pages/Sessions.tsx admin/src/test/Sessions.test.tsx admin/src/router.tsx
git commit -m "feat(admin-ui): sessions list page"
```

---

### Task 4: SessionDetail page — results grid + refetch/rescore (frontend)

**Files:**
- Create: `admin/src/pages/SessionDetail.tsx`, `admin/src/test/SessionDetail.test.tsx`
- Modify: `admin/src/router.tsx`

**Interfaces:**
- Consumes: `useSession`, `useSessionResults` (Task 3), `ActionButton`.
- Produces:
  - `<SessionDetail/>` — reads the `:id` route param, shows session meta, a results table (POS / DRIVER / CONSTRUCTOR / PTS / STATUS), and two `ActionButton`s: **Re-fetch** (`POST /admin/refetch-session/:id`, `invalidateKeys={[['session-results', id]]}`) and **Re-score** (`POST /admin/rescore-session/:id`).
  - Router: `/sessions/:id` renders `<SessionDetail/>`.

- [ ] **Step 1: Write the failing test**

`admin/src/test/SessionDetail.test.tsx`:
```tsx
import { describe, it, expect, afterEach, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import { MemoryRouter, Routes, Route } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { ToastProvider } from '../ui/toast'
import { SessionDetail } from '../pages/SessionDetail'
import { setToken } from '../api/client'

afterEach(() => { localStorage.clear(); vi.restoreAllMocks() })

function mockFetch() {
  return vi.fn((url: string) => {
    if (String(url).endsWith('/api/sessions/5')) {
      return Promise.resolve(new Response(JSON.stringify({ id: 5, eventId: 1, type: 'race', scheduledStart: '2026-03-01T14:00:00Z', scheduledEnd: '2026-03-01T16:00:00Z', status: 'finished' }), { status: 200 }))
    }
    if (String(url).endsWith('/api/sessions/5/results')) {
      return Promise.resolve(new Response(JSON.stringify([
        { position: 1, driverCode: 'VER', driverName: 'Max Verstappen', constructorId: 'red_bull', constructorName: 'Red Bull', points: 25, status: 'Finished', raceTime: null, q1: null, q2: null, q3: null }
      ]), { status: 200 }))
    }
    return Promise.resolve(new Response('{}', { status: 200 }))
  })
}

function wrap() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return (
    <QueryClientProvider client={qc}>
      <ToastProvider>
        <MemoryRouter initialEntries={['/sessions/5']}>
          <Routes><Route path="/sessions/:id" element={<SessionDetail />} /></Routes>
        </MemoryRouter>
      </ToastProvider>
    </QueryClientProvider>
  )
}

describe('SessionDetail', () => {
  it('shows the results grid and refetch/rescore buttons', async () => {
    setToken('tok')
    vi.stubGlobal('fetch', mockFetch())
    render(wrap())
    expect(await screen.findByText('Max Verstappen')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /re-fetch/i })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /re-score/i })).toBeInTheDocument()
  })
})
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd admin && npx vitest run src/test/SessionDetail.test.tsx`
Expected: FAIL — `../pages/SessionDetail` does not exist.

- [ ] **Step 3: Create `admin/src/pages/SessionDetail.tsx`**

```tsx
import { useParams } from 'react-router-dom'
import { Flex, Heading, Table, Text } from '@radix-ui/themes'
import { useSession, useSessionResults } from '../api/sessions'
import { ActionButton } from '../components/ActionButton'

export function SessionDetail() {
  const { id: idParam } = useParams()
  const id = Number(idParam)
  const session = useSession(id)
  const results = useSessionResults(id)
  const resultsKey: string[][] = [['session-results', String(id)]]

  return (
    <Flex direction="column" gap="4">
      <Heading size="6" className="display">Session #{id}</Heading>
      {session.data && (
        <Text size="2" className="label">{session.data.type} · {session.data.status}</Text>
      )}
      <Flex gap="2">
        <ActionButton label="Re-fetch" path={`/admin/refetch-session/${id}`} successMessage="Session re-fetched" invalidateKeys={resultsKey} />
        <ActionButton label="Re-score" path={`/admin/rescore-session/${id}`} successMessage="Session re-scored" />
      </Flex>
      {results.isLoading && <Text size="2">Loading results…</Text>}
      {results.error && <Text size="2" color="red">Failed to load results.</Text>}
      {results.data && (
        <Table.Root variant="surface">
          <Table.Header>
            <Table.Row>
              <Table.ColumnHeaderCell>Pos</Table.ColumnHeaderCell>
              <Table.ColumnHeaderCell>Driver</Table.ColumnHeaderCell>
              <Table.ColumnHeaderCell>Constructor</Table.ColumnHeaderCell>
              <Table.ColumnHeaderCell>Pts</Table.ColumnHeaderCell>
              <Table.ColumnHeaderCell>Status</Table.ColumnHeaderCell>
            </Table.Row>
          </Table.Header>
          <Table.Body>
            {results.data.map((r) => (
              <Table.Row key={r.position}>
                <Table.Cell>{r.position}</Table.Cell>
                <Table.Cell>{r.driverName} <Text size="1" color="gray">{r.driverCode}</Text></Table.Cell>
                <Table.Cell>{r.constructorName}</Table.Cell>
                <Table.Cell>{r.points ?? '—'}</Table.Cell>
                <Table.Cell>{r.status ?? '—'}</Table.Cell>
              </Table.Row>
            ))}
          </Table.Body>
        </Table.Root>
      )}
    </Flex>
  )
}
```

> Note: `resultsKey` uses `String(id)` so the key matches what Task 5's mutations invalidate; the `useSessionResults` query key in Task 3 is `['session-results', id]` (numeric). To keep them identical, **use the numeric `id`** in `resultsKey`: `const resultsKey: string[][] = [['session-results', String(id)]]` is WRONG for matching a numeric key — instead write the invalidate keys with the numeric id. Implement `ActionButton`'s `invalidateKeys` as `[['session-results', id]]` is not assignable to `string[][]`; therefore broaden the ActionButton/useAdminAction `invalidateKeys` type to `unknown[][]` in Task 5, OR pass the key as `['session-results', String(id)]` AND make Task 3's query key `['session-results', String(id)]` too. **Decision for this plan:** change Task 3's `useSessionResults` key to `['session-results', String(id)]` and use `String(id)` everywhere. The implementer of Task 4 must confirm Task 3 used `String(id)`; if Task 3 used numeric `id`, update it to `String(id)` here and note it.

- [ ] **Step 4: Wire the router**

In `admin/src/router.tsx`, add `import { SessionDetail } from './pages/SessionDetail'` and add a child route `{ path: 'sessions/:id', element: <SessionDetail /> }` after the `sessions` route entry.

- [ ] **Step 5: Run the test + build**

Run: `cd admin && npx vitest run src/test/SessionDetail.test.tsx`
Expected: PASS. Then `cd admin && npm run build` → clean.

- [ ] **Step 6: Commit**

```bash
git add admin/src/pages/SessionDetail.tsx admin/src/test/SessionDetail.test.tsx admin/src/router.tsx
git commit -m "feat(admin-ui): session detail page with results grid + refetch/rescore"
```

> **Consistency note for Task 3↔4↔5:** the `session-results` query key MUST be identical in `useSessionResults` (Task 3) and in every `invalidateKeys` (Tasks 4–5). This plan standardizes on **`['session-results', String(id)]`**. If Task 3 was implemented with a numeric id, the Task 4 implementer changes it to `String(id)` (and re-runs Task 3's test) before finishing.

---

### Task 5: Inline edit / add / delete on the grid (frontend)

**Files:**
- Create: `admin/src/components/ResultEditDialog.tsx`, `admin/src/test/ResultEditDialog.test.tsx`
- Modify: `admin/src/api/sessions.ts`, `admin/src/api/actions.ts` (broaden `invalidateKeys` type), `admin/src/pages/SessionDetail.tsx`

**Interfaces:**
- Consumes: `apiFetch`, `useToast`, `useQueryClient`, `SessionResultRow`.
- Produces:
  - `sessions.ts`: `useSaveResult(id)` and `useDeleteResult(id)` mutation hooks that PATCH/POST/DELETE and invalidate `['session-results', String(id)]`, toasting on success/error.
  - `ResultEditDialog.tsx`: `<ResultEditDialog sessionId mode={'edit'|'add'} initial? onClose />` — a Radix `Dialog` form over `driverCode, driverName, constructorId, constructorName, points, status`; Save calls the save mutation (PATCH for edit, POST for add).
  - `SessionDetail` gains an **Add result** button, an **Edit** action per row, and a **Delete** action per row.

- [ ] **Step 1: Broaden the `invalidateKeys` type**

In `admin/src/api/actions.ts` change the `invalidateKeys?: string[][]` field of the `useAdminAction` options to `invalidateKeys?: unknown[][]`, and in `admin/src/components/ActionButton.tsx` change the prop `invalidateKeys?: string[][]` to `invalidateKeys?: unknown[][]`. (TanStack `invalidateQueries({ queryKey })` accepts `unknown[]`.) Re-run `cd admin && npx vitest run src/test/ActionButton.test.tsx src/test/FetchControls.test.tsx` → still PASS.

- [ ] **Step 2: Write the failing test**

`admin/src/test/ResultEditDialog.test.tsx`:
```tsx
import { describe, it, expect, afterEach, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { ToastProvider } from '../ui/toast'
import { ResultEditDialog } from '../components/ResultEditDialog'
import { setToken } from '../api/client'

afterEach(() => { localStorage.clear(); vi.restoreAllMocks() })

function wrap(ui: React.ReactNode) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } })
  return <QueryClientProvider client={qc}><ToastProvider>{ui}</ToastProvider></QueryClientProvider>
}

describe('ResultEditDialog', () => {
  it('PATCHes the edited fields for an existing row', async () => {
    setToken('tok')
    const fetchMock = vi.fn().mockResolvedValue(new Response(JSON.stringify({ ok: true, result: {}, rescored: { users: 0, totalPoints: 0 } }), { status: 200 }))
    vi.stubGlobal('fetch', fetchMock)

    render(wrap(
      <ResultEditDialog
        sessionId={5}
        mode="edit"
        initial={{ position: 1, driverCode: 'VER', driverName: 'Max Verstappen', constructorId: 'red_bull', constructorName: 'Red Bull', points: 25, status: 'Finished', raceTime: null, q1: null, q2: null, q3: null }}
        onClose={() => {}}
      />
    ))

    const points = screen.getByLabelText(/points/i)
    await userEvent.clear(points)
    await userEvent.type(points, '18')
    await userEvent.click(screen.getByRole('button', { name: /save/i }))

    expect(await screen.findByText(/saved/i)).toBeInTheDocument()
    const patchCall = fetchMock.mock.calls.find((c) => (c[1]?.method ?? 'GET') === 'PATCH')
    expect(patchCall).toBeTruthy()
    expect(String(patchCall![0])).toMatch(/\/admin\/sessions\/5\/results\/1$/)
    expect(JSON.parse(patchCall![1].body).points).toBe(18)
  })
})
```

- [ ] **Step 3: Run to verify it fails**

Run: `cd admin && npx vitest run src/test/ResultEditDialog.test.tsx`
Expected: FAIL — `../components/ResultEditDialog` does not exist.

- [ ] **Step 4: Add the mutation hooks to `admin/src/api/sessions.ts`**

Append:
```ts
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { ApiError } from './client'
import { useToast } from '../ui/toast'
import type { SessionResultRow } from './types'

type ResultInput = Partial<SessionResultRow> & { position: number }

export function useSaveResult(id: number) {
  const qc = useQueryClient()
  const { show } = useToast()
  return useMutation({
    mutationFn: (input: { mode: 'edit' | 'add'; row: ResultInput }) =>
      input.mode === 'edit'
        ? apiFetch(`/admin/sessions/${id}/results/${input.row.position}`, { method: 'PATCH', body: input.row })
        : apiFetch(`/admin/sessions/${id}/results`, { method: 'POST', body: input.row }),
    onSuccess: () => { show('Saved', 'ok'); void qc.invalidateQueries({ queryKey: ['session-results', String(id)] }) },
    onError: (err) => show(err instanceof ApiError ? err.message : 'Save failed', 'error')
  })
}

export function useDeleteResult(id: number) {
  const qc = useQueryClient()
  const { show } = useToast()
  return useMutation({
    mutationFn: (position: number) => apiFetch(`/admin/sessions/${id}/results/${position}`, { method: 'DELETE' }),
    onSuccess: () => { show('Deleted', 'ok'); void qc.invalidateQueries({ queryKey: ['session-results', String(id)] }) },
    onError: (err) => show(err instanceof ApiError ? err.message : 'Delete failed', 'error')
  })
}
```
(Merge the new `import { apiFetch } from './client'` with the existing one — `client` is already imported; just add `ApiError` to that import and keep a single import line. `useQuery` stays imported alongside `useMutation, useQueryClient`.)

> The PATCH body should carry only the editable fields, not `position`. In `useSaveResult`, for edit mode strip `position` before sending: build the body as `const { position, ...fields } = input.row` and send `fields` for PATCH, the full `input.row` for POST. Implement it that way so the PATCH body matches the backend `patchBody` schema (which has no `position`).

- [ ] **Step 5: Create `admin/src/components/ResultEditDialog.tsx`**

```tsx
import { useState } from 'react'
import { Button, Dialog, Flex, Text, TextField } from '@radix-ui/themes'
import { useSaveResult } from '../api/sessions'
import type { SessionResultRow } from '../api/types'

type Props = {
  sessionId: number
  mode: 'edit' | 'add'
  initial?: SessionResultRow
  onClose: () => void
}

export function ResultEditDialog({ sessionId, mode, initial, onClose }: Props) {
  const save = useSaveResult(sessionId)
  const [f, setF] = useState({
    position: initial?.position ?? 1,
    driverCode: initial?.driverCode ?? '',
    driverName: initial?.driverName ?? '',
    constructorId: initial?.constructorId ?? '',
    constructorName: initial?.constructorName ?? '',
    points: initial?.points ?? null as number | null,
    status: initial?.status ?? ''
  })

  function field(label: string, key: keyof typeof f, type = 'text') {
    return (
      <label>
        <Text size="1" className="label">{label}</Text>
        <TextField.Root
          mt="1"
          type={type}
          value={f[key] === null ? '' : String(f[key])}
          onChange={(e) => setF((s) => ({ ...s, [key]: type === 'number' ? (e.target.value === '' ? null : Number(e.target.value)) : e.target.value }))}
        />
      </label>
    )
  }

  function onSave() {
    save.mutate(
      { mode, row: { position: Number(f.position), driverCode: f.driverCode, driverName: f.driverName, constructorId: f.constructorId, constructorName: f.constructorName, points: f.points, status: f.status || null } },
      { onSuccess: onClose }
    )
  }

  return (
    <Dialog.Root open onOpenChange={(o) => { if (!o) onClose() }}>
      <Dialog.Content maxWidth="420px">
        <Dialog.Title>{mode === 'add' ? 'Add result' : `Edit P${initial?.position}`}</Dialog.Title>
        <Flex direction="column" gap="3" mt="2">
          {mode === 'add' && field('Position', 'position', 'number')}
          {field('Driver code', 'driverCode')}
          {field('Driver name', 'driverName')}
          {field('Constructor id', 'constructorId')}
          {field('Constructor name', 'constructorName')}
          {field('Points', 'points', 'number')}
          {field('Status', 'status')}
          <Flex gap="2" justify="end" mt="2">
            <Button variant="soft" color="gray" onClick={onClose}>Cancel</Button>
            <Button onClick={onSave} disabled={save.isPending}>{save.isPending ? '…' : 'Save'}</Button>
          </Flex>
        </Flex>
      </Dialog.Content>
    </Dialog.Root>
  )
}
```

- [ ] **Step 6: Wire edit/add/delete into `admin/src/pages/SessionDetail.tsx`**

Add imports:
```tsx
import { useState } from 'react'
import { Button } from '@radix-ui/themes'
import { useDeleteResult } from '../api/sessions'
import { ResultEditDialog } from '../components/ResultEditDialog'
import type { SessionResultRow } from '../api/types'
```
Inside the component, add state + the delete hook:
```tsx
  const del = useDeleteResult(id)
  const [editing, setEditing] = useState<{ mode: 'edit' | 'add'; row?: SessionResultRow } | null>(null)
```
Add an **Add result** button next to Re-fetch/Re-score:
```tsx
        <Button variant="surface" onClick={() => setEditing({ mode: 'add' })}>Add result</Button>
```
Add an actions column header (`<Table.ColumnHeaderCell>Actions</Table.ColumnHeaderCell>`) and a per-row actions cell:
```tsx
                <Table.Cell>
                  <Flex gap="1">
                    <Button size="1" variant="soft" onClick={() => setEditing({ mode: 'edit', row: r })}>Edit</Button>
                    <Button size="1" variant="soft" color="red" onClick={() => del.mutate(r.position)}>Delete</Button>
                  </Flex>
                </Table.Cell>
```
And render the dialog at the end of the outer Flex:
```tsx
      {editing && (
        <ResultEditDialog sessionId={id} mode={editing.mode} initial={editing.row} onClose={() => setEditing(null)} />
      )}
```

- [ ] **Step 7: Run the tests + full gate**

Run: `cd admin && npx vitest run src/test/ResultEditDialog.test.tsx src/test/SessionDetail.test.tsx src/test/ActionButton.test.tsx`
Expected: PASS.

Run: `cd admin && npm test`
Expected: full suite green.

Run: `cd admin && npm run build`
Expected: `tsc -b` clean + `vite build`.

- [ ] **Step 8: Commit**

```bash
git add admin/src/components/ResultEditDialog.tsx admin/src/test/ResultEditDialog.test.tsx \
  admin/src/api/sessions.ts admin/src/api/actions.ts admin/src/components/ActionButton.tsx \
  admin/src/pages/SessionDetail.tsx
git commit -m "feat(admin-ui): inline edit/add/delete of session results"
```

---

## Self-Review

**Spec coverage (spec §4.2 writes, §6 data correction, roadmap item 4):**
- `PATCH /admin/sessions/:id/results/:position` (edit + rescore) → Task 2 ✓
- `POST` / `DELETE` result row (+ rescore) → Task 2 ✓
- FK validation (driver/constructor exist) + position uniqueness → Task 2 ✓
- Single-row repo helpers → Task 1 ✓
- Sessions list + SessionDetail grid → Tasks 3–4 ✓
- Inline edit/add/delete UI → Task 5 ✓
- Per-session Re-fetch / Re-score buttons → Task 4 ✓
- Provisional/source visibility → shown via the Sessions list badge (Task 3) ✓

**Type consistency:** `SessionResultRow`/`AdminSessionRow`/`SessionMeta` (Task 3 types) used by Tasks 3–5. The `session-results` query key is standardized to `['session-results', String(id)]` across `useSessionResults` (Task 3) and all invalidations (Tasks 4–5) — Task 4's note enforces this. `invalidateKeys` is broadened to `unknown[][]` in Task 5 step 1 before any non-string key is passed. Backend `updateResultFields`/`insertResult`/`getResult`/`deleteResult` (Task 1) consumed by the routes (Task 2).

**Open notes for the implementer:**
- Task 4 and Task 5 both touch `SessionDetail.tsx`; Task 5 layers the edit/add/delete onto Task 4's grid — apply Task 5's diffs onto the file Task 4 produced.
- PATCH must not include `position` in its body (backend `patchBody` has no `position`); Task 5 step 4 strips it for edit mode.
- The backend tests need the Postgres container up (`make db-up`) and must run single-file or via `npm test` (the suite is single-fork; don't run concurrent backend test processes).

## Next plans in this series

5. **Leagues admin** — backend cross-user league write routes + `Leagues`/`LeagueDetail` (rename, password, regenerate code, kick members, delete).
6. **Season management + remaining pages** — `Seasons` (bootstrap/activate/rescore/subjective-truth), drivers/constructors edit, users, predictions, standings, notifications.
