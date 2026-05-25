# Data Foundation — Design

**Date:** 2026-05-25
**Status:** Approved (pending user review of this document)
**Sub-project:** 1 of 5 in the F1 Prediction Game rebuild

## Context

The current Flutter app calls the deprecated Ergast F1 API directly from screen widgets. There is no backend, no persistence, and prediction "scores" are hardcoded mock data. This sub-project establishes the data layer the rest of the rebuild depends on.

It is deliberately scoped to data only. User accounts, predictions, scoring, the pre-season questionnaire, and frontend redesign are separate sub-projects, each with their own design + plan + implementation cycle.

## Goal

Stand up a small Node/TypeScript backend on Render that crawls F1 results from Jolpica-F1 (the community Ergast replacement), stores them in Postgres, and exposes a read-only HTTP API. Deployable, observable, and consumable on its own — even before any other piece of the rebuild exists.

## Decisions

| # | Decision | Rationale |
|---|---|---|
| D1 | **Source:** Jolpica-F1 (`api.jolpi.ca/ergast/f1`) | Drop-in for the deprecated Ergast schema we already speak. Free, no key. |
| D2 | **Liveness:** Final results only, no live timing | Predictions are locked before sessions start; live timing is cosmetic. |
| D3 | **History scope:** Current season + forward only | Smallest deploy; matches what the prediction game actually needs. |
| D4 | **Crawl trigger:** Fixed cron cadence (every 15 min); session-aware filtering inside the tick | Cron stays simple; the tick decides whether there's work. Idle when nothing's running; timely when sessions end. |
| D5 | **Shape:** Crawler + minimal backend on Render (read-only API) | End-to-end pipeline validation in one sub-project. |
| D6 | **Runtime:** Node + Fastify + Postgres + Drizzle, TypeScript | Matches existing Node services; best Render support. |
| D7 | **Process:** One Render web service, internal `node-cron` scheduler (no separate cron service) | One deploy, one bill, simpler ops. |
| D8 | **Repo:** `backend/` directory in this same repo (sibling to `lib/`) | Frontend + backend versioned together for now. |
| D9 | **Images:** Wikipedia auto-fetch on first-seen, with manual-override column | Free + automatic. Override slot for future curated assets. |

## Architecture

Single Node process on Render with two concurrent jobs:

```
[Render Web Service]
  ├── Fastify HTTP server  → /api/* read routes + /admin/* gated routes
  └── node-cron scheduler  → crawler tick every 15 min
        │
        └── Jolpica client + Wikipedia client
        ▼
  [Render Postgres]
```

**Boundary rules:**
- `api/` → `repo/` only. Never directly to `jolpica/` or `crawler/`.
- `crawler/` → `jolpica/`, `wikipedia/`, `repo/`.
- `repo/` → `db/` only. Returns domain types, not raw rows.
- `domain/` has zero imports from sibling dirs.

## Entity model

Eight tables.

```
season                    event                          session
──────                    ─────                          ───────
year (PK)                 id (PK, serial)                id (PK, serial)
is_current (bool)         season_year (FK)               event_id (FK)
                          round (int)                    type (enum: fp1, fp2, fp3,
                          name                                       qualifying,
                          circuit_name                               sprint_quali,
                          country                                    sprint, race)
                          has_sprint (bool)              scheduled_start (timestamptz)
                          UNIQUE(season_year, round)     scheduled_end (timestamptz)
                                                         status (enum: scheduled, finished)
                                                         UNIQUE(event_id, type)

session_result                      driver
──────────────                      ──────
session_id (FK)                     code (PK)              e.g. 'VER'
position (int)                      given_name
driver_code (FK → driver.code)      family_name
driver_name                         nationality
constructor_id (FK)                 permanent_number
constructor_name                    wikipedia_url
race_time (text, nullable)          image_url (nullable)             ← Wikipedia auto
status (text, nullable)             image_url_override (nullable)    ← manual
points (int, nullable)
fastest_lap (text, nullable)        constructor
fastest_lap_time (text, nullable)   ───────────
fastest_lap_speed (text, nullable)  id (PK)                e.g. 'red_bull'
q1 (text, nullable)                 name
q2 (text, nullable)                 nationality
q3 (text, nullable)                 wikipedia_url
PRIMARY KEY(session_id, position)   image_url (nullable)
                                    image_url_override (nullable)

driver_standing                     constructor_standing
───────────────                     ────────────────────
season_year (FK)                    season_year (FK)
driver_code (FK)                    constructor_id (FK)
position (int)                      position (int)
points (int)                        points (int)
wins (int)                          wins (int)
constructor_id (FK)                 updated_at (timestamptz)
updated_at (timestamptz)            PRIMARY KEY(season_year, constructor_id)
PRIMARY KEY(season_year, driver_code)
```

