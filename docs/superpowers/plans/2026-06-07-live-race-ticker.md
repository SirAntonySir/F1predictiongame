# Live In-Progress Race Ticker — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** While a scorable F1 session is in progress, replace the "next session" view (Home hero + session results screen) with a live running order plus backend-computed projected points for the user and each league member, rendered with the existing colored rows.

**Architecture:** A new authenticated backend endpoint `GET /api/sessions/:id/live` pulls the current order from OpenF1 (on-demand, short server cache), and computes projected scores with the **existing backend scoring engine** (the live order treated as finishers) so projections equal the eventual official score. The Flutter app polls it (~20s) via a shared `LiveSessionController`; the Home hero and results screen render the snapshot, reusing existing widgets. Row tinting (exact/in-top-N/miss) stays client-side via the position-based `outcomeFor` (no scoring divergence); only point *totals* come from the backend.

**Tech Stack:** Backend — Node/TypeScript, Fastify, Drizzle, vitest. Frontend — Flutter/Dart, `ChangeNotifier`, `flutter_test`. Data — OpenF1 REST (`/position`, `/drivers`, `/sessions`).

**Spec:** `docs/superpowers/specs/2026-06-07-live-race-ticker-design.md` (note the 2026-06-07 revision: projections are server-side; `/live` is authenticated).

**Prerequisite (DONE):** Render web service is on Starter (always-on). Confirm `f1pg-db` is on `basic-256mb` so the live endpoint isn't racing the free-DB expiry. No further infra work in this plan.

> **Execution revision (2026-06-07): team colours.** The 2026 grid includes teams with no curated frontend
> colour (Audi, Cadillac) and slugs that don't match the colour map (red_bull_racing, haas_f1_team,
> racing_bulls) — 5 of 11 teams would render grey. Fix: the backend passes OpenF1's per-driver `teamColour`
> (hex) through on each live order row, and the frontend uses it as `teamColor(constructorId, fallbackHex:)`
> (the existing, intended mechanism). So: Task 2's `parseLivePositions` output rows carry `teamColour`;
> Task 5's `SessionResult` model gains an optional `teamColour`; Tasks 10/11 pass `fallbackHex: r.teamColour`.

---

## File Structure

**Backend (new):**
- `backend/src/openf1/live.ts` — `parseLivePositions(rawPositions, drivers)` and `resolveOpenF1SessionKey(session, client)`. Pure-ish OpenF1 → `SessionResultRow[]` + key resolution.
- `backend/src/scoring/project.ts` — `projectTotal(type, picks, order)`: maps a live order to `Finisher[]`, runs `scoreSession`, returns the point total (or `null` when picks are incomplete).
- `backend/src/api/routes/live.ts` — `registerLiveRoutes` Fastify plugin: `GET /api/sessions/:id/live`.

**Backend (modified):**
- `backend/src/openf1/client.ts` — add `getPosition(sessionKey)`.
- `backend/src/index.ts` — register the live routes plugin.

**Frontend (new):**
- `lib/api/models/live_snapshot.dart` — `LiveSnapshot` + `LiveState` enum.
- `lib/domain/live_session.dart` — `isSessionLive(session, now)`, `findLiveSession(events, now)`.
- `lib/state/live_session_controller.dart` — `LiveSessionController` (detect live session + poll `/live`).

**Frontend (modified):**
- `lib/api/api_client.dart` — add `sessionLive(...)` signature.
- `lib/api/http_api_client.dart` — implement `sessionLive(...)`.
- `lib/state/app_state.dart` — expose `LiveSessionController` in scope.
- `lib/main.dart` — construct + wire `LiveSessionController`.
- `lib/screens/home_screen.dart` — live hero card + suppress "next" while live.
- `lib/screens/session_results_screen.dart` — live mode in `_payloadFor`/`_Body`.

**Tests (new):** `backend/test/unit/openf1_live.test.ts`, `backend/test/unit/scoring_project.test.ts`, `backend/test/integration/route_live.test.ts`, `test/api/live_snapshot_test.dart`, `test/domain/live_session_test.dart`, `test/state/live_session_controller_test.dart`, `test/screens/live_results_test.dart`, `test/screens/home_live_hero_test.dart`.

**Run tests:** backend via `make backend-test` (sources `.env`; vitest forces `NODE_ENV=test`). Frontend via `flutter test`.

---

## Phase 0 — Spike (de-risk OpenF1 live data)

### Task 0: Validate OpenF1 live endpoints

**No production code.** Confirms the one unproven assumption before building.

- [ ] **Step 1: Find a recent/live session_key and inspect `/position` + `/drivers`**

Run (replace year as needed; pick a recent race meeting):
```bash
curl -s "https://api.openf1.org/v1/sessions?year=2026" | head -c 4000
# pick a session_key for a Race/Qualifying/Sprint, then:
curl -s "https://api.openf1.org/v1/position?session_key=<KEY>" | head -c 2000
curl -s "https://api.openf1.org/v1/drivers?session_key=<KEY>"  | head -c 2000
```
Expected: `/position` returns rows shaped `{ "date": "...", "driver_number": N, "position": P, "session_key": K, ... }` (time-series — multiple rows per driver). `/drivers` returns rows with `name_acronym`, `first_name`, `last_name`, `team_name`, `team_colour`. `/sessions` rows have `session_key`, `session_name` (`"Race"`/`"Qualifying"`/`"Sprint"`/`"Sprint Qualifying"`), `date_start`, `country_name`.

- [ ] **Step 2: Record findings in the plan's notes**

Confirm: (a) latest position per driver = max `date` per `driver_number`; (b) `session_name` values map to our `sessionNameFor(type)`; (c) whether a key exists *during* a live session (note latency). If `/position` is unsuitable for qualifying ordering (track position ≠ timing classification), note it — v1 still uses `/position` for all types and labels quali/shootout as approximate (per spec §6).

- [ ] **Step 3: Commit a short note** (optional)

```bash
git commit --allow-empty -m "chore: openf1 live-data spike notes (position/drivers/sessions verified)"
```

---

## Phase 1 — Backend

### Task 1: `OpenF1Client.getPosition`

**Files:**
- Modify: `backend/src/openf1/client.ts`
- Test: `backend/test/unit/openf1_client.test.ts` (add a case)

- [ ] **Step 1: Add the failing test** (append inside the existing `describe('OpenF1Client', …)` in `backend/test/unit/openf1_client.test.ts`)

```ts
  it('GET /position?session_key=K', async () => {
    const { fetchFn, calls } = fakeFetch({
      'https://api.openf1.org/v1/position?session_key=9876': {
        status: 200,
        body: [{ driver_number: 1, position: 1, date: '2026-06-07T13:00:00Z' }]
      }
    })
    const c = new OpenF1Client('https://api.openf1.org/v1', fetchFn)
    const out = await c.getPosition(9876)
    expect(out).toEqual([{ driver_number: 1, position: 1, date: '2026-06-07T13:00:00Z' }])
    expect(calls).toEqual(['https://api.openf1.org/v1/position?session_key=9876'])
  })
```

- [ ] **Step 2: Run it, verify it fails**

Run: `make backend-test`
Expected: FAIL — `c.getPosition is not a function`.

- [ ] **Step 3: Implement** (add to the `OpenF1Client` class in `backend/src/openf1/client.ts`, next to `getSessionResult`)

```ts
  getPosition(sessionKey: number) {
    return this.getJson(`/position?session_key=${sessionKey}`)
  }
```

- [ ] **Step 4: Run tests, verify pass**

Run: `make backend-test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/src/openf1/client.ts backend/test/unit/openf1_client.test.ts
git commit -m "feat(openf1): add getPosition client method"
```

---

### Task 2: Live-order parser + session-key resolver (`openf1/live.ts`)

**Files:**
- Create: `backend/src/openf1/live.ts`
- Test: `backend/test/unit/openf1_live.test.ts`

- [ ] **Step 1: Write the failing test** (`backend/test/unit/openf1_live.test.ts`)

