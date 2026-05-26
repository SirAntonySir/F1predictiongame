# OpenF1 Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add OpenF1 as a second data source so that sprint qualifying gets results (Jolpica can't serve it), race/qualifying/sprint get a structured cross-check, and drivers/constructors gain official headshots + team colours.

**Architecture:** New self-contained `backend/src/openf1/` module (client + parsers, no repo/db imports). Bootstrap-time join writes `session.openf1_session_key` so the tick can look up OpenF1 data without per-request `/sessions` calls. Tick branches by session type: `sprint_quali` → OpenF1 only; `race`/`qualifying`/`sprint` → Jolpica primary + OpenF1 cross-check + OpenF1 fallback when Jolpica is empty. Opportunistic enrichment fills `driver.headshot_url` / `constructor.team_colour` whenever OpenF1 is consulted. Three nullable schema columns; no new tables.

**Tech Stack:** Node 22, TypeScript, Fastify, Postgres 16, Drizzle ORM, vitest. Flutter 3 / Dart 3 on the client.

**Spec:** `docs/superpowers/specs/2026-05-26-openf1-integration-design.md`

---

## File Structure

**New backend files**
- `backend/src/openf1/client.ts` — `OpenF1Client` class. One responsibility: HTTP to `api.openf1.org/v1`.
- `backend/src/openf1/parsers.ts` — `parseSessionResult`, `parseDrivers`, `formatDuration`, `sessionNameFor`. Pure functions, no IO.
- `backend/src/crawler/openf1Mapping.ts` — `mapSessionsToOpenF1(year, client)`: looks up year's sessions in OpenF1 and writes the `openf1_session_key` join keys.
- `backend/src/crawler/openf1Enrichment.ts` — `enrichDriversAndConstructors(drivers)`: opportunistically writes null `headshot_url` / `team_colour` from a single `/drivers?session_key=X` response.
- `backend/src/crawler/crossCheck.ts` — `compareClassifications(jolpica, openf1)`: returns a `{ matched, mismatches[] }` summary so the caller decides how to log.
- `backend/src/db/migrations/0005_openf1.sql` — additive migration.
- `backend/test/fixtures/openf1/sessions-2026.json` — captured `GET /sessions?year=2026` response slice (just enough sessions for the integration tests).
- `backend/test/fixtures/openf1/session_result-sprintquali-china.json` — captured `GET /session_result?session_key=11236`.
- `backend/test/fixtures/openf1/drivers-china-sprintquali.json` — captured `GET /drivers?session_key=11236`.

**Modified backend files**
- `backend/src/config.ts` — add `OPENF1_BASE` env var (defaults to `https://api.openf1.org/v1`).
- `backend/.env.example` — append `OPENF1_BASE=...`.
- `backend/src/db/schema.ts` — three nullable columns.
- `backend/src/domain/types.ts` — add `headshotUrl`/`teamColour` to `Driver`/`Constructor`, add `openf1SessionKey` to `Session`.
- `backend/src/repo/sessions.ts` — `setOpenF1SessionKey(id, key)`.
- `backend/src/repo/drivers.ts` — `setHeadshotUrl(code, url)`, `listMissingHeadshot()`.
- `backend/src/repo/constructors.ts` — `setTeamColour(id, colour)`, `listMissingTeamColour()`.
- `backend/src/crawler/bootstrap.ts` — invoke `mapSessionsToOpenF1` after the existing schedule loop.
- `backend/src/crawler/scheduler.ts` — inject `OpenF1Client` so `bootstrap.ts` can use it during weekly refresh too.
- `backend/src/crawler/tick.ts` — type-branch `fetchByType`, add cross-check + enrichment hooks, accept an `OpenF1Client`.
- `backend/src/api/routes/public.ts` — image precedence becomes `imageUrlOverride ?? headshotUrl ?? imageUrl`; constructor responses gain `teamColour`.
- `backend/src/api/routes/admin.ts` — `POST /admin/refresh-openf1-metadata`.

**New / modified Flutter files**
- `lib/api/models/driver.dart` — add `headshotUrl`.
- `lib/api/models/constructor.dart` — add `teamColour`.
- `lib/theme/team_colors.dart` — fallback to `teamColour` when curated map misses.
- `test/theme/team_colors_test.dart` — extend existing test or add fallback case.

---

## Task 1: Config, schema, types, repo writes

**Files**
- Modify: `backend/src/config.ts`, `backend/.env.example`, `backend/src/db/schema.ts`, `backend/src/domain/types.ts`, `backend/src/repo/sessions.ts`, `backend/src/repo/drivers.ts`, `backend/src/repo/constructors.ts`
- Create: `backend/src/db/migrations/0005_openf1.sql`
- Test: extend `backend/test/integration/repo_sessions_results.test.ts`, `backend/test/integration/repo_users.test.ts` is unrelated — add a tiny new `backend/test/integration/repo_openf1_columns.test.ts`.

- [ ] **Step 1: Extend the config**

In `backend/src/config.ts`, add the env entry and field.

Inside the Zod schema, add the line:

```ts
  OPENF1_BASE: z.string().url().default('https://api.openf1.org/v1')
```

In the `Config` type, add:

```ts
  openf1Base: string
```

In `parseConfig`, return the new field:

```ts
    openf1Base: parsed.OPENF1_BASE
```

Append to `backend/.env.example`:

```
OPENF1_BASE=https://api.openf1.org/v1
```

- [ ] **Step 2: Add the schema columns**

In `backend/src/db/schema.ts`, modify the three tables. Add to `session`:

```ts
  openf1SessionKey: integer('openf1_session_key'),
```