**Notes:**
- One `session_result` table covers all session types; type-specific columns are nullable. Cheaper than per-type tables; better than JSONB for sorting/filtering.
- Standings are snapshots (current only, overwritten on refresh). If a "standings over time" view is wanted later, add `as_of_round` in a follow-up migration.
- The API serves `image_url_override ?? image_url` as a single `image` field — clients don't see the distinction.

## Data flow

### Bootstrap
Runs on app start if no `season.is_current=true` row exists, and via `POST /admin/bootstrap`.

1. `GET /f1/current.json` → upsert `season`, `event`, and all `session` rows for the season from the schedule block. Set `has_sprint` per event based on session-list contents.
2. For every session where `scheduled_end + 30 min < now()`, run an immediate tick step.

### Tick (every 15 min, `node-cron`)

1. Select candidate sessions: `status='scheduled' AND scheduled_end + 30min < now() AND scheduled_end > now() - 7 days`. The 7-day cap stops infinite re-tries on permanently-missing data.
2. For each candidate:
   - `GET` the right Jolpica endpoint by `session.type`:
     - `race` → `/f1/{year}/{round}/results.json`
     - `qualifying` → `/f1/{year}/{round}/qualifying.json`
     - `sprint` → `/f1/{year}/{round}/sprint.json`
     - `sprint_quali` → endpoint TBD (see Known Unknowns)
     - `fp1`/`fp2`/`fp3` → never fetched (no results stored for practice sessions)
   - On 200 with non-empty `Results`: upsert `session_result` rows; upsert `driver`/`constructor` lookup rows for unknowns; mark session `finished`; trigger Wikipedia image fetch for new drivers/constructors.
   - On 200 with empty / 404: no-op, retry next tick.
   - On 5xx/network: log + retry next tick.
3. If any session moved to `finished` in this tick: refetch `/f1/current/driverStandings.json` and `/f1/current/constructorStandings.json`, overwrite the two standings tables.
### Weekly schedule refresh
Separate `node-cron` entry, Mondays at 03:00 UTC: re-runs only the schedule portion of bootstrap (step 1) to catch FIA mid-season changes (race postponed, sprint added, etc.). Idempotent.

### Wikipedia image fetch (subroutine)
Called once per genuinely-new driver/constructor. Never automatically retried.

1. Extract page title from `wikipedia_url`.
2. `GET en.wikipedia.org/w/api.php?action=query&titles={title}&prop=pageimages&pithumbsize=400&format=json`.
3. Save thumbnail URL to `image_url`. On any failure: leave `null`; admin can hit `POST /admin/refresh-images` later.

### Concurrency & idempotency
- Single process + single scheduler. An `isRunning` flag in `scheduler.ts` skips overlapping ticks.
- All writes are upserts (`ON CONFLICT DO UPDATE`). Re-running bootstrap or a tick is safe.

## API surface

### Public (no auth in this sub-project)

```
GET  /api/health                       → { ok, db, lastTickAt, lastTickStatus }
GET  /api/seasons/current              → { year, isCurrent }
GET  /api/events                       → [{ round, name, country, hasSprint, sessions: [...] }]
GET  /api/events/:round                → single event with full session list
GET  /api/sessions/:id                 → session metadata
GET  /api/sessions/:id/results         → ordered results for a session
GET  /api/next-session                 → soonest scheduled session (countdown source)
GET  /api/standings/drivers            → ordered driver standings + image
GET  /api/standings/constructors       → ordered constructor standings + image
GET  /api/drivers/:code                → driver lookup
GET  /api/constructors/:id             → constructor lookup
```

### Admin (`X-Admin-Token: $ADMIN_TOKEN`)

```
POST /admin/bootstrap                  → re-run bootstrap (idempotent)
POST /admin/refresh-images             → re-attempt Wikipedia fetch for null image_urls
POST /admin/crawl                      → force an immediate tick
```

### Response conventions
- All times ISO-8601 UTC. Client converts to local.
- Points/positions as integers.
- Errors: `{ error: { code, message } }` with appropriate HTTP status. Codes are short strings (`NOT_FOUND`, `UPSTREAM_FAILURE`, `BAD_REQUEST`, `UNAUTHORIZED`).
- No pagination — whole season fits in one response for every endpoint here.

## Error handling

| Failure | Behavior |
|---|---|
| Jolpica 4xx | Log, skip this session this tick, retry next tick |
| Jolpica 5xx / timeout | Log, no in-tick retry; next tick tries again |
| Jolpica 200 + empty Results | Treat as "not yet published", no-op |
| Unknown driver/constructor in response | Insert lookup row from response fields; image stays null until Wikipedia call resolves |
| Wikipedia API failure | `image_url` stays null, no auto-retry |
| DB connection lost | `/api/health` flips `db: 'down'`; crawler tick aborts; next tick reconnects |
| Tick overlap | New tick skipped via in-process `isRunning` flag |
| 404 for not-yet-crawled data | Return 404 with `code: 'NOT_FOUND'`; client shows "not available yet" |
| Sprint Qualifying endpoint missing | Tick logs the 404 each attempt (a candidate session is retried every 15 min for 7 days, then stops via the 7-day cap). Manual override path comes in a later sub-project |