```ts
import { describe, it, expect } from 'vitest'
import { parseLivePositions, resolveOpenF1SessionKey } from '../../src/openf1/live.js'
import type { OpenF1DriverLookup } from '../../src/openf1/parsers.js'
import type { StoredSession } from '../../src/repo/sessions.js'

const drivers: OpenF1DriverLookup[] = [
  { driverNumber: 1, code: 'VER', givenName: 'Max', familyName: 'Verstappen', teamName: 'Red Bull Racing', headshotUrl: null, teamColour: null },
  { driverNumber: 16, code: 'LEC', givenName: 'Charles', familyName: 'Leclerc', teamName: 'Ferrari', headshotUrl: null, teamColour: null }
]

describe('parseLivePositions', () => {
  it('keeps the latest position per driver and joins driver info', () => {
    const raw = [
      { driver_number: 1, position: 2, date: '2026-06-07T13:00:00Z' },
      { driver_number: 16, position: 1, date: '2026-06-07T13:00:00Z' },
      { driver_number: 1, position: 1, date: '2026-06-07T13:05:00Z' }, // later → wins
      { driver_number: 16, position: 2, date: '2026-06-07T13:05:00Z' }
    ]
    const out = parseLivePositions(raw, drivers)
    expect(out.map((r) => [r.position, r.driverCode])).toEqual([[1, 'VER'], [2, 'LEC']])
    expect(out[0]).toMatchObject({ constructorId: 'red_bull', constructorName: 'Red Bull Racing', driverName: 'Max Verstappen' })
  })

  it('skips drivers not present in the lookup and tolerates empty input', () => {
    expect(parseLivePositions([], drivers)).toEqual([])
    expect(parseLivePositions([{ driver_number: 99, position: 1, date: 'x' }], drivers)).toEqual([])
  })
})

describe('resolveOpenF1SessionKey', () => {
  const base: StoredSession = {
    id: 5, eventId: 1, type: 'race',
    scheduledStart: new Date('2026-06-07T13:00:00Z'),
    scheduledEnd: new Date('2026-06-07T15:00:00Z'),
    status: 'scheduled', openf1SessionKey: null
  }

  it('returns the stored key without calling OpenF1', async () => {
    let called = false
    const client = { getSessions: async () => { called = true; return [] } } as any
    const key = await resolveOpenF1SessionKey({ ...base, openf1SessionKey: 4242 }, client, async () => {})
    expect(key).toBe(4242)
    expect(called).toBe(false)
  })

  it('matches by session_name + nearest date_start, then persists', async () => {
    const client = {
      getSessions: async () => [
        { session_key: 11, session_name: 'Qualifying', date_start: '2026-06-07T13:00:00Z' },
        { session_key: 22, session_name: 'Race', date_start: '2026-06-07T13:02:00Z' },
        { session_key: 33, session_name: 'Race', date_start: '2026-06-14T13:00:00Z' }
      ]
    } as any
    let persisted: [number, number | null] | null = null
    const key = await resolveOpenF1SessionKey(base, client, async (id, k) => { persisted = [id, k] })
    expect(key).toBe(22)
    expect(persisted).toEqual([5, 22])
  })

  it('returns null when nothing matches within the window', async () => {
    const client = { getSessions: async () => [{ session_key: 1, session_name: 'Race', date_start: '2026-01-01T00:00:00Z' }] } as any
    expect(await resolveOpenF1SessionKey(base, client, async () => {})).toBeNull()
  })
})
```

- [ ] **Step 2: Run it, verify it fails**

Run: `make backend-test`
Expected: FAIL — cannot find module `../../src/openf1/live.js`.

- [ ] **Step 3: Implement** (`backend/src/openf1/live.ts`)

```ts
import type { SessionResultRow, SessionType } from '../domain/types.js'
import type { StoredSession } from '../repo/sessions.js'
import { parseDrivers, sessionNameFor, type OpenF1DriverLookup } from './parsers.js'

type OpenF1Client = {
  getSessions: (year: number) => Promise<unknown | null>
  getDrivers: (sessionKey: number) => Promise<unknown | null>
  getPosition: (sessionKey: number) => Promise<unknown | null>
}

/** Reduce the OpenF1 /position time-series to the latest position per driver,
 *  join with the drivers lookup, and emit SessionResultRow[] sorted by position.
 *  Drivers missing from the lookup are skipped. raceTime/points/q* are null
 *  (live order carries no times or championship points). */
export function parseLivePositions(raw: unknown, drivers: OpenF1DriverLookup[]): SessionResultRow[] {
  const byNumber = new Map(drivers.map((d) => [d.driverNumber, d]))
  const latest = new Map<number, { position: number; date: string }>()
  for (const r of (raw as any[]) ?? []) {
    const num = Number(r.driver_number)
    const date = String(r.date ?? '')
    const prev = latest.get(num)
    if (!prev || date > prev.date) latest.set(num, { position: Number(r.position), date })
  }
  const out: SessionResultRow[] = []
  for (const [num, { position }] of latest) {
    const drv = byNumber.get(num)
    if (!drv) continue
    out.push({
      sessionId: 0,
      position,
      driverCode: drv.code,
      driverName: `${drv.givenName} ${drv.familyName}`.trim(),
      constructorId: drv.teamName.toLowerCase().replace(/\s+/g, '_'),
      constructorName: drv.teamName,
      raceTime: null, status: null, points: null,
      fastestLap: null, fastestLapTime: null, fastestLapSpeed: null,
      q1: null, q2: null, q3: null
    })
  }
  out.sort((a, b) => a.position - b.position)
  return out
}

const MATCH_WINDOW_MS = 6 * 60 * 60 * 1000 // 6h around scheduledStart

/** Resolve the OpenF1 session_key for a stored session. Uses the persisted key
 *  if present; otherwise matches OpenF1's session list by name + nearest
 *  date_start within ±6h, persists the result via `persist`, and returns it
 *  (or null if no match). */
export async function resolveOpenF1SessionKey(
  session: StoredSession,
  client: Pick<OpenF1Client, 'getSessions'>,
  persist: (id: number, key: number | null) => Promise<void>
): Promise<number | null> {
  if (session.openf1SessionKey != null) return session.openf1SessionKey
  const year = session.scheduledStart.getUTCFullYear()
  const raw = (await client.getSessions(year)) as any[] | null
  if (!raw) return null
  const wantName = sessionNameFor(session.type)
  const target = session.scheduledStart.getTime()
  let best: { key: number; diff: number } | null = null
  for (const s of raw) {
    if (String(s.session_name) !== wantName) continue
    const diff = Math.abs(new Date(String(s.date_start)).getTime() - target)
    if (diff > MATCH_WINDOW_MS) continue
    if (!best || diff < best.diff) best = { key: Number(s.session_key), diff }
  }
  if (!best) return null
  await persist(session.id, best.key)
  return best.key
}
```

- [ ] **Step 4: Run tests, verify pass**

Run: `make backend-test`
Expected: PASS (all `openf1_live` cases).

- [ ] **Step 5: Commit**

```bash
git add backend/src/openf1/live.ts backend/test/unit/openf1_live.test.ts
git commit -m "feat(openf1): live-position parser + session-key resolver"
```

---

### Task 3: Projection helper (`scoring/project.ts`)

**Files:**
- Create: `backend/src/scoring/project.ts`
- Test: `backend/test/unit/scoring_project.test.ts`

- [ ] **Step 1: Write the failing test** (`backend/test/unit/scoring_project.test.ts`)