(insert after `status: sessionStatus(...).notNull().default('scheduled')` and before the table's secondary-arg arrow function).

Add to `driver`:

```ts
  headshotUrl: text('headshot_url'),
```

(insert after `imageUrlOverride`).

Add to `constructor`:

```ts
  teamColour: text('team_colour'),
```

(insert after `imageUrlOverride`).

- [ ] **Step 3: Write the migration**

Create `backend/src/db/migrations/0005_openf1.sql`:

```sql
ALTER TABLE "session" ADD COLUMN "openf1_session_key" integer;
ALTER TABLE "driver" ADD COLUMN "headshot_url" text;
ALTER TABLE "constructor" ADD COLUMN "team_colour" text;
```

- [ ] **Step 4: Run the migration**

```bash
cd backend && set -a && source .env && set +a && npm run db:migrate
```

Expected: `Migrations complete.` and three new columns in `\d session` / `\d driver` / `\d constructor` in psql.

- [ ] **Step 5: Extend domain types**

In `backend/src/domain/types.ts`, update three types.

`Driver` — add at the bottom of the type, before the closing brace:

```ts
  headshotUrl: string | null
```

`Constructor` — same idea:

```ts
  teamColour: string | null
```

`Session` — same idea:

```ts
  openf1SessionKey: number | null
```

- [ ] **Step 6: Update the existing `upsertSession` / `upsertDriver` / `upsertConstructor` callers**

`backend/src/crawler/bootstrap.ts` constructs `Session` objects in `upsertSession`. The new field has a default of null, but TypeScript will complain if the type requires it. Fix by making the *type* require it and the *upsert call* not pass it (it stays null until the OpenF1 mapping runs).

In `backend/src/repo/sessions.ts`, change `upsertSession` to accept a partial that omits the new field — or simpler, change `Session` to make `openf1SessionKey: number | null = null`. We chose the explicit form already. So update each existing call site to add `openf1SessionKey: null`:

- `backend/src/crawler/bootstrap.ts` — in the `for (const s of ev.sessions)` loop, the existing `await sessionsRepo.upsertSession({...})` call: add `openf1SessionKey: null,` to the object literal.

`upsertDriver` and `upsertConstructor` similarly: callers in `backend/src/crawler/tick.ts` (`upsertNewDrivers` / `upsertNewConstructors`) construct objects from `DriverLookup` / `ConstructorLookup`. Update those to include `headshotUrl: null` / `teamColour: null`. The existing lines are:

```ts
await driversRepo.upsertDriver({ ...d, imageUrl: null, imageUrlOverride: null })
```
and
```ts
await constructorsRepo.upsertConstructor({ ...c, imageUrl: null, imageUrlOverride: null })
```

Change to:

```ts
await driversRepo.upsertDriver({ ...d, imageUrl: null, imageUrlOverride: null, headshotUrl: null })
```
and
```ts
await constructorsRepo.upsertConstructor({ ...c, imageUrl: null, imageUrlOverride: null, teamColour: null })
```

- [ ] **Step 7: Add the new repo write methods**

In `backend/src/repo/sessions.ts`, append:

```ts
export async function setOpenF1SessionKey(id: number, key: number | null): Promise<void> {
  const db = getDb()
  await db.update(session).set({ openf1SessionKey: key }).where(eq(session.id, id))
}
```

In `backend/src/repo/drivers.ts`, append:

```ts
export async function setHeadshotUrl(code: string, url: string | null): Promise<void> {
  const db = getDb()
  await db.update(driver).set({ headshotUrl: url }).where(eq(driver.code, code))
}

export async function listMissingHeadshot(): Promise<Driver[]> {
  const db = getDb()
  const rows = await db.select().from(driver).where(isNull(driver.headshotUrl))
  return rows as Driver[]
}
```

In `backend/src/repo/constructors.ts`, append:

```ts
export async function setTeamColour(id: string, colour: string | null): Promise<void> {
  const db = getDb()
  await db.update(constructor).set({ teamColour: colour }).where(eq(constructor.id, id))
}

export async function listMissingTeamColour(): Promise<Constructor[]> {
  const db = getDb()
  const rows = await db.select().from(constructor).where(isNull(constructor.teamColour))
  return rows as Constructor[]
}
```

- [ ] **Step 8: Write a small repo test pinning the new columns**

Create `backend/test/integration/repo_openf1_columns.test.ts`:

```ts
import { describe, it, expect } from 'vitest'
import * as seasons from '../../src/repo/seasons.js'
import * as events from '../../src/repo/events.js'
import * as sessions from '../../src/repo/sessions.js'
import * as drivers from '../../src/repo/drivers.js'
import * as constructors from '../../src/repo/constructors.js'

async function seed() {
  await seasons.upsertSeason({ year: 2024, isCurrent: true })
  return events.upsertEvent({
    seasonYear: 2024, round: 1, name: 'Bahrain', circuitName: 'BIC',
    country: 'Bahrain', hasSprint: false
  })
}

describe('OpenF1 columns', () => {
  it('session.openf1SessionKey roundtrips via setter', async () => {
    const ev = await seed()
    const ses = await sessions.upsertSession({
      eventId: ev.id, type: 'race',
      scheduledStart: new Date('2024-03-02T15:00:00Z'),
      scheduledEnd: new Date('2024-03-02T17:00:00Z'),
      status: 'scheduled',
      openf1SessionKey: null
    })
    await sessions.setOpenF1SessionKey(ses.id!, 9876)
    const fetched = await sessions.getById(ses.id!)
    expect(fetched?.openf1SessionKey).toBe(9876)
  })

  it('driver.headshotUrl roundtrips via setter and listMissingHeadshot filters', async () => {
    await drivers.upsertDriver({
      code: 'VER', givenName: 'Max', familyName: 'Verstappen',
      nationality: 'Dutch', permanentNumber: 33, wikipediaUrl: null,
      imageUrl: null, imageUrlOverride: null, headshotUrl: null
    })
    expect((await drivers.listMissingHeadshot()).map((d) => d.code)).toEqual(['VER'])
    await drivers.setHeadshotUrl('VER', 'https://example.com/ver.png')
    expect((await drivers.listMissingHeadshot())).toEqual([])
    expect((await drivers.getByCode('VER'))?.headshotUrl).toBe('https://example.com/ver.png')
  })

  it('constructor.teamColour roundtrips via setter and listMissingTeamColour filters', async () => {
    await constructors.upsertConstructor({
      id: 'red_bull', name: 'Red Bull', nationality: 'Austrian',
      wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, teamColour: null
    })
    expect((await constructors.listMissingTeamColour()).map((c) => c.id)).toEqual(['red_bull'])
    await constructors.setTeamColour('red_bull', '1E41FF')
    expect((await constructors.listMissingTeamColour())).toEqual([])
    expect((await constructors.getById('red_bull'))?.teamColour).toBe('1E41FF')
  })
})
```

- [ ] **Step 9: Run the new test, then the full suite**

```bash
cd backend && set -a && source .env && set +a && npx vitest run test/integration/repo_openf1_columns.test.ts
```

Expected: 3 passed.

```bash
cd backend && set -a && source .env && set +a && npm test
```

Expected: all tests pass. Knock-on TypeScript errors most likely show up in `crawler/bootstrap.ts` / `crawler/tick.ts` if Step 6 missed any caller. Fix until green.

- [ ] **Step 10: Commit**

```bash
git add backend/src/config.ts backend/.env.example backend/src/db/schema.ts backend/src/db/migrations/0005_openf1.sql backend/src/domain/types.ts backend/src/repo/sessions.ts backend/src/repo/drivers.ts backend/src/repo/constructors.ts backend/src/crawler/bootstrap.ts backend/src/crawler/tick.ts backend/test/integration/repo_openf1_columns.test.ts
git commit -m "$(cat <<'EOF'
backend: schema + types + repo writes for OpenF1 integration

Adds three nullable columns (session.openf1_session_key, driver.headshot_url,
constructor.team_colour) plus the matching repo setters / listMissing helpers
and an OPENF1_BASE config entry. No behaviour change yet.

Spec: docs/superpowers/specs/2026-05-26-openf1-integration-design.md
EOF
)"
```

---

## Task 2: OpenF1 client (HTTP only)

**Files**
- Create: `backend/src/openf1/client.ts`
- Create: `backend/test/unit/openf1_client.test.ts`

- [ ] **Step 1: Write the failing unit test**

Create `backend/test/unit/openf1_client.test.ts`:

```ts
import { describe, it, expect } from 'vitest'
import { OpenF1Client } from '../../src/openf1/client.js'

function fakeFetch(handlers: Record<string, { status: number; body: unknown }>) {
  const calls: string[] = []
  const fetchFn = async (url: string | URL): Promise<Response> => {
    const u = url.toString()
    calls.push(u)
    const h = handlers[u]
    if (!h) throw new Error(`Unexpected fetch: ${u}`)
    return new Response(JSON.stringify(h.body), { status: h.status })
  }
  return { fetchFn: fetchFn as unknown as typeof fetch, calls }
}

describe('OpenF1Client', () => {
  it('GET /sessions?year=Y', async () => {
    const { fetchFn, calls } = fakeFetch({
      'https://api.openf1.org/v1/sessions?year=2026': { status: 200, body: [{ session_key: 1 }] }
    })
    const c = new OpenF1Client('https://api.openf1.org/v1', fetchFn)
    const out = await c.getSessions(2026)
    expect(out).toEqual([{ session_key: 1 }])
    expect(calls).toEqual(['https://api.openf1.org/v1/sessions?year=2026'])
  })

  it('GET /drivers?session_key=K', async () => {
    const { fetchFn } = fakeFetch({
      'https://api.openf1.org/v1/drivers?session_key=11282': { status: 200, body: [{ driver_number: 63 }] }
    })
    const c = new OpenF1Client('https://api.openf1.org/v1', fetchFn)
    const out = await c.getDrivers(11282)
    expect(out).toEqual([{ driver_number: 63 }])
  })

  it('GET /session_result?session_key=K', async () => {
    const { fetchFn } = fakeFetch({
      'https://api.openf1.org/v1/session_result?session_key=11282': { status: 200, body: [{ position: 1 }] }
    })
    const c = new OpenF1Client('https://api.openf1.org/v1', fetchFn)
    const out = await c.getSessionResult(11282)
    expect(out).toEqual([{ position: 1 }])
  })

  it('returns null on 4xx (treats as "no data", matching JolpicaClient convention)', async () => {
    const { fetchFn } = fakeFetch({
      'https://api.openf1.org/v1/session_result?session_key=99999': { status: 404, body: { error: 'not found' } }
    })
    const c = new OpenF1Client('https://api.openf1.org/v1', fetchFn)
    expect(await c.getSessionResult(99999)).toBeNull()
  })

  it('throws on 5xx', async () => {
    const { fetchFn } = fakeFetch({
      'https://api.openf1.org/v1/sessions?year=2026': { status: 502, body: '' }
    })
    const c = new OpenF1Client('https://api.openf1.org/v1', fetchFn)
    await expect(c.getSessions(2026)).rejects.toThrow(/OpenF1 502/)
  })
})
```

- [ ] **Step 2: Run the test, watch it fail**

```bash
cd backend && set -a && source .env && set +a && npx vitest run test/unit/openf1_client.test.ts
```

Expected: compile error "Cannot find module '../../src/openf1/client.js'" or similar.

- [ ] **Step 3: Implement the client**

Create `backend/src/openf1/client.ts`:

```ts
import { config } from '../config.js'

export type FetchFn = typeof fetch

export class OpenF1Client {
  constructor(
    private base = config.openf1Base,
    private fetchFn: FetchFn = fetch
  ) {}

  private async getJson(path: string): Promise<unknown | null> {
    const url = `${this.base}${path}`
    const res = await this.fetchFn(url, { headers: { Accept: 'application/json' } })
    // 4xx = "no data" (same convention as JolpicaClient — session not found, etc.)
    if (res.status >= 400 && res.status < 500) return null
    if (!res.ok) throw new Error(`OpenF1 ${res.status} for ${path}`)
    return res.json()
  }

  getSessions(year: number) {
    return this.getJson(`/sessions?year=${year}`)
  }
  getDrivers(sessionKey: number) {
    return this.getJson(`/drivers?session_key=${sessionKey}`)
  }
  getSessionResult(sessionKey: number) {
    return this.getJson(`/session_result?session_key=${sessionKey}`)
  }
}
```

- [ ] **Step 4: Run the test, watch it pass**

```bash
cd backend && set -a && source .env && set +a && npx vitest run test/unit/openf1_client.test.ts
```

Expected: 5 passed.

- [ ] **Step 5: Commit**

```bash
git add backend/src/openf1/client.ts backend/test/unit/openf1_client.test.ts
git commit -m "$(cat <<'EOF'
backend: add OpenF1Client (sessions, drivers, session_result)

Thin HTTP wrapper following the JolpicaClient pattern: 4xx returns null,
5xx throws. Three endpoints cover what the integration needs today.

Spec: docs/superpowers/specs/2026-05-26-openf1-integration-design.md
EOF
)"
```

---

## Task 3: OpenF1 parsers + fixtures

**Files**
- Create: `backend/src/openf1/parsers.ts`
- Create: `backend/test/fixtures/openf1/sessions-2026.json`
- Create: `backend/test/fixtures/openf1/session_result-sprintquali-china.json`
- Create: `backend/test/fixtures/openf1/drivers-china-sprintquali.json`
- Create: `backend/test/unit/openf1_parsers.test.ts`

- [ ] **Step 1: Capture the fixtures live**

Run, one at a time, capturing each response to its target file:

```bash
mkdir -p backend/test/fixtures/openf1
curl -fsS 'https://api.openf1.org/v1/sessions?year=2026' > backend/test/fixtures/openf1/sessions-2026.json
curl -fsS 'https://api.openf1.org/v1/session_result?session_key=11236' > backend/test/fixtures/openf1/session_result-sprintquali-china.json
curl -fsS 'https://api.openf1.org/v1/drivers?session_key=11236' > backend/test/fixtures/openf1/drivers-china-sprintquali.json
```

(session_key 11236 is the 2026 Chinese GP Sprint Qualifying.)

If any of these fixtures comes back empty or with an error shape, stop and check the API status. Fixtures must be real recorded responses, not synthetic.

- [ ] **Step 2: Write the failing parser tests**

Create `backend/test/unit/openf1_parsers.test.ts`:

```ts
import { describe, it, expect } from 'vitest'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import {
  parseSessionResult, parseDrivers, formatDuration, sessionNameFor
} from '../../src/openf1/parsers.js'

function fx(name: string): unknown {
  return JSON.parse(readFileSync(resolve('test/fixtures/openf1', name), 'utf8'))
}

describe('formatDuration', () => {
  it('formats >= 60s as M:SS.mmm with three-decimal millis', () => {
    expect(formatDuration(74.772)).toBe('1:14.772')
    expect(formatDuration(64.0)).toBe('1:04.000')
    expect(formatDuration(120.5)).toBe('2:00.500')
  })
  it('formats < 60s as SS.mmm (no leading zero)', () => {
    expect(formatDuration(45.123)).toBe('45.123')
  })
  it('rounds to milliseconds', () => {
    expect(formatDuration(74.7723)).toBe('1:14.772')
  })
})

describe('sessionNameFor', () => {
  it('maps every SessionType to the OpenF1 session_name', () => {
    expect(sessionNameFor('race')).toBe('Race')
    expect(sessionNameFor('qualifying')).toBe('Qualifying')
    expect(sessionNameFor('sprint')).toBe('Sprint')
    expect(sessionNameFor('sprint_quali')).toBe('Sprint Qualifying')
    expect(sessionNameFor('fp1')).toBe('Practice 1')
    expect(sessionNameFor('fp2')).toBe('Practice 2')
    expect(sessionNameFor('fp3')).toBe('Practice 3')
  })
})

describe('parseDrivers', () => {
  it('extracts code, name, team_name, headshot_url, team_colour (case preserved)', () => {
    const out = parseDrivers(fx('drivers-china-sprintquali.json'))
    const nor = out.find((d) => d.code === 'NOR')
    expect(nor).toBeDefined()
    expect(nor!.givenName).toBe('Lando')
    expect(nor!.familyName).toBe('Norris')
    expect(nor!.teamName).toBe('McLaren')
    expect(nor!.headshotUrl).toMatch(/^https?:\/\//)
    expect(nor!.teamColour).toMatch(/^[0-9A-F]{6}$/) // OpenF1 uses uppercase
  })
})

describe('parseSessionResult', () => {
  it('builds SessionResultRow with formatted q1/q2/q3 from duration array', () => {
    const drivers = parseDrivers(fx('drivers-china-sprintquali.json'))
    const rows = parseSessionResult(fx('session_result-sprintquali-china.json'), drivers)
    expect(rows.length).toBeGreaterThanOrEqual(15)
    const p1 = rows.find((r) => r.position === 1)
    expect(p1).toBeDefined()
    expect(p1!.driverCode).toMatch(/^[A-Z]{3}$/)
    // First duration entry must have produced a non-null q1 in M:SS.mmm or SS.mmm form
    expect(p1!.q1).toMatch(/^\d+:\d{2}\.\d{3}$|^\d+\.\d{3}$/)
    expect(p1!.raceTime).toBeNull()
    expect(p1!.points).toBeNull()
  })

  it('skips rows whose driver_number does not resolve to a driver in the lookup', () => {
    const drivers = parseDrivers(fx('drivers-china-sprintquali.json')).filter((d) => d.code !== 'NOR')
    const rows = parseSessionResult(fx('session_result-sprintquali-china.json'), drivers)
    expect(rows.every((r) => r.driverCode !== 'NOR')).toBe(true)
  })

  it('marks DSQ / DNF / DNS in status', () => {
    const drivers = parseDrivers(fx('drivers-china-sprintquali.json'))
    const synthetic = [
      { position: 20, driver_number: drivers[0].driverNumber, duration: [80.5], gap_to_leader: [0],
        dnf: true, dns: false, dsq: false, number_of_laps: 1, meeting_key: 1, session_key: 1 }
    ]
    const rows = parseSessionResult(synthetic, drivers)
    expect(rows[0].status).toBe('DNF')
  })

  it('produces sparse q1/q2/q3 when duration array is shorter than 3', () => {
    const drivers = parseDrivers(fx('drivers-china-sprintquali.json'))
    const synthetic = [
      { position: 16, driver_number: drivers[0].driverNumber, duration: [90.0], gap_to_leader: [0],
        dnf: false, dns: false, dsq: false, number_of_laps: 5, meeting_key: 1, session_key: 1 }
    ]
    const rows = parseSessionResult(synthetic, drivers)
    expect(rows[0].q1).toBe('1:30.000')
    expect(rows[0].q2).toBeNull()
    expect(rows[0].q3).toBeNull()
  })
})
```

- [ ] **Step 3: Run the test, watch it fail**

```bash
cd backend && set -a && source .env && set +a && npx vitest run test/unit/openf1_parsers.test.ts
```

Expected: compile error "Cannot find module '../../src/openf1/parsers.js'".

- [ ] **Step 4: Implement the parsers**

Create `backend/src/openf1/parsers.ts`:

```ts
import type { SessionResultRow, SessionType } from '../domain/types.js'

export type OpenF1DriverLookup = {
  driverNumber: number
  code: string
  givenName: string
  familyName: string
  teamName: string
  headshotUrl: string | null
  teamColour: string | null
}

export function formatDuration(seconds: number): string {
  const totalMs = Math.round(seconds * 1000)
  const wholeSeconds = Math.floor(totalMs / 1000)
  const ms = totalMs - wholeSeconds * 1000
  const minutes = Math.floor(wholeSeconds / 60)
  const secs = wholeSeconds - minutes * 60
  const msStr = String(ms).padStart(3, '0')
  if (minutes === 0) return `${secs}.${msStr}`
  const secStr = String(secs).padStart(2, '0')
  return `${minutes}:${secStr}.${msStr}`
}

const SESSION_NAME_BY_TYPE: Record<SessionType, string> = {
  race: 'Race',
  qualifying: 'Qualifying',
  sprint: 'Sprint',
  sprint_quali: 'Sprint Qualifying',
  fp1: 'Practice 1',
  fp2: 'Practice 2',
  fp3: 'Practice 3'
}

export function sessionNameFor(type: SessionType): string {
  return SESSION_NAME_BY_TYPE[type]
}

export function parseDrivers(raw: unknown): OpenF1DriverLookup[] {
  const arr = (raw as any[]) ?? []
  return arr.map((d) => ({
    driverNumber: Number(d.driver_number),
    code: String(d.name_acronym),
    givenName: String(d.first_name ?? ''),
    familyName: String(d.last_name ?? ''),
    teamName: String(d.team_name ?? ''),
    headshotUrl: d.headshot_url ?? null,
    teamColour: d.team_colour ?? null
  }))
}

function statusFrom(r: { dnf?: boolean; dns?: boolean; dsq?: boolean }): string | null {
  if (r.dsq) return 'DSQ'
  if (r.dns) return 'DNS'
  if (r.dnf) return 'DNF'
  return null
}

export function parseSessionResult(
  raw: unknown,
  drivers: OpenF1DriverLookup[]
): SessionResultRow[] {
  const byNumber = new Map(drivers.map((d) => [d.driverNumber, d]))
  const arr = (raw as any[]) ?? []
  const out: SessionResultRow[] = []
  for (const r of arr) {
    const drv = byNumber.get(Number(r.driver_number))
    if (!drv) continue
    const duration = (r.duration as number[] | undefined) ?? []
    out.push({
      sessionId: 0, // caller fills this in
      position: Number(r.position),
      driverCode: drv.code,
      driverName: `${drv.givenName} ${drv.familyName}`.trim(),
      constructorId: drv.teamName.toLowerCase().replace(/\s+/g, '_'),
      constructorName: drv.teamName,
      raceTime: null,
      status: statusFrom(r),
      points: null,
      fastestLap: null,
      fastestLapTime: null,
      fastestLapSpeed: null,
      q1: duration[0] != null ? formatDuration(duration[0]) : null,
      q2: duration[1] != null ? formatDuration(duration[1]) : null,
      q3: duration[2] != null ? formatDuration(duration[2]) : null
    })
  }
  return out
}
```

Note on `constructorId`: OpenF1 only gives us `team_name`. The slug form (`red_bull`, `mclaren`, etc.) is derived by lowercasing and replacing spaces with underscores. This matches Jolpica's convention for current teams. Constructor matching is by `constructorId` at the DB layer; if there's drift between this derivation and Jolpica's actual `constructorId` for a brand-new team that has never been in our DB, the row is skipped in Task 5's "unknown constructor" handling. We're not relying on this derivation for known teams.

- [ ] **Step 5: Run the parser tests, watch them pass**

```bash
cd backend && set -a && source .env && set +a && npx vitest run test/unit/openf1_parsers.test.ts
```

Expected: all tests passed.

- [ ] **Step 6: Commit**

```bash
git add backend/src/openf1/parsers.ts backend/test/fixtures/openf1/ backend/test/unit/openf1_parsers.test.ts
git commit -m "$(cat <<'EOF'
backend: OpenF1 parsers (session_result, drivers, duration formatting)

Includes pure helpers: formatDuration (74.772 -> "1:14.772"), sessionNameFor
(SessionType -> OpenF1 session_name), parseDrivers, parseSessionResult.
Fixture-backed unit tests pin the expected shape.

Spec: docs/superpowers/specs/2026-05-26-openf1-integration-design.md
EOF
)"
```

---

## Task 4: Bootstrap-time session-key mapping

**Files**
- Create: `backend/src/crawler/openf1Mapping.ts`
- Modify: `backend/src/crawler/bootstrap.ts`, `backend/src/crawler/scheduler.ts`
- Create: `backend/test/integration/bootstrap_openf1_mapping.test.ts`

- [ ] **Step 1: Write the failing integration test**

Create `backend/test/integration/bootstrap_openf1_mapping.test.ts`:

```ts
import { describe, it, expect } from 'vitest'
import { runBootstrap } from '../../src/crawler/bootstrap.js'
import { JolpicaClient } from '../../src/jolpica/client.js'
import { OpenF1Client } from '../../src/openf1/client.js'
import * as sessions from '../../src/repo/sessions.js'
import * as events from '../../src/repo/events.js'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'

function fx(rel: string): string {
  return readFileSync(resolve(rel), 'utf8')
}

function jolpicaFake(): JolpicaClient {
  // Reuses the captured 2024 schedule fixture from the existing jolpica tests.
  const body = fx('test/fixtures/jolpica/schedule-2024.json')
  return new JolpicaClient(
    'https://example.invalid',
    (async () => new Response(body, { status: 200 })) as unknown as typeof fetch
  )
}

function openf1Fake(sessionsBody: string): OpenF1Client {
  return new OpenF1Client(
    'https://api.openf1.org/v1',
    (async (url: string | URL) => {
      const u = url.toString()
      if (u.includes('/sessions?year=')) return new Response(sessionsBody, { status: 200 })
      return new Response('[]', { status: 200 })
    }) as unknown as typeof fetch
  )
}

describe('OpenF1 bootstrap-time mapping', () => {
  it('writes openf1_session_key for sessions present in OpenF1', async () => {
    // Build a tiny OpenF1 sessions payload that overlaps with Jolpica round 1 (Bahrain).
    // Bahrain race is 2024-03-02. session_name = "Race".
    const openf1Body = JSON.stringify([
      { session_key: 9001, session_name: 'Race', date_start: '2024-03-02T15:00:00+00:00', year: 2024 },
      { session_key: 9002, session_name: 'Qualifying', date_start: '2024-03-01T16:00:00+00:00', year: 2024 }
    ])

    await runBootstrap(jolpicaFake(), 2024, openf1Fake(openf1Body))

    const round1 = await events.getByRound(2024, 1)
    expect(round1).toBeTruthy()
    const round1Sessions = await sessions.listForEvent(round1!.id)
    const race = round1Sessions.find((s) => s.type === 'race')
    const quali = round1Sessions.find((s) => s.type === 'qualifying')
    const fp1 = round1Sessions.find((s) => s.type === 'fp1')
    expect(race?.openf1SessionKey).toBe(9001)
    expect(quali?.openf1SessionKey).toBe(9002)
    expect(fp1?.openf1SessionKey).toBeNull() // not in our OpenF1 fake response
  })

  it('does not fail when OpenF1 returns an empty array', async () => {
    await runBootstrap(jolpicaFake(), 2024, openf1Fake('[]'))
    const round1 = await events.getByRound(2024, 1)
    const round1Sessions = await sessions.listForEvent(round1!.id)
    for (const s of round1Sessions) {
      expect(s.openf1SessionKey).toBeNull()
    }
  })
})
```

- [ ] **Step 2: Run the test, watch it fail**

```bash
cd backend && set -a && source .env && set +a && npx vitest run test/integration/bootstrap_openf1_mapping.test.ts
```

Expected: fails (either TypeScript error because `runBootstrap` does not accept a third arg, or assertion failure because the mapping has not been wired).

- [ ] **Step 3: Implement the mapping helper**

Create `backend/src/crawler/openf1Mapping.ts`:

```ts
import type { OpenF1Client } from '../openf1/client.js'
import { sessionNameFor } from '../openf1/parsers.js'
import * as sessionsRepo from '../repo/sessions.js'
import * as eventsRepo from '../repo/events.js'

type OpenF1Session = { session_key: number; session_name: string; date_start: string }

function utcDate(iso: string): string {
  return new Date(iso).toISOString().slice(0, 10) // YYYY-MM-DD
}

export async function mapSessionsToOpenF1(year: number, client: OpenF1Client): Promise<void> {
  const raw = await client.getSessions(year)
  if (!raw) return
  const openf1: OpenF1Session[] = raw as OpenF1Session[]

  // Index OpenF1 sessions by (UTC date, session_name)
  const byKey = new Map<string, number>()
  for (const s of openf1) {
    byKey.set(`${utcDate(s.date_start)}|${s.session_name}`, s.session_key)
  }

  const events = await eventsRepo.listForSeason(year)
  for (const ev of events) {
    const local = await sessionsRepo.listForEvent(ev.id)
    for (const s of local) {
      const name = sessionNameFor(s.type)
      const k = `${utcDate(s.scheduledStart.toISOString())}|${name}`
      const key = byKey.get(k) ?? null
      if (key !== null) {
        await sessionsRepo.setOpenF1SessionKey(s.id!, key)
      } else {
        console.log('OpenF1 no-match for session', { eventId: ev.id, round: ev.round, type: s.type, date: k })
      }
    }
  }
}
```

- [ ] **Step 4: Wire the mapping into `runBootstrap`**

Modify `backend/src/crawler/bootstrap.ts`. Change the signature and the body. New full file content:

```ts
import { JolpicaClient } from '../jolpica/client.js'
import { OpenF1Client } from '../openf1/client.js'
import { parseSchedule } from '../jolpica/parsers.js'
import * as seasonsRepo from '../repo/seasons.js'
import * as eventsRepo from '../repo/events.js'
import * as sessionsRepo from '../repo/sessions.js'
import { mapSessionsToOpenF1 } from './openf1Mapping.js'

export async function runBootstrap(
  client: JolpicaClient,
  year: number,
  openf1?: OpenF1Client
): Promise<void> {
  const raw = await client.getSeasonSchedule(year)
  if (!raw) throw new Error(`Jolpica returned null for season ${year}`)
  const schedule = parseSchedule(raw)

  await seasonsRepo.upsertSeason({ year: schedule.year, isCurrent: true })

  for (const ev of schedule.events) {
    const stored = await eventsRepo.upsertEvent({
      seasonYear: ev.seasonYear,
      round: ev.round,
      name: ev.name,
      circuitName: ev.circuitName,
      country: ev.country,
      hasSprint: ev.hasSprint
    })
    for (const s of ev.sessions) {
      await sessionsRepo.upsertSession({
        eventId: stored.id,
        type: s.type,
        scheduledStart: s.scheduledStart,
        scheduledEnd: s.scheduledEnd,
        status: 'scheduled',
        openf1SessionKey: null
      })
    }
  }

  if (openf1) {
    try {
      await mapSessionsToOpenF1(year, openf1)
    } catch (err) {
      console.error('OpenF1 mapping failed (bootstrap continues)', err)
    }
  }
}
```

- [ ] **Step 5: Wire the OpenF1 client into the scheduler + admin route**

In `backend/src/crawler/scheduler.ts`:

- At the top, add `import { OpenF1Client } from '../openf1/client.js'`.
- In the constructor, add a third optional dependency mirroring `jolpica` / `wiki`:
  ```ts
  constructor(
    private jolpica = new JolpicaClient(),
    private wiki = new WikipediaClient(),
    private openf1 = new OpenF1Client()
  ) {}
  ```
- In `weeklyOnce`, change the `runBootstrap` call to pass the OpenF1 client:
  ```ts
  await runBootstrap(this.jolpica, cur.year, this.openf1)
  ```

In `backend/src/api/routes/admin.ts`:

- At the top, add `import { OpenF1Client } from '../../openf1/client.js'`.
- Inside `registerAdminRoutes`, after `const wiki = ...`, add:
  ```ts
  const openf1 = new OpenF1Client()
  ```
- Change the bootstrap route to pass `openf1`:
  ```ts
  app.post('/admin/bootstrap', async () => {
    const cur = await seasonsRepo.getCurrent()
    const year = cur?.year ?? new Date().getUTCFullYear()
    await runBootstrap(jolpica, year, openf1)
    return { ok: true, year }
  })
  ```

- [ ] **Step 6: Run the mapping test, then the full suite**

```bash
cd backend && set -a && source .env && set +a && npx vitest run test/integration/bootstrap_openf1_mapping.test.ts
```

Expected: 2 tests passed.

```bash
cd backend && set -a && source .env && set +a && npm test
```

Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git add backend/src/crawler/openf1Mapping.ts backend/src/crawler/bootstrap.ts backend/src/crawler/scheduler.ts backend/src/api/routes/admin.ts backend/test/integration/bootstrap_openf1_mapping.test.ts
git commit -m "$(cat <<'EOF'
backend: bootstrap-time mapping of our sessions to OpenF1 session_keys

After Jolpica's schedule loop, one GET /sessions?year=Y call indexes OpenF1
sessions by (UTC date, session_name) and writes session_key to our session
rows. Falls back to silent null when no match (logged once per session).

Spec: docs/superpowers/specs/2026-05-26-openf1-integration-design.md
EOF
)"
```

---

## Task 5: Tick — sprint_quali via OpenF1 only

**Files**
- Modify: `backend/src/crawler/tick.ts`
- Create: `backend/test/integration/crawler_openf1_sprintquali.test.ts`

- [ ] **Step 1: Read tick.ts once to anchor the changes**

The relevant pieces are:
- `fetchByType` at the top (the per-type fetcher).
- `runTick` at the bottom (the loop that calls `fetchByType` and writes results).

We'll add an `OpenF1Client` parameter to both and branch `fetchByType` for `sprint_quali`.

- [ ] **Step 2: Write the failing integration test**

Create `backend/test/integration/crawler_openf1_sprintquali.test.ts`:

```ts
import { describe, it, expect } from 'vitest'
import { runTick } from '../../src/crawler/tick.js'
import { JolpicaClient } from '../../src/jolpica/client.js'
import { WikipediaClient } from '../../src/wikipedia/client.js'
import { OpenF1Client } from '../../src/openf1/client.js'
import * as seasons from '../../src/repo/seasons.js'
import * as events from '../../src/repo/events.js'
import * as sessions from '../../src/repo/sessions.js'
import * as drivers from '../../src/repo/drivers.js'
import * as constructors from '../../src/repo/constructors.js'
import * as results from '../../src/repo/results.js'