## Observability

- Logs to stdout as JSON. Render captures.
- `/api/health` includes `lastTickAt` and `lastTickStatus` so a basic uptime check covers both web and crawler.
- No metrics service yet. Revisit if log inspection becomes insufficient.

## Repo layout

```
backend/
├── package.json
├── tsconfig.json
├── drizzle.config.ts
├── render.yaml                  # Render Blueprint (web + Postgres)
├── docker-compose.yml           # local Postgres for dev/tests
├── src/
│   ├── index.ts                 # entry: Fastify + scheduler
│   ├── config.ts                # env parsing
│   ├── db/
│   │   ├── client.ts            # pg pool
│   │   ├── schema.ts            # Drizzle table defs
│   │   └── migrations/          # generated SQL
│   ├── domain/types.ts          # Session, SessionResult, Driver, Constructor, ...
│   ├── jolpica/
│   │   ├── client.ts            # typed fetch wrappers
│   │   └── parsers.ts           # Jolpica JSON → domain types
│   ├── wikipedia/client.ts
│   ├── crawler/
│   │   ├── bootstrap.ts
│   │   ├── tick.ts
│   │   └── scheduler.ts         # node-cron wiring + isRunning guard
│   ├── repo/
│   │   ├── seasons.ts
│   │   ├── events.ts
│   │   ├── sessions.ts
│   │   ├── results.ts
│   │   ├── standings.ts
│   │   ├── drivers.ts
│   │   └── constructors.ts
│   └── api/
│       ├── routes/
│       │   ├── public.ts
│       │   └── admin.ts
│       └── errors.ts
└── test/
    ├── fixtures/                # captured Jolpica + Wikipedia JSON
    ├── unit/
    └── integration/
```

## Deploy

`render.yaml` (committed):

```yaml
databases:
  - name: f1pg-db
    plan: free               # 90-day expiry; upgrade before live
    postgresMajorVersion: 16

services:
  - type: web
    name: f1pg-backend
    runtime: node
    plan: free
    buildCommand: npm ci && npm run build && npm run db:migrate
    startCommand: npm start
    healthCheckPath: /api/health
    envVars:
      - key: DATABASE_URL
        fromDatabase: { name: f1pg-db, property: connectionString }
      - key: ADMIN_TOKEN
        generateValue: true
      - key: NODE_ENV
        value: production
```

- Migrations run on every deploy via Drizzle.
- No staging environment in this sub-project. Add when prediction-writes land.

## Testing strategy

| Layer | Approach |
|---|---|
| Jolpica parsers | Unit, fixture-based. One fixture per session type + "missing sprint quali" fixture. |
| Wikipedia client | Unit, fixture-based. |
| Crawler tick | Integration. Real Postgres (testcontainer / CI service), stubbed `fetch` returning fixtures. Drive the tick, assert DB state. |
| Repo functions | Integration against real Postgres. No DB mocking. |
| API routes | `fastify.inject()` against a real DB seeded with known fixtures. |
| End-to-end | Out of scope here. Add when UI consumes the API. |

Local dev DB: `docker compose up db`. CI DB: GitHub Actions Postgres service container.

## Done-list (definition of done for this sub-project)

- [ ] `backend/` scaffold builds and starts locally
- [ ] All eight tables migrated cleanly
- [ ] Bootstrap populates current-season schedule from Jolpica
- [ ] Tick fetches finished sessions and writes results
- [ ] Wikipedia images backfilled on first-seen
- [ ] All public read endpoints return real data
- [ ] Admin endpoints work behind `X-Admin-Token`
- [ ] `/api/health` reports DB + last-tick status accurately
- [ ] Deployed to Render via the blueprint, reachable over HTTPS
- [ ] Sprint Qualifying behavior verified against actual Jolpica responses (see Known Unknowns)

## Known unknowns

1. **Sprint Qualifying ("Sprint Shootout") endpoint.** The Saturday-morning short qualifying introduced in 2023 may not be a distinct Jolpica/Ergast endpoint. We will verify at implementation time. Fallbacks, in order: (a) skip the session type until source becomes available; (b) add a manual-result admin endpoint in a later sub-project.
2. **Jolpica rate limits.** Read their docs during implementation; respect them. Current shape (a handful of calls every 15 min, bursting only on session end) is very light.
3. **Render free Postgres 90-day expiry.** Decide before that window closes whether to upgrade plan or migrate.

## Out of scope (next sub-projects)

- User accounts, auth.
- Prediction submission and storage.
- Scoring engine (Quali Top-2, Race Top-5, SprintQuali Top-1, Sprint Top-3).
- Pre-season questionnaire (form, storage, season-end resolution).
- Flutter UI redesign.

Each of the above gets its own design → plan → implementation cycle.