```ts
import { describe, it, expect } from 'vitest'
import { projectTotal } from '../../src/scoring/project.js'
import type { SessionResultRow } from '../../src/domain/types.js'

function row(position: number, driverCode: string, constructorId: string): SessionResultRow {
  return { sessionId: 0, position, driverCode, driverName: driverCode, constructorId, constructorName: constructorId,
    raceTime: null, status: null, points: null, fastestLap: null, fastestLapTime: null, fastestLapSpeed: null, q1: null, q2: null, q3: null }
}

const order = [row(1, 'VER', 'red_bull'), row(2, 'LEC', 'ferrari'), row(3, 'NOR', 'mclaren'),
               row(4, 'PIA', 'mclaren'), row(5, 'RUS', 'mercedes')]

describe('projectTotal', () => {
  it('scores a full race pick set using backend rules (exact 3, wrongPos 1, +2 team bonus)', () => {
    // picks P1..P5; VER exact (3), LEC exact (3), PIA in top-5 wrong slot (1), HAM miss (0), RUS exact (3)
    // P1 pick VER → winner VER same team → team bonus +2  => 3+3+1+0+3 +2 = 12
    const picks = [
      { position: 1, driverCode: 'VER' }, { position: 2, driverCode: 'LEC' },
      { position: 3, driverCode: 'PIA' }, { position: 4, driverCode: 'HAM' },
      { position: 5, driverCode: 'RUS' }
    ]
    expect(projectTotal('race', picks, order)).toBe(12)
  })

  it('returns null when the pick count does not match the session type', () => {
    expect(projectTotal('race', [{ position: 1, driverCode: 'VER' }], order)).toBeNull()
    expect(projectTotal('race', [], order)).toBeNull()
  })

  it('returns null for non-scorable types', () => {
    expect(projectTotal('fp1', [], order)).toBeNull()
  })
})
```

- [ ] **Step 2: Run it, verify it fails**

Run: `make backend-test`
Expected: FAIL — cannot find module `../../src/scoring/project.js`.

- [ ] **Step 3: Implement** (`backend/src/scoring/project.ts`)

```ts
import type { SessionResultRow, SessionType } from '../domain/types.js'
import type { Finisher, Pick } from './types.js'
import { scoreSession, picksRequiredFor } from './index.js'

/** Project a point total from a (possibly live) order, using the canonical
 *  backend scoring engine. Returns null when the type isn't scorable or the
 *  pick count doesn't match what the type expects (so partial/empty picks
 *  don't throw). The order is treated as the finishers. */
export function projectTotal(
  type: SessionType,
  picks: Pick[],
  order: SessionResultRow[]
): number | null {
  const required = picksRequiredFor(type)
  if (required == null) return null
  if (picks.length !== required) return null
  const finishers: Finisher[] = order.map((r) => ({
    position: r.position, driverCode: r.driverCode, constructorId: r.constructorId
  }))
  const b = scoreSession(type, picks, finishers)
  return b.perPosition.reduce((s, x) => s + x.points, 0) + b.teamBonus.points
}
```

> Note: confirm `picksRequiredFor` is exported from `scoring/index.ts` (it is, per index.ts:42, returning `number | null`). If the name differs, use `isScorableSessionType` + `EXPECTED_PICKS`.

- [ ] **Step 4: Run tests, verify pass**

Run: `make backend-test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/src/scoring/project.ts backend/test/unit/scoring_project.test.ts
git commit -m "feat(scoring): projectTotal for live order using canonical engine"
```

---

### Task 4: `GET /api/sessions/:id/live` route

**Files:**
- Create: `backend/src/api/routes/live.ts`
- Modify: `backend/src/index.ts` (register the plugin)
- Test: `backend/test/integration/route_live.test.ts`

- [ ] **Step 1: Write the failing integration test** (`backend/test/integration/route_live.test.ts`)

Mirror existing integration tests (seed via repos against the test DB, build the app with a fake OpenF1 client, use `app.inject`). Look at a sibling in `backend/test/integration/` for the exact seed helpers / `buildApp` opts and auth-token creation; reuse them.

```ts
import { describe, it, expect, beforeEach } from 'vitest'
import { buildApp } from '../../src/index.js'
import { resetDb, seedSession, seedUserWithToken, seedPrediction, seedLeagueWith } from '../helpers/seed.js' // use the project's actual helpers
import type { FastifyInstance } from 'fastify'

function fakeOpenF1() {
  return {
    getSessions: async () => [{ session_key: 777, session_name: 'Race', date_start: '2026-06-07T13:00:00Z' }],
    getDrivers: async () => [
      { driver_number: 1, name_acronym: 'VER', first_name: 'Max', last_name: 'Verstappen', team_name: 'Red Bull Racing' },
      { driver_number: 16, name_acronym: 'LEC', first_name: 'Charles', last_name: 'Leclerc', team_name: 'Ferrari' }
    ],
    getPosition: async () => [
      { driver_number: 1, position: 1, date: '2026-06-07T13:30:00Z' },
      { driver_number: 16, position: 2, date: '2026-06-07T13:30:00Z' }
    ],
    getSessionResult: async () => null
  }
}

describe('GET /api/sessions/:id/live', () => {
  let app: FastifyInstance
  beforeEach(async () => {
    await resetDb()
    app = await buildApp({ scheduler: null, jolpica: {} as any, wiki: {} as any, openf1: fakeOpenF1() as any })
  })

  it('returns live order + my projected total for an in-progress race', async () => {
    const { token, userId } = await seedUserWithToken()
    const sessionId = await seedSession({ type: 'race', status: 'scheduled',
      scheduledStart: new Date(Date.now() - 30 * 60_000), scheduledEnd: new Date(Date.now() + 60 * 60_000),
      openf1SessionKey: 777 })
    await seedPrediction(userId, sessionId, [
      { position: 1, driverCode: 'VER' }, { position: 2, driverCode: 'LEC' },
      { position: 3, driverCode: 'X' }, { position: 4, driverCode: 'Y' }, { position: 5, driverCode: 'Z' }
    ])
    const res = await app.inject({ method: 'GET', url: `/api/sessions/${sessionId}/live`, headers: { authorization: `Bearer ${token}` } })
    expect(res.statusCode).toBe(200)
    const body = res.json()
    expect(body.state).toBe('live')
    expect(body.order.map((r: any) => [r.position, r.driverCode])).toEqual([[1, 'VER'], [2, 'LEC']])
    // VER exact (3) + LEC exact (3) + 0 + 0 + 0, P1 team bonus +2 = 8
    expect(body.myProjected.pointsTotal).toBe(8)
  })

  it('401 without a token', async () => {
    const sessionId = await seedSession({ type: 'race', status: 'scheduled',
      scheduledStart: new Date(Date.now() - 1000), scheduledEnd: new Date(Date.now() + 1000), openf1SessionKey: 777 })
    const res = await app.inject({ method: 'GET', url: `/api/sessions/${sessionId}/live` })
    expect(res.statusCode).toBe(401)
  })

  it('returns state=final for a finished session (client should use /results)', async () => {
    const { token } = await seedUserWithToken()
    const sessionId = await seedSession({ type: 'race', status: 'finished',
      scheduledStart: new Date(Date.now() - 3 * 3600_000), scheduledEnd: new Date(Date.now() - 2 * 3600_000), openf1SessionKey: 777 })
    const res = await app.inject({ method: 'GET', url: `/api/sessions/${sessionId}/live`, headers: { authorization: `Bearer ${token}` } })
    expect(res.json().state).toBe('final')
  })
})
```

> If the test helpers (`seedSession`, `seedUserWithToken`, `seedPrediction`, `seedLeagueWith`) don't exist with these names, create thin wrappers in `backend/test/helpers/seed.ts` over the existing repos (`sessionsRepo.upsertSession`, the auth/signup flow, `predictionsRepo.upsertPredictionWithPicks`, league repos). Match the patterns already used by other files in `backend/test/integration/`.

- [ ] **Step 2: Run it, verify it fails**

Run: `make backend-test`
Expected: FAIL — route 404/`Not found` (plugin not registered yet).

- [ ] **Step 3: Implement the route** (`backend/src/api/routes/live.ts`)