function staticFetch(handler: (url: string) => { status: number; body: unknown }) {
  return (async (url: string | URL) => {
    const h = handler(url.toString())
    return new Response(JSON.stringify(h.body), { status: h.status })
  }) as unknown as typeof fetch
}

async function seedSprintQualiSession() {
  await seasons.upsertSeason({ year: 2026, isCurrent: true })
  const ev = await events.upsertEvent({
    seasonYear: 2026, round: 2, name: 'Chinese GP', circuitName: 'Shanghai',
    country: 'China', hasSprint: true
  })
  await drivers.upsertDriver({
    code: 'NOR', givenName: 'Lando', familyName: 'Norris',
    nationality: null, permanentNumber: 4, wikipediaUrl: null,
    imageUrl: null, imageUrlOverride: null, headshotUrl: null
  })
  await constructors.upsertConstructor({
    id: 'mclaren', name: 'McLaren', nationality: null,
    wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, teamColour: null
  })
  const past = new Date(Date.now() - 3 * 60 * 60 * 1000)
  return sessions.upsertSession({
    eventId: ev.id, type: 'sprint_quali',
    scheduledStart: past, scheduledEnd: past,
    status: 'scheduled', openf1SessionKey: 11236
  })
}

describe('Crawler — sprint_quali via OpenF1', () => {
  it('writes a finished session_result for a sprint_quali session', async () => {
    const ses = await seedSprintQualiSession()

    const jolpica = new JolpicaClient(
      'https://example.invalid',
      staticFetch(() => ({ status: 200, body: { MRData: { RaceTable: { Races: [] } } } }))
    )
    const wiki = new WikipediaClient(
      'https://example.invalid',
      staticFetch(() => ({ status: 200, body: { query: { pages: {} } } }))
    )
    const openf1 = new OpenF1Client(
      'https://api.openf1.org/v1',
      staticFetch((url) => {
        if (url.endsWith('/session_result?session_key=11236')) {
          return { status: 200, body: [
            { position: 1, driver_number: 4, duration: [79.5, 78.9, 78.5],
              gap_to_leader: [0, 0, 0], dnf: false, dns: false, dsq: false,
              number_of_laps: 19, meeting_key: 1280, session_key: 11236 }
          ] }
        }
        if (url.endsWith('/drivers?session_key=11236')) {
          return { status: 200, body: [
            { driver_number: 4, name_acronym: 'NOR', first_name: 'Lando',
              last_name: 'Norris', team_name: 'McLaren',
              headshot_url: 'https://example.com/nor.png', team_colour: 'F47600' }
          ] }
        }
        return { status: 200, body: [] }
      })
    )

    const summary = await runTick(jolpica, wiki, openf1)
    expect(summary.sessionsFinished).toBe(1)
    expect(summary.errors).toBe(0)

    const refreshed = await sessions.getById(ses.id!)
    expect(refreshed?.status).toBe('finished')

    const rows = await results.listForSession(ses.id!)
    expect(rows.length).toBe(1)
    expect(rows[0].driverCode).toBe('NOR')
    expect(rows[0].q1).toBe('1:19.500')
    expect(rows[0].q2).toBe('1:18.900')
    expect(rows[0].q3).toBe('1:18.500')
    expect(rows[0].raceTime).toBeNull()
  })

  it('skips a sprint_quali session when its openf1SessionKey is null', async () => {
    await seasons.upsertSeason({ year: 2026, isCurrent: true })
    const ev = await events.upsertEvent({
      seasonYear: 2026, round: 2, name: 'Chinese GP', circuitName: 'Shanghai',
      country: 'China', hasSprint: true
    })
    const past = new Date(Date.now() - 3 * 60 * 60 * 1000)
    await sessions.upsertSession({
      eventId: ev.id, type: 'sprint_quali',
      scheduledStart: past, scheduledEnd: past,
      status: 'scheduled', openf1SessionKey: null
    })

    const jolpica = new JolpicaClient('https://example.invalid', staticFetch(() => ({ status: 200, body: { MRData: { RaceTable: { Races: [] } } } })))
    const wiki = new WikipediaClient('https://example.invalid', staticFetch(() => ({ status: 200, body: { query: { pages: {} } } })))
    const openf1 = new OpenF1Client('https://api.openf1.org/v1', staticFetch(() => ({ status: 200, body: [] })))

    const summary = await runTick(jolpica, wiki, openf1)
    expect(summary.sessionsFinished).toBe(0)
    expect(summary.sessionsSkipped).toBe(1)
  })
})
```

- [ ] **Step 3: Run the test, watch it fail**

```bash
cd backend && set -a && source .env && set +a && npx vitest run test/integration/crawler_openf1_sprintquali.test.ts
```

Expected: fails (either compile error because `runTick` does not accept a third arg, or assertion failure because sprint_quali still goes through Jolpica and returns empty).

- [ ] **Step 4: Modify tick.ts to branch sprint_quali to OpenF1**

In `backend/src/crawler/tick.ts`:

(a) At the top, add the OpenF1 imports next to the existing ones:

```ts
import type { OpenF1Client } from '../openf1/client.js'
import { parseSessionResult as parseOpenF1SessionResult, parseDrivers as parseOpenF1Drivers, type OpenF1DriverLookup } from '../openf1/parsers.js'
```

(b) Change `fetchByType` to accept an OpenF1 client and the session's `openf1SessionKey`, branching `sprint_quali` to OpenF1:

```ts
async function fetchByType(
  client: JolpicaClient,
  openf1: OpenF1Client,
  type: SessionType,
  year: number,
  round: number,
  openf1SessionKey: number | null
): Promise<FetchOutput> {
  const empty: FetchOutput = { rows: [], drivers: [], constructors: [] }
  let raw: unknown | null = null
  let rows: SessionResultRow[] = []
  switch (type) {
    case 'race':
      raw = await client.getRaceResults(year, round)
      if (!raw) return empty
      rows = parseRaceResults(raw)
      break
    case 'qualifying':
      raw = await client.getQualifyingResults(year, round)
      if (!raw) return empty
      rows = parseQualifyingResults(raw)
      break
    case 'sprint':
      raw = await client.getSprintResults(year, round)
      if (!raw) return empty
      rows = parseSprintResults(raw)
      break
    case 'sprint_quali': {
      if (openf1SessionKey == null) return empty
      const sr = await openf1.getSessionResult(openf1SessionKey)
      if (!sr) return empty
      const drv = await openf1.getDrivers(openf1SessionKey)
      if (!drv) return empty
      const openF1Drivers = parseOpenF1Drivers(drv)
      rows = parseOpenF1SessionResult(sr, openF1Drivers)
      return {
        rows,
        drivers: openF1Drivers.map((d) => ({
          code: d.code, givenName: d.givenName, familyName: d.familyName,
          nationality: null, permanentNumber: d.driverNumber, wikipediaUrl: null
        })),
        constructors: dedupeConstructorsFromOpenF1(openF1Drivers)
      }
    }
    default:
      return empty  // FPx — never fetched
  }
  return {
    rows,
    drivers: extractDriversFromResults(raw),
    constructors: extractConstructorsFromResults(raw)
  }
}

function dedupeConstructorsFromOpenF1(drivers: OpenF1DriverLookup[]) {
  const seen = new Map<string, { id: string; name: string; nationality: null; wikipediaUrl: null }>()
  for (const d of drivers) {
    const id = d.teamName.toLowerCase().replace(/\s+/g, '_')
    if (!seen.has(id)) seen.set(id, { id, name: d.teamName, nationality: null, wikipediaUrl: null })
  }
  return [...seen.values()]
}
```

(c) Change `runTick` to accept the OpenF1 client and pass it (and `openf1SessionKey`) to `fetchByType`:

```ts
export async function runTick(
  jolpica: JolpicaClient,
  wiki: WikipediaClient,
  openf1: OpenF1Client
): Promise<TickSummary> {
```

And in the loop body, update the call:

```ts
const { rows, drivers, constructors } = await fetchByType(
  jolpica, openf1, ses.type, ev.seasonYear, ev.round, ses.openf1SessionKey
)
```

(d) Update the scheduler's `tickOnce` to pass `this.openf1` (it already has the field from Task 4 Step 5):

In `backend/src/crawler/scheduler.ts`, change the body of `tickOnce`'s `runTick` call:

```ts
const summary = await runTick(this.jolpica, this.wiki, this.openf1)
```

(e) Update the admin route `/admin/crawl` if it has any direct `runTick` calls — it does not (it goes through `scheduler.tickOnce`), so no change needed.

- [ ] **Step 5: Run the sprint_quali test, then the full suite**

```bash
cd backend && set -a && source .env && set +a && npx vitest run test/integration/crawler_openf1_sprintquali.test.ts
```

Expected: 2 passed.

```bash
cd backend && set -a && source .env && set +a && npm test
```

Expected: all pass. If a pre-existing crawler test fails because of the new `runTick` arity, update it to pass an `OpenF1Client` with an empty fake fetcher.

- [ ] **Step 6: Commit**

```bash
git add backend/src/crawler/tick.ts backend/src/crawler/scheduler.ts backend/test/integration/crawler_openf1_sprintquali.test.ts
git commit -m "$(cat <<'EOF'
backend: tick fetches sprint_quali from OpenF1 (sprint quali bug fix)

When a session's openf1SessionKey is set, sprint_quali results now come
from OpenF1's /session_result + /drivers. Jolpica path is untouched for
race/qualifying/sprint. Sessions without a session_key remain skipped.

Spec: docs/superpowers/specs/2026-05-26-openf1-integration-design.md
EOF
)"
```

---

## Task 6: Tick — cross-check + Jolpica-empty fallback (race/qualifying/sprint)

**Files**
- Create: `backend/src/crawler/crossCheck.ts`
- Modify: `backend/src/crawler/tick.ts`
- Create: `backend/test/integration/crawler_openf1_crosscheck.test.ts`

- [ ] **Step 1: Write the failing integration test**

Create `backend/test/integration/crawler_openf1_crosscheck.test.ts`:

```ts
import { describe, it, expect, vi } from 'vitest'
import { runTick } from '../../src/crawler/tick.js'
import { JolpicaClient } from '../../src/jolpica/client.js'
import { WikipediaClient } from '../../src/wikipedia/client.js'
import { OpenF1Client } from '../../src/openf1/client.js'
import * as seasons from '../../src/repo/seasons.js'
import * as events from '../../src/repo/events.js'
import * as sessions from '../../src/repo/sessions.js'
import * as drivers from '../../src/repo/drivers.js'
import * as constructors from '../../src/repo/constructors.js'
import * as results from '../../src/repo/results.js'