```ts
import type { FastifyInstance } from 'fastify'
import { getCurrentUser, registerAuthHook } from '../auth-context.js'
import { ApiError } from '../errors.js'
import { config } from '../../config.js'
import { OpenF1Client } from '../../openf1/client.js'
import { parseDrivers } from '../../openf1/parsers.js'
import { parseLivePositions, resolveOpenF1SessionKey } from '../../openf1/live.js'
import { projectTotal } from '../../scoring/project.js'
import { isScorableSessionType } from '../../scoring/index.js'
import * as sessionsRepo from '../../repo/sessions.js'
import * as predictionsRepo from '../../repo/predictions.js'
import * as picksRepo from '../../repo/predictionPicks.js'

export type LiveDeps = { openf1: Pick<OpenF1Client, 'getSessions' | 'getDrivers' | 'getPosition'> }

export async function registerLiveRoutes(app: FastifyInstance, deps?: LiveDeps): Promise<void> {
  registerAuthHook(app)
  const openf1 = deps?.openf1 ?? new OpenF1Client(config.openf1Base)

  app.get<{ Params: { id: string }; Querystring: { leagueId?: string } }>(
    '/api/sessions/:id/live',
    async (req) => {
      const u = getCurrentUser(req)
      const id = Number(req.params.id)
      if (!Number.isFinite(id)) throw new ApiError('BAD_REQUEST', 'id must be a number')
      const s = await sessionsRepo.getById(id)
      if (!s) throw new ApiError('NOT_FOUND', `Session ${id} not found`)
      if (!isScorableSessionType(s.type)) throw new ApiError('BAD_REQUEST', 'session type is not scorable')

      const asOf = new Date().toISOString()
      if (s.status === 'finished') {
        return { sessionId: id, state: 'final', asOf, order: [], myProjected: null, leagueProjected: [] }
      }

      const key = await resolveOpenF1SessionKey(s, openf1, sessionsRepo.setOpenF1SessionKey)
      if (key == null) {
        return { sessionId: id, state: 'unavailable', asOf, order: [], myProjected: null, leagueProjected: [] }
      }

      const [rawPos, rawDrv] = await Promise.all([openf1.getPosition(key), openf1.getDrivers(key)])
      const order = parseLivePositions(rawPos, parseDrivers(rawDrv))
      const pastEnd = Date.now() >= s.scheduledEnd.getTime()
      const state = order.length === 0 ? (pastEnd ? 'provisional' : 'pre') : (pastEnd ? 'provisional' : 'live')

      // My projection
      const myPred = await predictionsRepo.getByUserAndSession(u.id, id)
      const myPicks = myPred ? await picksRepo.listForPrediction(myPred.id) : []
      const myProjected = { pointsTotal: projectTotal(s.type, myPicks, order) }

      // League projections (optional ?leagueId=, members the caller can see)
      let leagueProjected: Array<{ userId: string; displayName: string; picks: { position: number; driverCode: string }[]; pointsTotal: number | null }> = []
      const leagueId = req.query.leagueId
      if (leagueId) {
        const members = await predictionsRepo.listLeagueMemberPredictions(leagueId, id)
        leagueProjected = members
          .filter((m) => m.userId !== u.id)
          .map((m) => ({ userId: m.userId, displayName: m.displayName, picks: m.picks, pointsTotal: projectTotal(s.type, m.picks, order) }))
          .sort((a, b) => (b.pointsTotal ?? -1) - (a.pointsTotal ?? -1))
      }

      return { sessionId: id, state, asOf, order, myProjected, leagueProjected }
    }
  )
}
```

> Verify import paths: `picksRepo.listForPrediction` lives in `repo/predictionPicks.ts` (per Task context). `isScorableSessionType` is exported from `scoring/index.ts`. If `registerAuthHook` requires the plugin to be registered via `app.register`, see Step 4.

- [ ] **Step 4: Register the plugin** in `backend/src/index.ts` `buildApp`, right after `await registerPublicRoutes(app)` (line 36):

```ts
  await registerPublicRoutes(app)
  await app.register(registerLiveRoutes, { openf1: opts.openf1 })   // <-- add
```

Add the import near the other route imports (line ~6):
```ts
import { registerLiveRoutes } from './api/routes/live.js'
```