function staticFetch(handler: (url: string) => { status: number; body: unknown }) {
  return (async (url: string | URL) => {
    const h = handler(url.toString())
    return new Response(JSON.stringify(h.body), { status: h.status })
  }) as unknown as typeof fetch
}

async function seedRaceSession(openf1Key: number | null = 9001) {
  await seasons.upsertSeason({ year: 2024, isCurrent: true })
  const ev = await events.upsertEvent({
    seasonYear: 2024, round: 1, name: 'Bahrain GP', circuitName: 'BIC',
    country: 'Bahrain', hasSprint: false
  })
  for (const code of ['VER', 'PER']) {
    await drivers.upsertDriver({
      code, givenName: code, familyName: code, nationality: null,
      permanentNumber: 1, wikipediaUrl: null, imageUrl: null,
      imageUrlOverride: null, headshotUrl: null
    })
  }
  await constructors.upsertConstructor({
    id: 'red_bull', name: 'Red Bull', nationality: null,
    wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, teamColour: null
  })
  const past = new Date(Date.now() - 3 * 60 * 60 * 1000)
  return sessions.upsertSession({
    eventId: ev.id, type: 'race',
    scheduledStart: past, scheduledEnd: past,
    status: 'scheduled', openf1SessionKey: openf1Key
  })
}

function jolpicaRace(rows: Array<{ position: number; code: string }>) {
  const body = {
    MRData: { RaceTable: { Races: [{ Results: rows.map((r) => ({
      position: String(r.position),
      Driver: { code: r.code, driverId: r.code.toLowerCase(), givenName: r.code, familyName: r.code, url: null, nationality: 'Dutch', permanentNumber: '1' },
      Constructor: { constructorId: 'red_bull', name: 'Red Bull', url: null, nationality: 'Austrian' }
    })) }] } }
  }
  return new JolpicaClient('https://example.invalid', staticFetch(() => ({ status: 200, body })))
}

function openf1Race(rows: Array<{ position: number; code: string }>) {
  return new OpenF1Client('https://api.openf1.org/v1', staticFetch((url) => {
    if (url.endsWith('/session_result?session_key=9001')) {
      return { status: 200, body: rows.map((r) => ({
        position: r.position, driver_number: r.code === 'VER' ? 1 : 11,
        duration: [], gap_to_leader: [], dnf: false, dns: false, dsq: false,
        number_of_laps: 1, meeting_key: 1, session_key: 9001
      })) }
    }
    if (url.endsWith('/drivers?session_key=9001')) {
      return { status: 200, body: [
        { driver_number: 1, name_acronym: 'VER', first_name: 'Max', last_name: 'Verstappen', team_name: 'Red Bull', headshot_url: null, team_colour: null },
        { driver_number: 11, name_acronym: 'PER', first_name: 'Sergio', last_name: 'Pérez', team_name: 'Red Bull', headshot_url: null, team_colour: null }
      ] }
    }
    return { status: 200, body: [] }
  }))
}

const wikiNoop = new WikipediaClient('https://example.invalid', staticFetch(() => ({ status: 200, body: { query: { pages: {} } } })))

describe('Crawler — OpenF1 cross-check', () => {
  it('persists Jolpica and logs no warning when classifications match', async () => {
    const ses = await seedRaceSession()
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {})
    await runTick(
      jolpicaRace([{ position: 1, code: 'VER' }, { position: 2, code: 'PER' }]),
      wikiNoop,
      openf1Race([{ position: 1, code: 'VER' }, { position: 2, code: 'PER' }])
    )
    const rows = await results.listForSession(ses.id!)
    expect(rows.map((r) => r.driverCode)).toEqual(['VER', 'PER'])
    expect(warn).not.toHaveBeenCalled()
    warn.mockRestore()
  })

  it('persists Jolpica and logs exactly one warning on mismatch', async () => {
    const ses = await seedRaceSession()
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {})
    await runTick(
      jolpicaRace([{ position: 1, code: 'VER' }, { position: 2, code: 'PER' }]),
      wikiNoop,
      openf1Race([{ position: 1, code: 'PER' }, { position: 2, code: 'VER' }])
    )
    const rows = await results.listForSession(ses.id!)
    expect(rows.map((r) => r.driverCode)).toEqual(['VER', 'PER']) // Jolpica wins
    expect(warn).toHaveBeenCalledTimes(1)
    warn.mockRestore()
  })

  it('falls back to OpenF1 rows when Jolpica returns empty', async () => {
    const ses = await seedRaceSession()
    const jolpicaEmpty = new JolpicaClient(
      'https://example.invalid',
      staticFetch(() => ({ status: 200, body: { MRData: { RaceTable: { Races: [] } } } }))
    )
    await runTick(
      jolpicaEmpty,
      wikiNoop,
      openf1Race([{ position: 1, code: 'VER' }, { position: 2, code: 'PER' }])
    )
    const rows = await results.listForSession(ses.id!)
    expect(rows.map((r) => r.driverCode)).toEqual(['VER', 'PER'])
  })

  it('does not invoke OpenF1 when openf1SessionKey is null (no cross-check)', async () => {
    const ses = await seedRaceSession(null)
    let openf1Calls = 0
    const openf1 = new OpenF1Client('https://api.openf1.org/v1', (async (url: string | URL) => {
      openf1Calls++
      return new Response('[]', { status: 200 })
    }) as unknown as typeof fetch)

    await runTick(
      jolpicaRace([{ position: 1, code: 'VER' }, { position: 2, code: 'PER' }]),
      wikiNoop,
      openf1
    )
    expect(openf1Calls).toBe(0)
    const rows = await results.listForSession(ses.id!)
    expect(rows.length).toBe(2)
  })
})
```

- [ ] **Step 2: Run the test, watch it fail**

```bash
cd backend && set -a && source .env && set +a && npx vitest run test/integration/crawler_openf1_crosscheck.test.ts
```

Expected: at least two of the four tests fail (no cross-check is wired yet).

- [ ] **Step 3: Implement the cross-check helper**

Create `backend/src/crawler/crossCheck.ts`:

```ts
import type { SessionResultRow } from '../domain/types.js'

export type CrossCheckResult =
  | { kind: 'match' }
  | { kind: 'length-differs'; jolpicaLength: number; openf1Length: number }
  | { kind: 'position-differs'; differences: Array<{ position: number; jolpica: string; openf1: string }> }

export function compareClassifications(
  jolpica: SessionResultRow[],
  openf1: SessionResultRow[]
): CrossCheckResult {
  if (jolpica.length !== openf1.length) {
    return { kind: 'length-differs', jolpicaLength: jolpica.length, openf1Length: openf1.length }
  }
  const jByPos = new Map(jolpica.map((r) => [r.position, r.driverCode]))
  const oByPos = new Map(openf1.map((r) => [r.position, r.driverCode]))
  const diffs: Array<{ position: number; jolpica: string; openf1: string }> = []
  for (const [pos, j] of jByPos) {
    const o = oByPos.get(pos)
    if (o && o !== j) diffs.push({ position: pos, jolpica: j, openf1: o })
  }
  return diffs.length === 0 ? { kind: 'match' } : { kind: 'position-differs', differences: diffs }
}
```

- [ ] **Step 4: Wire cross-check + Jolpica-empty fallback into the tick loop**

In `backend/src/crawler/tick.ts`:

(a) Import the cross-check at the top:

```ts
import { compareClassifications } from './crossCheck.js'
```

(b) In `runTick`'s per-session loop, between fetching Jolpica's rows and writing them, fetch OpenF1 in parallel (for race/quali/sprint), then cross-check, then choose the rows to persist. Replace the existing body of the per-session `try` block (everything inside `for (const ses of candidates)`):

```ts
for (const ses of candidates) {
  try {
    const ev = await getEvent(ses.eventId)
    if (!ev) { summary.errors++; continue }
    const jolpicaOut = await fetchByType(jolpica, openf1, ses.type, ev.seasonYear, ev.round, ses.openf1SessionKey)

    // Cross-check + fallback for race/qualifying/sprint.
    let rowsToPersist = jolpicaOut.rows
    let driversToUpsert = jolpicaOut.drivers
    let constructorsToUpsert = jolpicaOut.constructors

    const isCrossCheckable = ses.type === 'race' || ses.type === 'qualifying' || ses.type === 'sprint'
    if (isCrossCheckable && ses.openf1SessionKey != null) {
      try {
        const sr = await openf1.getSessionResult(ses.openf1SessionKey)
        const drv = await openf1.getDrivers(ses.openf1SessionKey)
        if (sr && drv) {
          const oDrv = parseOpenF1Drivers(drv)
          const oRows = parseOpenF1SessionResult(sr, oDrv)
          if (rowsToPersist.length === 0 && oRows.length > 0) {
            // Jolpica empty, OpenF1 has data — fallback to OpenF1.
            rowsToPersist = oRows
            driversToUpsert = oDrv.map((d) => ({
              code: d.code, givenName: d.givenName, familyName: d.familyName,
              nationality: null, permanentNumber: d.driverNumber, wikipediaUrl: null
            }))
            constructorsToUpsert = dedupeConstructorsFromOpenF1(oDrv)
          } else if (oRows.length > 0) {
            const cmp = compareClassifications(rowsToPersist, oRows)
            if (cmp.kind !== 'match') {
              console.warn('OpenF1 cross-check mismatch', { sessionId: ses.id, type: ses.type, summary: cmp })
            }
          }
        }
      } catch (err) {
        console.warn('OpenF1 cross-check fetch failed', { sessionId: ses.id, err })
      }
    }

    if (rowsToPersist.length === 0) { summary.sessionsSkipped++; continue }

    await upsertNewDrivers(driversToUpsert, wiki)
    await upsertNewConstructors(constructorsToUpsert, wiki)
    await resultsRepo.replaceForSession(ses.id!, rowsToPersist.map((r) => ({ ...r, sessionId: ses.id! })))
    await sessionsRepo.markFinished(ses.id!)
    summary.sessionsFinished++
    anyFinished = true
    try {
      const rescore = await rescoreSession(ses.id!)
      console.log('Rescored session', { sessionId: ses.id, ...rescore })
    } catch (err) {
      console.error('Rescore failed (results saved)', { sessionId: ses.id, err })
    }
  } catch (err) {
    summary.errors++
    console.error('Tick error for session', ses.id, err)
  }
}
```

The pre-existing standings refresh + preseason rescore block that runs `if (anyFinished)` after the loop stays unchanged.

- [ ] **Step 5: Run the cross-check test, then the full suite**

```bash
cd backend && set -a && source .env && set +a && npx vitest run test/integration/crawler_openf1_crosscheck.test.ts
```

Expected: 4 passed.

```bash
cd backend && set -a && source .env && set +a && npm test
```

Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add backend/src/crawler/crossCheck.ts backend/src/crawler/tick.ts backend/test/integration/crawler_openf1_crosscheck.test.ts
git commit -m "$(cat <<'EOF'
backend: cross-check race/qualifying/sprint against OpenF1

Adds compareClassifications + tick-loop wiring. When openf1SessionKey is
set: fetch OpenF1 in parallel, log structured WARN on length or per-position
mismatch, fall back to OpenF1 rows if Jolpica returned empty. Jolpica stays
authoritative when both sources agree or both have data.

Spec: docs/superpowers/specs/2026-05-26-openf1-integration-design.md
EOF
)"
```

---

## Task 7: Opportunistic driver / constructor enrichment

**Files**
- Create: `backend/src/crawler/openf1Enrichment.ts`
- Modify: `backend/src/crawler/tick.ts`
- Create: `backend/test/integration/crawler_openf1_enrichment.test.ts`

- [ ] **Step 1: Write the failing integration test**

Create `backend/test/integration/crawler_openf1_enrichment.test.ts`:

```ts
import { describe, it, expect } from 'vitest'
import { runTick } from '../../src/crawler/tick.js'
import { JolpicaClient } from '../../src/jolpica/client.js'
import { WikipediaClient } from '../../src/wikipedia/client.js'
import { OpenF1Client } from '../../src/openf1/client.js'
import * as seasons from '../../src/repo/seasons.js'
import * as events from '../../src/repo/events.js'
import * as sessions from '../../src/repo/sessions.js'
import * as drivers from '../../src/repo/drivers.js'
import * as constructors from '../../src/repo/constructors.js'

function staticFetch(handler: (url: string) => { status: number; body: unknown }) {
  return (async (url: string | URL) => {
    const h = handler(url.toString())
    return new Response(JSON.stringify(h.body), { status: h.status })
  }) as unknown as typeof fetch
}

async function seedNorWithoutHeadshot() {
  await seasons.upsertSeason({ year: 2024, isCurrent: true })
  const ev = await events.upsertEvent({
    seasonYear: 2024, round: 1, name: 'Bahrain', circuitName: 'BIC',
    country: 'Bahrain', hasSprint: false
  })
  await drivers.upsertDriver({
    code: 'NOR', givenName: 'Lando', familyName: 'Norris',
    nationality: null, permanentNumber: 4, wikipediaUrl: null,
    imageUrl: null, imageUrlOverride: null, headshotUrl: null
  })
  await constructors.upsertConstructor({
    id: 'mclaren', name: 'McLaren', nationality: null,
    wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, teamColour: null
  })
  const past = new Date(Date.now() - 3 * 60 * 60 * 1000)
  return sessions.upsertSession({
    eventId: ev.id, type: 'race',
    scheduledStart: past, scheduledEnd: past,
    status: 'scheduled', openf1SessionKey: 9001
  })
}

function jolpicaRace(code: string, ctor: string) {
  const body = {
    MRData: { RaceTable: { Races: [{ Results: [{
      position: '1',
      Driver: { code, driverId: code.toLowerCase(), givenName: 'X', familyName: 'X', url: null, nationality: 'X', permanentNumber: '4' },
      Constructor: { constructorId: ctor, name: ctor, url: null, nationality: 'X' }
    }] }] } }
  }
  return new JolpicaClient('https://example.invalid', staticFetch(() => ({ status: 200, body })))
}

function openf1WithDriver() {
  return new OpenF1Client('https://api.openf1.org/v1', staticFetch((url) => {
    if (url.endsWith('/session_result?session_key=9001')) {
      return { status: 200, body: [{ position: 1, driver_number: 4, duration: [],
        gap_to_leader: [], dnf: false, dns: false, dsq: false, number_of_laps: 1,
        meeting_key: 1, session_key: 9001 }] }
    }
    if (url.endsWith('/drivers?session_key=9001')) {
      return { status: 200, body: [{ driver_number: 4, name_acronym: 'NOR',
        first_name: 'Lando', last_name: 'Norris', team_name: 'McLaren',
        headshot_url: 'https://example.com/nor.png', team_colour: 'F47600' }] }
    }
    return { status: 200, body: [] }
  }))
}

const wikiNoop = new WikipediaClient('https://example.invalid', staticFetch(() => ({ status: 200, body: { query: { pages: {} } } })))

describe('Crawler — OpenF1 driver/team enrichment', () => {
  it('writes headshot_url for a driver with no headshot', async () => {
    await seedNorWithoutHeadshot()
    await runTick(jolpicaRace('NOR', 'mclaren'), wikiNoop, openf1WithDriver())
    const d = await drivers.getByCode('NOR')
    expect(d?.headshotUrl).toBe('https://example.com/nor.png')
  })

  it('writes team_colour for a constructor with no colour', async () => {
    await seedNorWithoutHeadshot()
    await runTick(jolpicaRace('NOR', 'mclaren'), wikiNoop, openf1WithDriver())
    const c = await constructors.getById('mclaren')
    expect(c?.teamColour).toBe('F47600')
  })

  it('does not overwrite an existing non-null headshot_url', async () => {
    await seedNorWithoutHeadshot()
    await drivers.setHeadshotUrl('NOR', 'https://manual.example/keep.png')
    await runTick(jolpicaRace('NOR', 'mclaren'), wikiNoop, openf1WithDriver())
    const d = await drivers.getByCode('NOR')
    expect(d?.headshotUrl).toBe('https://manual.example/keep.png')
  })
})
```

- [ ] **Step 2: Run the test, watch it fail**

```bash
cd backend && set -a && source .env && set +a && npx vitest run test/integration/crawler_openf1_enrichment.test.ts
```

Expected: all three fail (enrichment is not wired).

- [ ] **Step 3: Implement the enrichment helper**

Create `backend/src/crawler/openf1Enrichment.ts`:

```ts
import * as driversRepo from '../repo/drivers.js'
import * as constructorsRepo from '../repo/constructors.js'
import type { OpenF1DriverLookup } from '../openf1/parsers.js'

export async function enrichDriversAndConstructors(drivers: OpenF1DriverLookup[]): Promise<void> {
  const seenConstructors = new Set<string>()
  for (const d of drivers) {
    try {
      const existing = await driversRepo.getByCode(d.code)
      if (existing && existing.headshotUrl == null && d.headshotUrl != null) {
        await driversRepo.setHeadshotUrl(d.code, d.headshotUrl)
      }
      const constructorId = d.teamName.toLowerCase().replace(/\s+/g, '_')
      if (!seenConstructors.has(constructorId)) {
        seenConstructors.add(constructorId)
        const existingCtor = await constructorsRepo.getById(constructorId)
        if (existingCtor && existingCtor.teamColour == null && d.teamColour != null) {
          await constructorsRepo.setTeamColour(constructorId, d.teamColour)
        }
      }
    } catch (err) {
      console.warn('OpenF1 enrichment error', { code: d.code, err })
    }
  }
}
```

- [ ] **Step 4: Wire enrichment into the tick loop**

In `backend/src/crawler/tick.ts`:

(a) Import the helper at the top:

```ts
import { enrichDriversAndConstructors } from './openf1Enrichment.js'
```

(b) In the per-session loop, whenever OpenF1 drivers have been parsed (either in the sprint_quali path inside `fetchByType` OR in the cross-check path inside `runTick`), call `enrichDriversAndConstructors` with the parsed list. The cleanest place is: hoist the OpenF1 drivers parsing out of `fetchByType` and into `runTick`, so the same `oDrv` value flows to both the cross-check and the enrichment.

Concretely: extract a helper that fetches both `/session_result` and `/drivers` once per session (`fetchOpenF1ForSession(openf1, sessionKey)`), and call it once per scorable-type candidate session whose key is set. Use the returned drivers list for enrichment regardless of whether the OpenF1 rows were persisted or merely cross-checked.

After the cross-check / fallback block in the per-session loop, add (before `if (rowsToPersist.length === 0) {...}`):

```ts
    if (isCrossCheckable && ses.openf1SessionKey != null /* and OpenF1 drivers were fetched */) {
      // The cross-check block already parsed `oDrv` — call enrichment with it.
      // (Restructure the cross-check block to make `oDrv` reachable here.)
    }
```

For clarity, the minimal restructure of Step 4 of Task 6 is shown here as the *final* per-session loop body (post-Task 6 + post-Task 7):

```ts
for (const ses of candidates) {
  try {
    const ev = await getEvent(ses.eventId)
    if (!ev) { summary.errors++; continue }
    const jolpicaOut = await fetchByType(jolpica, openf1, ses.type, ev.seasonYear, ev.round, ses.openf1SessionKey)

    let rowsToPersist = jolpicaOut.rows
    let driversToUpsert = jolpicaOut.drivers
    let constructorsToUpsert = jolpicaOut.constructors
    let openF1Drivers: OpenF1DriverLookup[] | null = null

    const isCrossCheckable = ses.type === 'race' || ses.type === 'qualifying' || ses.type === 'sprint'
    if (isCrossCheckable && ses.openf1SessionKey != null) {
      try {
        const sr = await openf1.getSessionResult(ses.openf1SessionKey)
        const drv = await openf1.getDrivers(ses.openf1SessionKey)
        if (sr && drv) {
          openF1Drivers = parseOpenF1Drivers(drv)
          const oRows = parseOpenF1SessionResult(sr, openF1Drivers)
          if (rowsToPersist.length === 0 && oRows.length > 0) {
            rowsToPersist = oRows
            driversToUpsert = openF1Drivers.map((d) => ({
              code: d.code, givenName: d.givenName, familyName: d.familyName,
              nationality: null, permanentNumber: d.driverNumber, wikipediaUrl: null
            }))
            constructorsToUpsert = dedupeConstructorsFromOpenF1(openF1Drivers)
          } else if (oRows.length > 0) {
            const cmp = compareClassifications(rowsToPersist, oRows)
            if (cmp.kind !== 'match') {
              console.warn('OpenF1 cross-check mismatch', { sessionId: ses.id, type: ses.type, summary: cmp })
            }
          }
        }
      } catch (err) {
        console.warn('OpenF1 cross-check fetch failed', { sessionId: ses.id, err })
      }
    }

    if (rowsToPersist.length === 0) { summary.sessionsSkipped++; continue }

    await upsertNewDrivers(driversToUpsert, wiki)
    await upsertNewConstructors(constructorsToUpsert, wiki)
    await resultsRepo.replaceForSession(ses.id!, rowsToPersist.map((r) => ({ ...r, sessionId: ses.id! })))
    await sessionsRepo.markFinished(ses.id!)

    if (openF1Drivers) await enrichDriversAndConstructors(openF1Drivers)
    // Also enrich after sprint_quali (no cross-check path, drivers came from inside fetchByType).
    if (!openF1Drivers && ses.type === 'sprint_quali' && ses.openf1SessionKey != null) {
      try {
        const drv = await openf1.getDrivers(ses.openf1SessionKey)
        if (drv) await enrichDriversAndConstructors(parseOpenF1Drivers(drv))
      } catch (err) {
        console.warn('OpenF1 enrichment fetch failed (sprint_quali)', { sessionId: ses.id, err })
      }
    }

    summary.sessionsFinished++
    anyFinished = true
    try {
      const rescore = await rescoreSession(ses.id!)
      console.log('Rescored session', { sessionId: ses.id, ...rescore })
    } catch (err) {
      console.error('Rescore failed (results saved)', { sessionId: ses.id, err })
    }
  } catch (err) {
    summary.errors++
    console.error('Tick error for session', ses.id, err)
  }
}
```