> `opts.openf1` already exists on `BuildAppOpts` (it's part of `AdminDeps`). Passing it as plugin options lets tests inject a fake; production uses the real client wired in `index.ts`'s bootstrap.

- [ ] **Step 5: Run tests, verify pass**

Run: `make backend-test`
Expected: PASS (all `route_live` cases).

- [ ] **Step 6: Commit**

```bash
git add backend/src/api/routes/live.ts backend/src/index.ts backend/test/integration/route_live.test.ts backend/test/helpers/seed.ts
git commit -m "feat(api): GET /api/sessions/:id/live with backend-computed projections"
```

---

## Phase 2 — Frontend data layer

### Task 5: `LiveSnapshot` model

**Files:**
- Create: `lib/api/models/live_snapshot.dart`
- Test: `test/api/live_snapshot_test.dart`

- [ ] **Step 1: Write the failing test** (`test/api/live_snapshot_test.dart`)

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/models/live_snapshot.dart';

void main() {
  test('LiveSnapshot.fromJson parses state, order, projections', () {
    final j = {
      'sessionId': 5,
      'state': 'live',
      'asOf': '2026-06-07T13:30:00Z',
      'order': [
        {'position': 1, 'driverCode': 'VER', 'driverName': 'Max Verstappen', 'constructorId': 'red_bull', 'constructorName': 'Red Bull Racing'}
      ],
      'myProjected': {'pointsTotal': 8},
      'leagueProjected': [
        {'userId': 'u2', 'displayName': 'Lukas', 'picks': [{'position': 1, 'driverCode': 'LEC'}], 'pointsTotal': 3}
      ]
    };
    final s = LiveSnapshot.fromJson(j);
    expect(s.state, LiveState.live);
    expect(s.order.single.driverCode, 'VER');
    expect(s.myPointsTotal, 8);
    expect(s.league.single.displayName, 'Lukas');
    expect(s.league.single.pointsTotal, 3);
  });

  test('unknown state falls back to unavailable; null projection tolerated', () {
    final s = LiveSnapshot.fromJson({
      'sessionId': 1, 'state': 'weird', 'asOf': '2026-06-07T13:30:00Z',
      'order': [], 'myProjected': {'pointsTotal': null}, 'leagueProjected': []
    });
    expect(s.state, LiveState.unavailable);
    expect(s.myPointsTotal, isNull);
    expect(s.order, isEmpty);
  });
}
```

- [ ] **Step 2: Run it, verify it fails**

Run: `flutter test test/api/live_snapshot_test.dart`
Expected: FAIL — target of URI doesn't exist (`live_snapshot.dart`).

- [ ] **Step 3: Implement** (`lib/api/models/live_snapshot.dart`)

```dart
import 'member_prediction.dart';
import 'session_result.dart';

enum LiveState { pre, live, provisional, finalised, unavailable }

LiveState _stateFrom(String s) {
  switch (s) {
    case 'pre': return LiveState.pre;
    case 'live': return LiveState.live;
    case 'provisional': return LiveState.provisional;
    case 'final': return LiveState.finalised;
    default: return LiveState.unavailable;
  }
}

/// One poll of the live endpoint. `order` reuses [SessionResult] so the existing
/// colored-row rendering works unchanged. `league` reuses [MemberPrediction]
/// (userId/displayName/picks/pointsTotal) with pointsTotal = backend-projected.
class LiveSnapshot {
  final int sessionId;
  final LiveState state;
  final DateTime asOf;
  final List<SessionResult> order;
  /// Caller's projected total; null when picks are incomplete/absent.
  final int? myPointsTotal;
  /// Each league member's picks + projected total, excluding the caller, sorted desc.
  final List<MemberPrediction> league;

  const LiveSnapshot({
    required this.sessionId,
    required this.state,
    required this.asOf,
    required this.order,
    required this.myPointsTotal,
    required this.league,
  });

  factory LiveSnapshot.fromJson(Map<String, dynamic> j) => LiveSnapshot(
        sessionId: j['sessionId'] as int,
        state: _stateFrom(j['state'] as String),
        asOf: DateTime.parse(j['asOf'] as String).toLocal(),
        order: ((j['order'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(SessionResult.fromJson)
            .toList(),
        myPointsTotal: (j['myProjected'] as Map<String, dynamic>?)?['pointsTotal'] as int?,
        league: ((j['leagueProjected'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(MemberPrediction.fromJson)
            .toList(),
      );
}
```

> Verify `MemberPrediction.fromJson` accepts `{userId, displayName, picks:[{position,driverCode}], pointsTotal}`. It does (it backs `leagueSessionPredictions`). If its `pointsTotal` key name differs, align the backend response key to match the existing model so this reuse holds.

- [ ] **Step 4: Run tests, verify pass**

Run: `flutter test test/api/live_snapshot_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/api/models/live_snapshot.dart test/api/live_snapshot_test.dart
git commit -m "feat(model): LiveSnapshot"
```

---

### Task 6: `ApiClient.sessionLive` + HTTP impl

**Files:**
- Modify: `lib/api/api_client.dart`, `lib/api/http_api_client.dart`
- Test: extend the existing http client test if present, else `test/api/http_client_live_test.dart`

- [ ] **Step 1: Write the failing test** (`test/api/http_client_live_test.dart`)

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:predictiongame/api/http_api_client.dart';
import 'package:predictiongame/api/models/live_snapshot.dart';

void main() {
  test('sessionLive GETs /live with leagueId and parses snapshot', () async {
    late Uri seen;
    final mock = MockClient((req) async {
      seen = req.url;
      return http.Response(
        '{"sessionId":5,"state":"live","asOf":"2026-06-07T13:30:00Z","order":[],"myProjected":{"pointsTotal":7},"leagueProjected":[]}',
        200, headers: {'content-type': 'application/json'});
    });
    final api = HttpApiClient(baseUrl: 'https://x.test', tokenProvider: () => 'tok',
        onUnauthorized: () {}, client: mock);
    final snap = await api.sessionLive(5, leagueId: 'lg1');
    expect(seen.path, '/api/sessions/5/live');
    expect(seen.queryParameters['leagueId'], 'lg1');
    expect(snap.state, LiveState.live);
    expect(snap.myPointsTotal, 7);
  });
}
```

> Match the `HttpApiClient` constructor to its real signature (from `http_api_client.dart`: `baseUrl`, `tokenProvider`, `onUnauthorized`, `client`). If a test already constructs it, copy that.

- [ ] **Step 2: Run it, verify it fails**

Run: `flutter test test/api/http_client_live_test.dart`
Expected: FAIL — `sessionLive` not defined.

- [ ] **Step 3: Add the interface method** in `lib/api/api_client.dart` (next to `sessionResults`, ~line 30):

```dart
  Future<LiveSnapshot> sessionLive(int id, {String? leagueId});
```

Add the import at the top of `lib/api/api_client.dart` with the other model imports:
```dart
import 'models/live_snapshot.dart';
```

- [ ] **Step 4: Implement** in `lib/api/http_api_client.dart` (near `sessionResults`, ~line 117). Reuse `_request`:

```dart
  @override
  Future<LiveSnapshot> sessionLive(int id, {String? leagueId}) async {
    final q = leagueId == null ? '' : '?leagueId=$leagueId';
    final j = await _request('GET', '/api/sessions/$id/live$q');
    return LiveSnapshot.fromJson(j as Map<String, dynamic>);
  }
```

Add the import at the top of `lib/api/http_api_client.dart`:
```dart
import 'models/live_snapshot.dart';
```

- [ ] **Step 5: Run tests, verify pass**

Run: `flutter test test/api/http_client_live_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/api/api_client.dart lib/api/http_api_client.dart test/api/http_client_live_test.dart
git commit -m "feat(api-client): sessionLive"
```

---

### Task 7: Live-session predicate (`domain/live_session.dart`)

**Files:**
- Create: `lib/domain/live_session.dart`
- Test: `test/domain/live_session_test.dart`

- [ ] **Step 1: Write the failing test** (`test/domain/live_session_test.dart`)

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/models/event.dart';
import 'package:predictiongame/api/models/session.dart';
import 'package:predictiongame/domain/live_session.dart';

Session _s(int id, SessionType type, DateTime start, DateTime end, SessionStatus status) =>
    Session(id: id, type: type, scheduledStart: start, scheduledEnd: end, status: status);

void main() {
  final now = DateTime.utc(2026, 6, 7, 13, 30);

  test('a scorable session that has started and is not finished is live', () {
    final s = _s(1, SessionType.race, now.subtract(const Duration(hours: 1)),
        now.add(const Duration(hours: 1)), SessionStatus.scheduled);
    expect(isSessionLive(s, now), isTrue);
  });

  test('finished, not-yet-started, non-scorable, and long-past are not live', () {
    expect(isSessionLive(_s(1, SessionType.race, now.subtract(const Duration(hours: 1)), now.add(const Duration(hours: 1)), SessionStatus.finished), now), isFalse);
    expect(isSessionLive(_s(1, SessionType.race, now.add(const Duration(hours: 1)), now.add(const Duration(hours: 3)), SessionStatus.scheduled), now), isFalse);
    expect(isSessionLive(_s(1, SessionType.fp1, now.subtract(const Duration(hours: 1)), now.add(const Duration(hours: 1)), SessionStatus.scheduled), now), isFalse);
    // ended >6h ago but still flagged scheduled (crawler missed it) → not live (safety cap)
    expect(isSessionLive(_s(1, SessionType.race, now.subtract(const Duration(hours: 9)), now.subtract(const Duration(hours: 7)), SessionStatus.scheduled), now), isFalse);
  });

  test('provisional window (just past end, still scheduled) is live', () {
    final s = _s(1, SessionType.race, now.subtract(const Duration(hours: 3)),
        now.subtract(const Duration(minutes: 10)), SessionStatus.scheduled);
    expect(isSessionLive(s, now), isTrue);
  });

  test('findLiveSession returns the live one across events', () {
    final events = [
      Event(round: 1, name: 'A', country: 'X', circuitName: 'c', hasSprint: false, sessions: [
        _s(10, SessionType.race, now.subtract(const Duration(hours: 1)), now.add(const Duration(hours: 1)), SessionStatus.scheduled),
      ]),
    ];
    expect(findLiveSession(events, now)?.id, 10);
    expect(findLiveSession(const [], now), isNull);
  });
}
```

> Match the `Session`/`Event` constructors to their real shapes (from `lib/api/models/session.dart` / `event.dart`). Adjust named args if needed.

- [ ] **Step 2: Run it, verify it fails**

Run: `flutter test test/domain/live_session_test.dart`
Expected: FAIL — `live_session.dart` missing.

- [ ] **Step 3: Implement** (`lib/domain/live_session.dart`)

```dart
import '../api/models/event.dart';
import '../api/models/session.dart';
import 'prediction.dart';

/// Safety cap so a session the crawler never scored doesn't read "live" forever.
const _maxProvisional = Duration(hours: 6);

/// A scorable session that has started (locked) and isn't finished yet — spans
/// the running phase AND the post-end "provisional" gap until the backend marks
/// it finished, bounded by [_maxProvisional] past its scheduled end.
bool isSessionLive(Session s, DateTime now) {
  if (requiredPicks(s.type) <= 0) return false;
  if (s.status == SessionStatus.finished) return false;
  if (now.isBefore(s.scheduledStart)) return false;
  if (now.isAfter(s.scheduledEnd.add(_maxProvisional))) return false;
  return true;
}

/// The single live scorable session across [events], or null. (F1 weekends
/// don't overlap, so at most one is expected; first match wins.)
Session? findLiveSession(List<Event> events, DateTime now) {
  for (final e in events) {
    for (final s in e.sessions) {
      if (isSessionLive(s, now)) return s;
    }
  }
  return null;
}
```

- [ ] **Step 4: Run tests, verify pass**

Run: `flutter test test/domain/live_session_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/domain/live_session.dart test/domain/live_session_test.dart
git commit -m "feat(domain): isSessionLive + findLiveSession"
```

---

### Task 8: `LiveSessionController`

**Files:**
- Create: `lib/state/live_session_controller.dart`
- Test: `test/state/live_session_controller_test.dart`

- [ ] **Step 1: Write the failing test** (`test/state/live_session_controller_test.dart`)

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/api_client.dart';
import 'package:predictiongame/api/models/event.dart';
import 'package:predictiongame/api/models/session.dart';
import 'package:predictiongame/api/models/live_snapshot.dart';
import 'package:predictiongame/state/live_session_controller.dart';

class _FakeApi implements ApiClient {
  int liveCalls = 0;
  int? lastId;
  String? lastLeague;
  LiveSnapshot reply = const LiveSnapshot(
      sessionId: 10, state: LiveState.live, order: [], myPointsTotal: 5, league: []);
  @override
  Future<LiveSnapshot> sessionLive(int id, {String? leagueId}) async {
    liveCalls += 1; lastId = id; lastLeague = leagueId; return reply;
  }
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Session _s(int id, SessionType type, DateTime start, DateTime end, SessionStatus status) =>
    Session(id: id, type: type, scheduledStart: start, scheduledEnd: end, status: status);

void main() {
  final now = DateTime.utc(2026, 6, 7, 13, 30);
  Event ev(Session s) => Event(round: 1, name: 'A', country: 'X', circuitName: 'c', hasSprint: false, sessions: [s]);

  test('update() detects the live session and refreshOnce() fetches it', () async {
    final api = _FakeApi();
    final c = LiveSessionController(api: api);
    c.update([ev(_s(10, SessionType.race, now.subtract(const Duration(hours: 1)), now.add(const Duration(hours: 1)), SessionStatus.scheduled))],
        now, leagueId: 'lg1', autoPoll: false);
    expect(c.liveSessionId, 10);
    await c.refreshOnce();
    expect(api.liveCalls, 1);
    expect(api.lastId, 10);
    expect(api.lastLeague, 'lg1');
    expect(c.snapshot?.myPointsTotal, 5);
    expect(c.isLiveFor(10), isTrue);
    expect(c.isLiveFor(99), isFalse);
  });

  test('update() with no live session clears state', () async {
    final api = _FakeApi();
    final c = LiveSessionController(api: api);
    c.update([ev(_s(10, SessionType.race, now.add(const Duration(hours: 1)), now.add(const Duration(hours: 2)), SessionStatus.scheduled))],
        now, leagueId: null, autoPoll: false);
    expect(c.liveSessionId, isNull);
    await c.refreshOnce();
    expect(api.liveCalls, 0);
    expect(c.snapshot, isNull);
  });
}
```

- [ ] **Step 2: Run it, verify it fails**

Run: `flutter test test/state/live_session_controller_test.dart`
Expected: FAIL — `live_session_controller.dart` missing.

- [ ] **Step 3: Implement** (`lib/state/live_session_controller.dart`)

```dart
import 'dart:async';
import 'package:flutter/widgets.dart';
import '../api/api_client.dart';
import '../api/models/event.dart';
import '../api/models/live_snapshot.dart';
import '../domain/live_session.dart';

/// Detects the single in-progress scorable session and polls `/live` for it
/// while the app is foregrounded. Home hero + results screen read this; neither
/// re-implements polling. Polling pauses on background and stops when no session
/// is live. [refreshOnce] is exposed for tests (no timer dependency).
class LiveSessionController extends ChangeNotifier with WidgetsBindingObserver {
  LiveSessionController({required this.api, this.pollInterval = const Duration(seconds: 20)}) {
    WidgetsBinding.instance.addObserver(this);
  }
  final ApiClient api;
  final Duration pollInterval;

  int? _liveSessionId;
  String? _leagueId;
  LiveSnapshot? _snapshot;
  Timer? _timer;
  bool _autoPoll = true;

  int? get liveSessionId => _liveSessionId;
  LiveSnapshot? get snapshot => _snapshot;
  bool isLiveFor(int sessionId) => _liveSessionId == sessionId;

  /// Recompute the live session from [events]; (re)start or stop polling.
  /// Call when home data loads and on login/league changes. [leagueId] enables
  /// league projections in the snapshot. [autoPoll] = false for tests.
  void update(List<Event> events, DateTime now, {String? leagueId, bool autoPoll = true}) {
    _autoPoll = autoPoll;
    _leagueId = leagueId;
    final live = findLiveSession(events, now);
    final newId = live?.id;
    if (newId == _liveSessionId) {
      if (newId != null && autoPoll) _ensureTimer();
      return;
    }
    _liveSessionId = newId;
    _snapshot = null;
    _timer?.cancel();
    _timer = null;
    notifyListeners();
    if (newId != null) {
      // ignore: discarded_futures
      refreshOnce();
      if (autoPoll) _ensureTimer();
    }
  }

  Future<void> refreshOnce() async {
    final id = _liveSessionId;
    if (id == null) return;
    try {
      final snap = await api.sessionLive(id, leagueId: _leagueId);
      if (id != _liveSessionId) return; // changed mid-flight
      _snapshot = snap;
      notifyListeners();
      if (snap.state == LiveState.finalised) {
        // Session got scored — stop; the next home refresh will drop it from "live".
        _timer?.cancel();
        _timer = null;
      }
    } catch (_) {
      // Best-effort; keep the previous snapshot, try again next tick.
    }
  }

  void _ensureTimer() {
    _timer ??= Timer.periodic(pollInterval, (_) {
      // ignore: discarded_futures
      refreshOnce();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_autoPoll) return;
    if (state == AppLifecycleState.resumed) {
      if (_liveSessionId != null) {
        // ignore: discarded_futures
        refreshOnce();
        _ensureTimer();
      }
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }
}
```

- [ ] **Step 4: Run tests, verify pass**

Run: `flutter test test/state/live_session_controller_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/state/live_session_controller.dart test/state/live_session_controller_test.dart
git commit -m "feat(state): LiveSessionController (detect + poll live session)"
```

---

## Phase 3 — Frontend wiring & UI

### Task 9: Wire `LiveSessionController` into AppState + main + home refresh

**Files:**
- Modify: `lib/state/app_state.dart`, `lib/main.dart`, `lib/state/home_cache_controller.dart`

- [ ] **Step 1: Add to AppState scope** — in `lib/state/app_state.dart`, add the field to both `AppState` and `_AppStateScope` (mirror `homeCache`):

In imports:
```dart
import 'live_session_controller.dart';
```
In `AppState` (fields + constructor) and `_AppStateScope` (fields + constructor) add:
```dart
  final LiveSessionController live;
```
and pass `live: widget.live` in `_AppStateState.build`'s `_AppStateScope(...)`.

- [ ] **Step 2: Construct + provide it** in `lib/main.dart` `_loadLate` (alongside `homeCache`, ~line 163), and pass to `F1PgApp`:

```dart
    final live = LiveSessionController(api: widget.api);
```
Add to the `_LateState` class + its constructor + the returned `_LateState(...)`, and pass `live: s.live` into `F1PgApp(...)`. Add the import:
```dart
import 'state/live_session_controller.dart';
```
Then thread `live` through `F1PgApp` → `AppState(live: ...)` (update `F1PgApp` in `lib/app.dart` to accept and forward it, mirroring `homeCache`).

- [ ] **Step 3: Drive `update()` from home data** — in `lib/state/home_cache_controller.dart`, after a successful `_fetch()` sets `_data`, call the live controller. Inject it via the constructor (mirror `predictions`):

Add field + ctor param:
```dart
  final LiveSessionController live;
```
(import `live_session_controller.dart`; pass it in `main.dart` where `HomeCacheController(...)` is built). At the end of `_doRefresh`'s success path (after `_data = await _fetch()`):
```dart
    live.update(_data!.events, DateTime.now(), leagueId: auth.leagues.isEmpty ? null : auth.leagues.first.id);
```

- [ ] **Step 4: Verify it compiles + existing tests pass**

Run: `flutter analyze && flutter test`
Expected: analyzer clean; existing suites green (constructors updated everywhere they're built — fix any test that constructs `AppState`/`HomeCacheController` to pass a `LiveSessionController`, e.g. `test/nav/router_gate_test.dart`).

- [ ] **Step 5: Commit**

```bash
git add lib/state/app_state.dart lib/main.dart lib/app.dart lib/state/home_cache_controller.dart test/
git commit -m "wire: LiveSessionController into AppState + home refresh"
```

---

### Task 10: Home hero — live card + suppress "next"

**Files:**
- Modify: `lib/screens/home_screen.dart`
- Test: `test/screens/home_live_hero_test.dart`

- [ ] **Step 1: Write the failing widget test** (`test/screens/home_live_hero_test.dart`)

Pump just the live hero widget with a snapshot (keeps the test focused; no full screen/AppState needed).

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/models/live_snapshot.dart';
import 'package:predictiongame/api/models/session_result.dart';
import 'package:predictiongame/screens/home_screen.dart' show LiveHeroCard;

void main() {
  testWidgets('LiveHeroCard shows LIVE, event/session, top order and my projected points', (tester) async {
    const snap = LiveSnapshot(
      sessionId: 5, state: LiveState.live, order: [
        SessionResult(position: 1, driverCode: 'VER', driverName: 'Max Verstappen', constructorId: 'red_bull', constructorName: 'Red Bull Racing'),
        SessionResult(position: 2, driverCode: 'LEC', driverName: 'Charles Leclerc', constructorId: 'ferrari', constructorName: 'Ferrari'),
      ], myPointsTotal: 8, league: []);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      LiveHeroCard(eventName: 'Spanish GP', sessionLabel: 'RACE', snap: snap, onTap: () {}))));
    expect(find.text('LIVE'), findsOneWidget);
    expect(find.textContaining('Spanish GP'), findsOneWidget);
    expect(find.text('VER'), findsOneWidget);
    expect(find.textContaining('8'), findsWidgets); // projected points shown
  });
}
```

- [ ] **Step 2: Run it, verify it fails**

Run: `flutter test test/screens/home_live_hero_test.dart`
Expected: FAIL — `LiveHeroCard` not exported / not defined.

- [ ] **Step 3: Implement `LiveHeroCard`** (add to `lib/screens/home_screen.dart`; make it a public top-level widget so the test can import it). Reuse `teamColor`, `AppText`, `AppCard`, `Spacing` already imported by the screen.

```dart
/// Compact live-session card shown on Home in place of the next/countdown hero
/// while a scorable session is in progress. Tapping opens the full live results.
class LiveHeroCard extends StatelessWidget {
  final String eventName;
  final String sessionLabel;
  final LiveSnapshot snap;
  final VoidCallback onTap;
  const LiveHeroCard({super.key, required this.eventName, required this.sessionLabel, required this.snap, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final top = snap.order.take(3).toList();
    final pts = snap.myPointsTotal;
    final badge = snap.state == LiveState.provisional ? 'PROVISIONAL' : 'LIVE';
    return InkWell(
      onTap: onTap,
      child: AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(width: 8, height: 8, decoration: const BoxDecoration(color: BrandColors.accent, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(badge, style: AppText.label(11, color: BrandColors.accent)),
            const SizedBox(width: 8),
            Expanded(child: Text('$eventName · $sessionLabel', overflow: TextOverflow.ellipsis, style: AppText.label(11, color: t.colorScheme.onSurface.withOpacity(0.6)))),
          ]),
          const SizedBox(height: Spacing.sm),
          for (final r in top)
            Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(children: [
              SizedBox(width: 18, child: Text('${r.position}', style: AppText.display(13))),
              Container(width: 3, height: 16, color: teamColor(r.constructorId)),
              const SizedBox(width: Spacing.sm),
              Text(r.driverCode, style: AppText.body(13, weight: FontWeight.w800)),
            ])),
          if (pts != null) ...[
            const SizedBox(height: Spacing.sm),
            Text('YOUR PROJECTED', style: AppText.label(9, color: t.colorScheme.onSurface.withOpacity(0.55))),
            Text('+$pts', style: AppText.display(22)),
          ],
        ]),
      ),
    );
  }
}
```

Add the import at the top of `home_screen.dart`:
```dart
import '../api/models/live_snapshot.dart';
```

- [ ] **Step 4: Swap the hero when live** — in `home_screen.dart` `build`, wrap the hero region in a `ListenableBuilder` on the live controller and branch. Replace the existing hero block (`if (d.next != null && d.nextEvent != null) _hero(...) else _noNextHero(t)`) with:

```dart
            ListenableBuilder(
              listenable: scope.live,
              builder: (_, __) {
                final live = scope.live;
                final snap = live.snapshot;
                if (live.liveSessionId != null && snap != null && snap.state != LiveState.finalised) {
                  final ev = d.events.firstWhere(
                    (e) => e.sessions.any((s) => s.id == live.liveSessionId),
                    orElse: () => d.nextEvent ?? d.events.first);
                  final sess = ev.sessions.firstWhere((s) => s.id == live.liveSessionId);
                  return LiveHeroCard(
                    eventName: ev.name,
                    sessionLabel: sess.type.name.toUpperCase(),
                    snap: snap,
                    onTap: () => context.go('/race/${ev.round}/${live.liveSessionId}'),
                  );
                }
                if (d.next != null && d.nextEvent != null) return _hero(_resolveHeroSession(d), d.nextEvent!, t);
                return _noNextHero(t);
              },
            ),
```

> `scope` is `AppState.of(context)` (already in `build`). Confirm the route path matches the results screen route (`/race/:round/:sessionId`, per `session_results_screen` nav).

- [ ] **Step 5: Run tests, verify pass**

Run: `flutter test test/screens/home_live_hero_test.dart && flutter analyze`
Expected: PASS; analyzer clean.

- [ ] **Step 6: Commit**

```bash
git add lib/screens/home_screen.dart test/screens/home_live_hero_test.dart
git commit -m "feat(home): live hero card replaces next-session while a session is live"
```

---

### Task 11: Results screen — live mode

**Files:**
- Modify: `lib/screens/session_results_screen.dart`
- Test: `test/screens/live_results_test.dart`

- [ ] **Step 1: Write the failing widget test** (`test/screens/live_results_test.dart`)

Pump the `_Body` via a small public test seam. Add a public builder `buildResultsBody(...)` OR make `_Body` constructible in tests by exposing a `@visibleForTesting` factory. Simplest: extract the live rendering into a public `LiveResultsBody` widget and test that.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/models/live_snapshot.dart';
import 'package:predictiongame/api/models/member_prediction.dart';
import 'package:predictiongame/api/models/session.dart';
import 'package:predictiongame/api/models/session_result.dart';
import 'package:predictiongame/screens/session_results_screen.dart' show LiveResultsBody;

void main() {
  testWidgets('LiveResultsBody shows projected score, colored order and league projections', (tester) async {
    final snap = LiveSnapshot(
      sessionId: 5, state: LiveState.live, order: const [
        SessionResult(position: 1, driverCode: 'VER', driverName: 'Max Verstappen', constructorId: 'red_bull', constructorName: 'Red Bull Racing'),
        SessionResult(position: 2, driverCode: 'LEC', driverName: 'Charles Leclerc', constructorId: 'ferrari', constructorName: 'Ferrari'),
      ],
      myPointsTotal: 8,
      league: const [ MemberPrediction(userId: 'u2', displayName: 'Lukas', picks: [], pointsTotal: 3) ]);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child:
      LiveResultsBody(sessionType: SessionType.race, myPicks: const ['VER','LEC','X','Y','Z'], snap: snap)))));
    expect(find.textContaining('PROJECTED'), findsWidgets);
    expect(find.text('+8'), findsOneWidget);
    expect(find.text('VER'), findsOneWidget);
    expect(find.textContaining('LIVE'), findsWidgets);
    expect(find.text('Lukas'.toUpperCase()), findsOneWidget);
  });
}
```

> Adjust `MemberPrediction`'s constructor args to its real shape.

- [ ] **Step 2: Run it, verify it fails**

Run: `flutter test test/screens/live_results_test.dart`
Expected: FAIL — `LiveResultsBody` not defined.

- [ ] **Step 3: Implement `LiveResultsBody`** (add to `session_results_screen.dart`, public). It reuses the existing row/ticket helpers — render the same colored rows from `snap.order` with `outcomeFor` tinting, a `YOUR SCORE · PROJECTED` ticket from `snap.myPointsTotal`, and league projections from `snap.league` sorted by `pointsTotal`. Reuse `_YourScoreTicket`, `_MemberPickTicket`, `_OutcomeTag`, `_PickSlotChip`, `teamColor`, `outcomeFor`, `requiredPicks`.

```dart
/// Live/provisional rendering of a session's results screen body. Mirrors the
/// finished-session layout but fed a live order + backend-projected points.
class LiveResultsBody extends StatelessWidget {
  final SessionType sessionType;
  final List<String> myPicks;
  final LiveSnapshot snap;
  const LiveResultsBody({super.key, required this.sessionType, required this.myPicks, required this.snap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final topN = requiredPicks(sessionType);
    final order = snap.order;
    final badge = snap.state == LiveState.provisional ? 'PROVISIONAL · OFFICIAL PENDING' : 'LIVE';
    final myPts = snap.myPointsTotal;
    final members = [...snap.league]..sort((a, b) => (b.pointsTotal ?? -1).compareTo(a.pointsTotal ?? -1));

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
        child: _YourScoreTicket(
          score: myPts ?? 0,
          subtitle: myPts == null ? 'No picks for this session' : 'projected · $badge',
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.lg, Spacing.lg, Spacing.xs),
        child: Row(children: [
          Container(width: 8, height: 8, decoration: const BoxDecoration(color: BrandColors.accent, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(badge, style: AppText.label(11, color: BrandColors.accent)),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
        child: AppCard(
          padding: EdgeInsets.zero,
          child: Column(children: order.map((r) {
            final slot = myPicks.indexOf(r.driverCode);
            final pickedSlot = slot == -1 ? null : slot + 1;
            final outcome = pickedSlot == null ? null : outcomeFor(r.driverCode, pickedSlot, order, topN);
            final mine = pickedSlot != null;
            final rowBg = !mine ? null : (outcome == PickOutcome.exact
                ? BrandColors.ok.withOpacity(0.18)
                : outcome == PickOutcome.inTopN ? BrandColors.near.withOpacity(0.22) : t.rowHighlight);
            return Container(
              color: rowBg,
              padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 7),
              child: Row(children: [
                SizedBox(width: 22, child: Text('${r.position}', style: AppText.display(13))),
                Container(width: 3, height: 18, color: teamColor(r.constructorId)),
                const SizedBox(width: Spacing.sm),
                SizedBox(width: 44, child: Text(r.driverCode, style: AppText.body(12, weight: FontWeight.w800))),
                Expanded(child: Text(r.driverName, style: AppText.body(12, weight: FontWeight.w500))),
                if (pickedSlot != null) ...[_PickSlotChip(slot: pickedSlot), const SizedBox(width: 6)],
                if (outcome != null) _OutcomeTag(outcome: outcome),
              ]),
            );
          }).toList()),
        ),
      ),
      if (members.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xs),
          child: Text('LEAGUE · PROJECTED', style: AppText.label(11, color: t.colorScheme.onSurface.withOpacity(0.6))),
        ),
        for (final m in members)
          Padding(
            padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.sm),
            child: _MemberPickTicket(member: m),
          ),
      ],
    ]);
  }
}
```

Add the import:
```dart
import '../api/models/live_snapshot.dart';
```

- [ ] **Step 4: Branch the screen to live mode** — in `_SessionResultsScreenState`, when the active session is the live one (read `AppState.of(context).live.isLiveFor(active.id)` and its `snapshot`), render `LiveResultsBody` instead of the `FutureBuilder<_SessionPayload>` block, wrapped in a `ListenableBuilder` on `scope.live` so it repaints each poll. Pass `myPicks` from `scope.predictions.prediction(active.id)?.picks` (codes). When `snapshot.state == LiveState.finalised` (or not live), fall through to the existing `FutureBuilder` path so the official results show.

Concretely, replace the `FutureBuilder<_SessionPayload>(future: _payloadFor(active.id), …)` child with:
```dart
                    ListenableBuilder(
                      listenable: AppState.of(context).live,
                      builder: (ctx, __) {
                        final live = AppState.of(ctx).live;
                        final snap = live.snapshot;
                        if (live.isLiveFor(active.id) && snap != null && snap.state != LiveState.finalised) {
                          final picks = AppState.of(ctx).predictions.prediction(active.id)?.picks
                              .map((p) => p.driverCode).toList() ?? const <String>[];
                          return LiveResultsBody(sessionType: active.type, myPicks: picks, snap: snap);
                        }
                        return FutureBuilder<_SessionPayload>(
                          future: _payloadFor(active.id),
                          builder: (_, payloadSnap) { /* existing body unchanged */ },
                        );
                      },
                    ),
```
Keep the existing `FutureBuilder` body verbatim inside the `else` path.

- [ ] **Step 5: Run tests, verify pass**

Run: `flutter test test/screens/live_results_test.dart && flutter analyze`
Expected: PASS; analyzer clean.

- [ ] **Step 6: Commit**

```bash
git add lib/screens/session_results_screen.dart test/screens/live_results_test.dart
git commit -m "feat(results): live mode (projected score + colored live order + league projections)"
```

---

### Task 12: Full suite + manual smoke

- [ ] **Step 1: Run everything**

Run: `flutter analyze && flutter test && make backend-test`
Expected: all green.

- [ ] **Step 2: Manual smoke (during a real session, or with a temporary fake)**

If no live session is available, temporarily point the live route at a recorded fixture (or run the spike's `curl` against a current session) and verify: Home swaps to the live card; tapping opens the results screen in live mode; projected points match a hand-computed value with the backend rules; after the crawler scores the session, both surfaces revert to official results and the next session returns as "next".

- [ ] **Step 3: Commit any fixes**

```bash
git add -A && git commit -m "test: live-ticker full-suite green + smoke fixes"
```

---

## Self-Review (completed against the spec)

- **Spec coverage:** infra prereq (done, out of plan); §5.2 endpoint → Task 4; §5.3 live predicate → Task 7; §5.4 controller → Task 8/9; §5.5 results live mode → Task 11; §5.6 home hero → Task 10; §5.7 states (`pre/live/provisional/final/unavailable`) → Tasks 4 & 11; §6 edges (empty order, quali approximate, no league, not-logged-in→401) → Tasks 4/5/11; §8 testing → unit+integration+widget tests per task; §9 spike → Task 0. Revision (server-side projection) → Tasks 3 & 4 (no client-side scoring used; row tint uses position-based `outcomeFor`, not point values).
- **Placeholder scan:** no TBD/TODO; every code step has concrete code. Two explicit "verify the real signature" notes (test seed helpers; `MemberPrediction.fromJson` keys) are integration checks, not placeholders — the code is provided.
- **Type consistency:** `scoreSession(type, Pick[], Finisher[])` → `projectTotal` (Task 3) → route (Task 4); `LiveSnapshot`/`LiveState` (Task 5) used identically in client (Task 6), controller (Task 8), home (Task 10), results (Task 11); `MemberPrediction` reused for `league`/`leagueProjected`; `SessionResult` reused for `order`. `LiveState.finalised` (Dart can't name it `final`) maps backend `"final"`.

## Known limitations (per spec, intentional)
- Qualifying/shootout live order uses OpenF1 `/position` (track position), which approximates the timing-screen classification — labeled provisional. Revisit with `/laps`-based best-lap ordering if needed (validated in Task 0).
- Single backend instance assumed for the in-memory needs; no server cache is added in this plan (on-demand fetch per request). If poll volume grows, add a ~10–15s TTL cache in `live.ts` keyed by `sessionId` (spec §5.2) — deferred until needed.