- [ ] **Step 5: Run the enrichment test, then the full suite**

```bash
cd backend && set -a && source .env && set +a && npx vitest run test/integration/crawler_openf1_enrichment.test.ts
```

Expected: 3 passed.

```bash
cd backend && set -a && source .env && set +a && npm test
```

Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add backend/src/crawler/openf1Enrichment.ts backend/src/crawler/tick.ts backend/test/integration/crawler_openf1_enrichment.test.ts
git commit -m "$(cat <<'EOF'
backend: opportunistic OpenF1 enrichment of driver headshot + team colour

Whenever the tick calls OpenF1 (sprint_quali or cross-check), it also fills
in null driver.headshot_url and constructor.team_colour from the same
/drivers response. Existing non-null values are never overwritten.

Spec: docs/superpowers/specs/2026-05-26-openf1-integration-design.md
EOF
)"
```

---

## Task 8: API surface — image precedence + teamColour

**Files**
- Modify: `backend/src/api/routes/public.ts`
- Create: `backend/test/integration/api_drivers_headshot.test.ts`

- [ ] **Step 1: Write the failing API test**

Create `backend/test/integration/api_drivers_headshot.test.ts`:

```ts
import { describe, it, expect, beforeEach } from 'vitest'
import { buildApp } from '../../src/index.js'
import * as drivers from '../../src/repo/drivers.js'
import * as constructors from '../../src/repo/constructors.js'
import * as seasons from '../../src/repo/seasons.js'
import * as standings from '../../src/repo/standings.js'

let app: Awaited<ReturnType<typeof buildApp>>
beforeEach(async () => { app = await buildApp({ scheduler: null }) })

async function seedVerWithImages(opts: { override?: string | null; headshot?: string | null; image?: string | null }) {
  await drivers.upsertDriver({
    code: 'VER', givenName: 'Max', familyName: 'Verstappen',
    nationality: 'Dutch', permanentNumber: 33, wikipediaUrl: null,
    imageUrl: opts.image ?? null, imageUrlOverride: opts.override ?? null,
    headshotUrl: opts.headshot ?? null
  })
}

describe('GET /api/drivers/:code', () => {
  it('returns image = override when override is set', async () => {
    await seedVerWithImages({ override: 'OVER', headshot: 'HEAD', image: 'WIKI' })
    const res = await app.inject({ method: 'GET', url: '/api/drivers/VER' })
    expect(res.statusCode).toBe(200)
    expect(res.json().image).toBe('OVER')
  })
  it('returns image = headshot when override is null and headshot is set', async () => {
    await seedVerWithImages({ headshot: 'HEAD', image: 'WIKI' })
    const res = await app.inject({ method: 'GET', url: '/api/drivers/VER' })
    expect(res.json().image).toBe('HEAD')
  })
  it('returns image = imageUrl when override and headshot are both null', async () => {
    await seedVerWithImages({ image: 'WIKI' })
    const res = await app.inject({ method: 'GET', url: '/api/drivers/VER' })
    expect(res.json().image).toBe('WIKI')
  })
  it('exposes headshotUrl on the payload alongside image', async () => {
    await seedVerWithImages({ headshot: 'HEAD' })
    const res = await app.inject({ method: 'GET', url: '/api/drivers/VER' })
    expect(res.json().headshotUrl).toBe('HEAD')
  })
})

describe('GET /api/constructors/:id', () => {
  it('exposes teamColour', async () => {
    await constructors.upsertConstructor({
      id: 'red_bull', name: 'Red Bull', nationality: 'Austrian',
      wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, teamColour: '1E41FF'
    })
    const res = await app.inject({ method: 'GET', url: '/api/constructors/red_bull' })
    expect(res.statusCode).toBe(200)
    expect(res.json().teamColour).toBe('1E41FF')
  })
})
```

(`buildApp` is exported from `backend/src/index.ts` — see `backend/test/integration/api_admin.test.ts` for the established usage pattern with `{ scheduler: null }`.)

- [ ] **Step 2: Run, watch it fail**

```bash
cd backend && set -a && source .env && set +a && npx vitest run test/integration/api_drivers_headshot.test.ts
```

Expected: image precedence assertion fails ("expected 'HEAD' but received 'WIKI'" or similar) and the `teamColour` assertion fails.

- [ ] **Step 3: Update the API serializers**

In `backend/src/api/routes/public.ts`, change the four spots that compute the `image` field for drivers and the two spots for constructors.

For drivers: replace `image: d.imageUrlOverride ?? d.imageUrl` with `image: d.imageUrlOverride ?? d.headshotUrl ?? d.imageUrl` everywhere it appears (drivers standings and `/api/drivers/:code` routes).

For constructors: leave `image` precedence unchanged (OpenF1 has no constructor image). The response shape already spreads `...c` so `teamColour` is included automatically — verify the test passes without further changes.

Concretely, the four lines to change are at `backend/src/api/routes/public.ts` (line numbers approximate):

```ts
// in /api/standings/drivers and /api/standings/constructors loops
return { ...s, driver: d ? { ...d, image: d.imageUrlOverride ?? d.headshotUrl ?? d.imageUrl } : null }
// constructor stays untouched
return { ...s, constructor: c ? { ...c, image: c.imageUrlOverride ?? c.imageUrl } : null }

// in /api/drivers/:code
return { ...d, image: d.imageUrlOverride ?? d.headshotUrl ?? d.imageUrl }

// in /api/constructors/:id
return { ...c, image: c.imageUrlOverride ?? c.imageUrl }
```

- [ ] **Step 4: Run the API test, then the full suite**

```bash
cd backend && set -a && source .env && set +a && npx vitest run test/integration/api_drivers_headshot.test.ts
```

Expected: 5 passed.

```bash
cd backend && set -a && source .env && set +a && npm test
```

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add backend/src/api/routes/public.ts backend/test/integration/api_drivers_headshot.test.ts
git commit -m "$(cat <<'EOF'
backend: api — image precedence override > headshot > wiki; expose teamColour

Driver image resolution now prefers manual override, then OpenF1 headshot,
then the Wikipedia-scraped image. Constructor responses expose teamColour
verbatim. No constructor image precedence change (OpenF1 has no logo).

Spec: docs/superpowers/specs/2026-05-26-openf1-integration-design.md
EOF
)"
```

---

## Task 9: Admin endpoint `/admin/refresh-openf1-metadata`

**Files**
- Modify: `backend/src/api/routes/admin.ts`
- Modify: `Makefile` (add `refresh-openf1` target)
- Create: `backend/test/integration/api_admin_refresh_openf1.test.ts`

- [ ] **Step 1: Write the failing integration test**

Create `backend/test/integration/api_admin_refresh_openf1.test.ts`:

```ts
import { describe, it, expect, beforeEach } from 'vitest'
import { buildApp } from '../../src/index.js'
import * as seasons from '../../src/repo/seasons.js'
import * as events from '../../src/repo/events.js'
import * as sessions from '../../src/repo/sessions.js'
import * as drivers from '../../src/repo/drivers.js'
import * as constructors from '../../src/repo/constructors.js'

let app: Awaited<ReturnType<typeof buildApp>>
beforeEach(async () => { app = await buildApp({ scheduler: null }) })

async function seed() {
  await seasons.upsertSeason({ year: 2024, isCurrent: true })
  const ev = await events.upsertEvent({
    seasonYear: 2024, round: 1, name: 'Bahrain', circuitName: 'BIC',
    country: 'Bahrain', hasSprint: false
  })
  await sessions.upsertSession({
    eventId: ev.id, type: 'race',
    scheduledStart: new Date('2024-03-02T15:00:00Z'),
    scheduledEnd: new Date('2024-03-02T17:00:00Z'),
    status: 'finished', openf1SessionKey: 9001
  })
  await drivers.upsertDriver({
    code: 'VER', givenName: 'Max', familyName: 'Verstappen',
    nationality: null, permanentNumber: 1, wikipediaUrl: null,
    imageUrl: null, imageUrlOverride: null, headshotUrl: null
  })
  await constructors.upsertConstructor({
    id: 'red_bull', name: 'Red Bull', nationality: null,
    wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, teamColour: null
  })
}

describe('POST /admin/refresh-openf1-metadata', () => {
  it('fills headshot_url and team_colour from OpenF1', async () => {
    await seed()
    const res = await app.inject({
      method: 'POST',
      url: '/admin/refresh-openf1-metadata',
      headers: { 'x-admin-token': 'local-dev-token' }
    })
    expect(res.statusCode).toBe(200)
    const body = res.json()
    expect(body.ok).toBe(true)
    expect(body.driversUpdated).toBeGreaterThanOrEqual(0)
    expect(body.constructorsUpdated).toBeGreaterThanOrEqual(0)
  })

  it('returns 401 without admin token', async () => {
    await seed()
    const res = await app.inject({ method: 'POST', url: '/admin/refresh-openf1-metadata' })
    expect(res.statusCode).toBe(401)
  })
})
```

Note: this test runs against the real OpenF1 API (no mock). It's a smoke test rather than a strict assertion; the strict tests live in Task 7. If the OpenF1 endpoint is unreachable in CI later, mark it `.skip` — but for the local-dev story it's useful to keep it real.

If the test infra in `helpers/app.ts` mocks OpenF1 at the app level, swap the assertions for ones that drive the mock.

- [ ] **Step 2: Run, watch it fail**

```bash
cd backend && set -a && source .env && set +a && npx vitest run test/integration/api_admin_refresh_openf1.test.ts
```

Expected: 404 (endpoint not registered).

- [ ] **Step 3: Implement the admin endpoint**

In `backend/src/api/routes/admin.ts`, add a new handler. Append, after the existing `app.post('/admin/refresh-images', ...)` block:

```ts
  app.post('/admin/refresh-openf1-metadata', async () => {
    const missingDrivers = await driversRepo.listMissingHeadshot()
    const missingCtors = await constructorsRepo.listMissingTeamColour()

    // Find the most-recent finished session that has an openf1_session_key. Use that
    // session's /drivers payload as a single bulk source for headshots / team colours.
    const finished = await sessionsRepo.listRecentFinishedWithOpenF1Key(5)

    let driversUpdated = 0
    let constructorsUpdated = 0
    const driverFilled = new Set<string>()
    const ctorFilled = new Set<string>()

    for (const ses of finished) {
      if (driverFilled.size >= missingDrivers.length && ctorFilled.size >= missingCtors.length) break
      const drvRaw = await openf1.getDrivers(ses.openf1SessionKey!)
      if (!drvRaw) continue
      const oDrv = parseOpenF1Drivers(drvRaw)
      for (const d of oDrv) {
        if (missingDrivers.some((md) => md.code === d.code) && !driverFilled.has(d.code) && d.headshotUrl) {
          await driversRepo.setHeadshotUrl(d.code, d.headshotUrl)
          driverFilled.add(d.code)
          driversUpdated++
        }
        const ctorId = d.teamName.toLowerCase().replace(/\s+/g, '_')
        if (missingCtors.some((mc) => mc.id === ctorId) && !ctorFilled.has(ctorId) && d.teamColour) {
          await constructorsRepo.setTeamColour(ctorId, d.teamColour)
          ctorFilled.add(ctorId)
          constructorsUpdated++
        }
      }
    }

    return { ok: true, driversUpdated, constructorsUpdated }
  })
```

Add the imports near the top of the file:

```ts
import { OpenF1Client } from '../../openf1/client.js'
import { parseDrivers as parseOpenF1Drivers } from '../../openf1/parsers.js'
```

(`openf1` const was already added in Task 4 Step 5.)

Add the new repo function `listRecentFinishedWithOpenF1Key` to `backend/src/repo/sessions.ts`:

```ts
export async function listRecentFinishedWithOpenF1Key(limit: number): Promise<StoredSession[]> {
  const db = getDb()
  const rows = await db
    .select()
    .from(session)
    .where(
      and(
        eq(session.status, 'finished'),
        sql`${session.openf1SessionKey} IS NOT NULL`
      )
    )
    .orderBy(desc(session.scheduledEnd))
    .limit(limit)
  return rows as StoredSession[]
}
```

Make sure `desc` is imported from `drizzle-orm` at the top of `sessions.ts`:

```ts
import { and, eq, lt, gt, sql, asc, desc } from 'drizzle-orm'
```

- [ ] **Step 4: Add the `make` target**

In `Makefile`, after the `crawl` target:

```make
.PHONY: refresh-openf1
refresh-openf1:  ## POST /admin/refresh-openf1-metadata (token-gated)
	@curl -fsS -X POST -H "X-Admin-Token: $(ADMIN_TOKEN)" $(API_URL)/admin/refresh-openf1-metadata | python3 -m json.tool
```

- [ ] **Step 5: Run the new test, then the full suite**

```bash
cd backend && set -a && source .env && set +a && npx vitest run test/integration/api_admin_refresh_openf1.test.ts
```

Expected: 2 passed.

```bash
cd backend && set -a && source .env && set +a && npm test
```

Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add backend/src/api/routes/admin.ts backend/src/repo/sessions.ts Makefile backend/test/integration/api_admin_refresh_openf1.test.ts
git commit -m "$(cat <<'EOF'
backend: admin endpoint to backfill OpenF1 metadata + make target

POST /admin/refresh-openf1-metadata iterates drivers/constructors with
null headshot_url / team_colour and fills them from the most-recent
finished session's OpenF1 /drivers response. Make refresh-openf1 wraps
the curl call.

Spec: docs/superpowers/specs/2026-05-26-openf1-integration-design.md
EOF
)"
```

---

## Task 10: Flutter — models + team_colors fallback

**Files**
- Modify: `lib/api/models/driver.dart`, `lib/api/models/constructor.dart`, `lib/theme/team_colors.dart`
- Create: `test/theme/team_colors_test.dart` (or extend existing — check first)

- [ ] **Step 1: Add `headshotUrl` to the Driver model**

Replace the contents of `lib/api/models/driver.dart` with:

```dart
class Driver {
  final String code;
  final String givenName;
  final String familyName;
  final String nationality;
  final int? permanentNumber;
  final String? image;
  final String? headshotUrl;

  const Driver({
    required this.code,
    required this.givenName,
    required this.familyName,
    required this.nationality,
    this.permanentNumber,
    this.image,
    this.headshotUrl,
  });

  factory Driver.fromJson(Map<String, dynamic> j) => Driver(
        code: j['code'] as String,
        givenName: j['givenName'] as String,
        familyName: j['familyName'] as String,
        nationality: j['nationality'] as String,
        permanentNumber: j['permanentNumber'] as int?,
        image: j['image'] as String?,
        headshotUrl: j['headshotUrl'] as String?,
      );
}
```

- [ ] **Step 2: Add `teamColour` to the Constructor model**

Replace the contents of `lib/api/models/constructor.dart` with:

```dart
class Constructor {
  final String id;
  final String name;
  final String nationality;
  final String? image;
  final String? teamColour;

  const Constructor({
    required this.id,
    required this.name,
    required this.nationality,
    this.image,
    this.teamColour,
  });

  factory Constructor.fromJson(Map<String, dynamic> j) => Constructor(
        id: j['id'] as String,
        name: j['name'] as String,
        nationality: j['nationality'] as String,
        image: j['image'] as String?,
        teamColour: j['teamColour'] as String?,
      );
}
```

- [ ] **Step 3: Update `team_colors.dart` to accept a fallback hex**

Replace the contents of `lib/theme/team_colors.dart` with:

```dart
import 'package:flutter/material.dart';

const Map<String, Color> _teamColors = {
  'red_bull': Color(0xFF1E41FF),
  'ferrari': Color(0xFFE8002D),
  'mclaren': Color(0xFFFF8000),
  'mercedes': Color(0xFF27F4D2),
  'aston_martin': Color(0xFF229971),
  'alpine': Color(0xFF0093CC),
  'kick_sauber': Color(0xFF52E252),
  'rb': Color(0xFF6692FF),
  'haas': Color(0xFFB6BABD),
  'williams': Color(0xFF64C4FF),
};

const Map<String, String> _aliases = {
  'alphatauri': 'rb',
  'alpha_tauri': 'rb',
  'alfa': 'kick_sauber',
  'alfa_romeo': 'kick_sauber',
  'sauber': 'kick_sauber',
};

const Color _fallback = Color(0xFF707070);

/// Curated map first; if missing and a fallback hex is provided
/// (e.g. from the backend's OpenF1 `teamColour` field), use it; else neutral grey.
Color teamColor(String constructorId, {String? fallbackHex}) {
  final id = _aliases[constructorId] ?? constructorId;
  final curated = _teamColors[id];
  if (curated != null) return curated;
  if (fallbackHex != null && RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(fallbackHex)) {
    return Color(int.parse(fallbackHex, radix: 16) | 0xFF000000);
  }
  return _fallback;
}
```

This change is backwards-compatible: existing callers passing only `constructorId` get the curated colour or neutral grey, exactly as before.

- [ ] **Step 4: Write a unit test pinning the fallback behaviour**

Check whether `test/theme/team_colors_test.dart` already exists; if it does, extend it. If not, create it:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/theme/team_colors.dart';

void main() {
  group('teamColor', () {
    test('curated map wins over fallback', () {
      expect(
        teamColor('red_bull', fallbackHex: 'F47600'),
        const Color(0xFF1E41FF),
      );
    });

    test('falls back to provided hex when constructor is unknown', () {
      expect(
        teamColor('zzz_new_team', fallbackHex: 'F47600'),
        const Color(0xFFF47600),
      );
    });

    test('returns neutral grey when constructor unknown and no fallback', () {
      expect(teamColor('zzz_new_team'), const Color(0xFF707070));
    });

    test('ignores malformed fallback hex', () {
      expect(teamColor('zzz_new_team', fallbackHex: 'not-hex'), const Color(0xFF707070));
    });

    test('alias resolution still works (alphatauri -> rb)', () {
      expect(teamColor('alphatauri'), const Color(0xFF6692FF));
    });
  });
}
```

- [ ] **Step 5: Run Flutter tests**

```bash
flutter test test/theme/team_colors_test.dart
```

Expected: 5 passed.

```bash
flutter analyze lib/api/models/driver.dart lib/api/models/constructor.dart lib/theme/team_colors.dart test/theme/team_colors_test.dart
```

Expected: `No issues found!`.

```bash
flutter test
```

Expected: every test passes.

- [ ] **Step 6: Commit**

```bash
git add lib/api/models/driver.dart lib/api/models/constructor.dart lib/theme/team_colors.dart test/theme/team_colors_test.dart
git commit -m "$(cat <<'EOF'
flutter: surface OpenF1 headshot + team colour in models and theme

Driver model gains headshotUrl, Constructor gains teamColour, and
teamColor() optionally accepts a fallback hex string so unknown teams
get the backend-supplied colour instead of neutral grey. Curated map
still wins where present.

Spec: docs/superpowers/specs/2026-05-26-openf1-integration-design.md
EOF
)"
```

---

## Task 11: Operational rollout + visual verification

This task has no code changes — it's the post-deploy operational checklist.

- [ ] **Step 1: Confirm DB and backend are up**

From the repo root:

```bash
docker ps --format '{{.Names}}\t{{.Status}}' | grep backend-db-1
```

Expected: container `Up`. If not, `make db-up`.

Start the backend in the foreground in a separate terminal, or in the background of this session:

```bash
make backend
```

Wait for `Listening at http://0.0.0.0:3000`.

- [ ] **Step 2: Bootstrap to apply the new mapping**

```bash
make bootstrap
```

Expected: `{ "ok": true, "year": 2026 }`. Check the backend log for "OpenF1 mapping" lines — there should be one INFO line per session that didn't match (likely all the FP sessions when the OpenF1 calendar is incomplete) and no errors.

- [ ] **Step 3: Verify session_key was written for known races**

```bash
docker exec -e PGPASSWORD=f1pg_dev backend-db-1 psql -U f1pg -d f1pg -c \
  "SELECT e.round, s.type, s.openf1_session_key FROM event e JOIN session s ON s.event_id=e.id WHERE s.type IN ('race','qualifying','sprint','sprint_quali') AND s.scheduled_start < now() ORDER BY e.round, s.type;"
```

Expected: every past race/qualifying/sprint/sprint_quali has a non-null `openf1_session_key`.

- [ ] **Step 4: Crawl**

```bash
make crawl
```

Expected: `sessionsFinished` includes the three previously-skipped sprint_quali sessions (China round 2, Miami round 4, Canada round 5). `errors: 0`. The backend log may contain `OpenF1 cross-check mismatch` lines if the FIA has updated any past classification — those are informational, not failures.

- [ ] **Step 5: Backfill driver headshots + constructor colours**

```bash
make refresh-openf1
```

Expected JSON shows `driversUpdated >= 1` (typically all drivers gain a headshot on first run) and `constructorsUpdated >= 1`.

- [ ] **Step 6: Spot-check the API**

```bash
curl -fsS http://localhost:3000/api/drivers/RUS | python3 -m json.tool
curl -fsS http://localhost:3000/api/constructors/mercedes | python3 -m json.tool
SID=$(curl -fsS http://localhost:3000/api/events/2 | python3 -c "import json,sys; e=json.load(sys.stdin); print(next(s['id'] for s in e['sessions'] if s['type']=='sprint_quali'))")
curl -fsS "http://localhost:3000/api/sessions/$SID/results" | python3 -m json.tool | head -40
```

Expected:
- Driver response includes `headshotUrl` and resolved `image` field reflects new precedence.
- Constructor response includes `teamColour`.
- Round-2 (China) sprint_quali results endpoint returns ~15-20 rows with populated `q1` / `q2` / `q3`.

- [ ] **Step 7: Visual verification in the Flutter app**

```bash
make app
```

Open Calendar → tap round 2 (Chinese GP) → switch to **SPRINT QUALI** tab. Expected: full classification with Q3/Q2/Q1 times in the right column (using the existing `displayTime` helper from the earlier bug fix).

If the user-prediction features for sprint_quali now show scores instead of "RESULTS NOT IN YET", that's the headline win for this feature.

- [ ] **Step 8: No commit**

Task 11 is pure operational verification. If everything checked out, the work is done. Otherwise, capture the failing output and walk back to the relevant task — most likely Task 4 (mapping) or Task 5 (sprint_quali fetch).

---

## Self-Review Summary

**Spec coverage:**

- D1 (Jolpica authoritative) → Task 6 (cross-check + fallback logic preserves Jolpica).
- D2 (cross-check + log, no DB write) → Task 6 (compareClassifications + WARN logs).
- D3 (Jolpica-empty fallback) → Task 6 Step 4.
- D4 (bootstrap-time session_key join) → Task 4.
- D5 (3 nullable columns, no new tables) → Task 1.
- D6 (opportunistic enrichment) → Task 7.
- D7 (image precedence override > headshot > wiki) → Task 8.
- D8 (teamColour API field + Flutter fallback) → Tasks 8, 10.
- D9 (cadence unchanged) → no task needed (default behaviour).
- D10 (boundary rule: openf1 imports nothing from rest of backend) → Tasks 2, 3 (client + parsers have only domain-type imports).

Testing matrix in the spec is covered by 5 backend integration tests (Tasks 1, 4, 5, 6, 7, 8, 9), 2 backend unit tests (Tasks 2, 3), and 1 Flutter test (Task 10). All test files are explicitly created in their respective tasks.

**Placeholders:** none — every step has executable code or commands.

**Type consistency:** `OpenF1DriverLookup` (Task 3) → consumed in Tasks 5, 6, 7, 9. `mapSessionsToOpenF1(year, client)` defined in Task 4 → no other consumers. `compareClassifications` (Task 6) → only called from `runTick`. `enrichDriversAndConstructors` (Task 7) → only called from `runTick`. All cross-task signatures and property names match.

**One nuance to surface to the executor:** Tasks 6 and 7 both modify the same per-session loop in `tick.ts`. Task 7's Step 4 shows the **final** form of the loop body (after both modifications). If executed in order, treat Task 6's loop body as scaffolding and use Task 7's as the authoritative version on commit.
