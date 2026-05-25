# Pre-Season Questionnaire & Scoring — Design

**Date:** 2026-05-25
**Status:** Approved (pending user review of this document)
**Sub-project:** 4 of 4 in the F1 Prediction Game rebuild (final backend sub-project; bundles storage + scoring)

## Context

Sub-projects 1-3 built the data foundation, the identity layer, and per-session predictions with auto-scoring. This sub-project adds the season-long pre-season questionnaire: a small set of bets a user makes before the season starts, scored at season end against either crawled F1 data or admin-set ground truth.

This is the last backend slice of the rebuild. After this lands, the only remaining work is the Flutter UI redesign (a parallel track outside the backend).

## Goal

Let each user submit 8 pre-season picks (six small categories + two full ordered lists), lock the questionnaire at the season's first session, and pay out points to the same `score` table the existing leaderboards already sum. Same single-Node-process + Postgres + cron-driven shape as the prior sub-projects.

## Scoring scheme

| Category | Picks | Points awarded | Max |
|---|---|---|---|
| **Biggest surprise** | 1 driver + 1 team | 4 each match | 8 |
| **Biggest disappointment** | 1 driver + 1 team | 4 each match | 8 |
| **Most DNFs over season** | 1 driver + 1 team | 4 each match | 8 |
| **Most poles** | 1 driver + 1 team | 4 each match | 8 |
| **Most fastest laps** | 1 driver + 1 team | 4 each match | 8 |
| **WDC + WCC** | 1 driver + 1 team | 4 each match | 8 |
| **Complete championship** | ~20 drivers ordered + ~10 teams ordered | 3 per correctly-placed driver + 4 per correctly-placed team | 100 |

**Per-season max: 148 pts.**

The first two categories are subjective — there's no F1 data that declares the "surprise of the season." An admin sets ground truth at season end via a token-gated endpoint. The other five categories are derived from the existing `session_result`, `driver_standing`, and `constructor_standing` tables the crawler already populates.

## Decisions

| # | Decision | Rationale |
|---|---|---|
| D1 | **Bundle storage + scoring + admin truth endpoint** | Same pattern that worked for sub-project 3. One cohesive slice. |
| D2 | **One questionnaire per user per season, globally scoped** | Same shape as session predictions. Leagues are a leaderboard filter, not a prediction scope. |
| D3 | **Lock at first session of season's first round** | First session of round 1 (FP1 typically). Captures everyone's picks before any on-track running. Computed from existing schedule data — no new config. |
| D4 | **Surprise / disappointment resolved by admin at season end** | Subjective categories have no objective F1 data. Admin sets the 4 truth picks via `POST /admin/seasons/:year/subjective-truth`. Until set, those categories score 0. |
| D5 | **Each category submitted independently** | A user can fill out poles + WDC without touching the championship ordering. All categories lock at the same moment. |
| D6 | **Strict exact-position match on standings** | "Right driver, wrong slot" gets no credit. Matches the user's stated rule ("je Fahrer 3Pkt" / "je Team 4Pkt"). |
| D7 | **Preseason scores live in the existing `score` table, discriminated by a new `kind` column** | Existing league leaderboard SQL sums everything automatically when filtered by season. Migration is small. Alternative (separate `preseason_score` + UNION) doubles schema and complicates leaderboard SQL. |
| D8 | **Auto-rescore preseason on every tick that refreshes standings** | Same idempotent upsert pattern as session rescore. Cheap (10 users × 7 categories per call). Standings updates flow into scores automatically. |
| D9 | **No partial credit on standings** | Per the user's rule. If we wanted "wrong slot, half points" later, it's an additive scoring change (rule version bump). |

## Architecture

```
[ Node process — unchanged shape ]
  ├── Fastify HTTP
  │     ├── (existing) /api/* /api/auth/* /api/leagues/* /api/predictions/* /api/sessions/:id/*
  │     ├── /api/preseason/*                  (NEW)
  │     ├── /api/users/me/preseason-scores    (NEW)
  │     ├── /api/seasons/:year/preseason-truth (NEW; after-lock only)
  │     └── /admin/seasons/:year/subjective-truth, /admin/preseason-rescore/:year (NEW)
  └── Scheduler
        └── existing 15-min tick now ALSO rescores preseason after standings refresh
```

**New leaf module `src/preseason/`** mirrors `src/scoring/`:
- 7 pure scorer files (1 per category, `standings` consumes the long ordered list).
- `derive.ts` — pure functions that compute observed truth from `session_result` + `driver_standing` + `constructor_standing` rows.
- `index.ts` — dispatcher.
- `rescorer.ts` — DB-aware orchestrator (sanctioned `repo/` import exception).

**Boundary rules** extend cleanly from prior sub-projects:
- `preseason/` is leaf-level except `rescorer.ts` (sanctioned `repo/` import).
- `repo/` → `db/`, `domain/` only.
- `api/` → `repo/`, `preseason/`, `scoring/`, `auth/`, `domain/`.
- `crawler/tick.ts` now also calls `preseason/rescorer.ts`.

No new infrastructure. No new dependencies.

## Entity model

Three new tables, one Postgres enum, plus a non-trivial change to the existing `score` table.

```
preseason_pick                                preseason_pick_standings_driver
──────────────                                ───────────────────────────────
user_id        uuid  FK → user(id)            user_id     uuid FK → user(id) ON DELETE CASCADE
season_year    int   FK → season(year)        season_year int  FK → season(year) ON DELETE CASCADE
category       enum  preseason_category       position    int  NOT NULL
driver_code    text  NULL FK → driver(code)   driver_code text NOT NULL FK → driver(code)
constructor_id text  NULL FK → constructor(id) PK (user_id, season_year, position)
updated_at     timestamptz DEFAULT now()      UNIQUE (user_id, season_year, driver_code)
PK (user_id, season_year, category)           INDEX (season_year)
INDEX (season_year, category)

preseason_pick_standings_constructor          subjective_truth
────────────────────────────────────          ────────────────
user_id        uuid FK → user(id) CASCADE     season_year                   int PK FK → season(year) ON DELETE CASCADE
season_year    int  FK → season(year) CASCADE surprise_driver_code          text NULL FK → driver(code)
position       int  NOT NULL                  surprise_constructor_id       text NULL FK → constructor(id)
constructor_id text NOT NULL FK → constructor(id) disappointment_driver_code     text NULL FK → driver(code)
PK (user_id, season_year, position)           disappointment_constructor_id  text NULL FK → constructor(id)
UNIQUE (user_id, season_year, constructor_id) set_at                        timestamptz DEFAULT now()
INDEX (season_year)

preseason_category enum values:
  surprise | disappointment | dnf | poles | fastest_lap | wdc_wcc
```

**Both `driver_code` and `constructor_id` are nullable in `preseason_pick`** — a user can fill only one half. The route layer enforces "at least one non-null" so the database stays permissive.

### Score table change (migration 0004)

```sql
ALTER TABLE "score" ADD COLUMN "kind" text NOT NULL DEFAULT 'session';
ALTER TABLE "score" ADD COLUMN "season_year" integer NULL;
ALTER TABLE "score" ADD COLUMN "preseason_category" text NULL;
ALTER TABLE "score" ALTER COLUMN "session_id" DROP NOT NULL;
ALTER TABLE "score" DROP CONSTRAINT "score_pk";
CREATE UNIQUE INDEX "score_session_uq"   ON "score" ("user_id", "session_id")
  WHERE kind = 'session';
CREATE UNIQUE INDEX "score_preseason_uq" ON "score" ("user_id", "season_year", "preseason_category")
  WHERE kind = 'preseason';
```

- Existing session score rows keep `kind='session'`, `session_id NOT NULL`, `season_year NULL`, `preseason_category NULL`.
- Preseason score rows have `kind='preseason'`, `session_id NULL`, `season_year NOT NULL`, `preseason_category` one of 7 values: `surprise`, `disappointment`, `dnf`, `poles`, `fastest_lap`, `wdc_wcc`, `standings`.
- Two partial unique indexes enforce one-per-kind. Old PK is dropped (replaced by these).
- **Note:** `score.preseason_category` is plain `text`, NOT the `preseason_category` enum. The enum only covers the 6 single-pick categories; the score table additionally stores `'standings'` to represent the full-ordering category's score row. Keeping it as text keeps these two concerns decoupled.

**Leaderboard SQL change** (Task 7 in plan): the existing `leagueLeaderboard` filters scores by `event.season_year`. Update it to also include preseason rows that match `season_year` directly (since they have no session→event chain). One small SQL extension; existing session-row behavior unchanged.

## Scoring engine

**Shared types** (`src/preseason/types.ts`):

```ts
export type PreseasonPick = { driverCode: string | null; constructorId: string | null }
export type StandingsPick = { position: number; entityId: string }

export type PreseasonPerEntityScore = {
  picked: string | null
  truth:  string | null
  correct: boolean
  points: number
}

export type PreseasonScoreBreakdown = {
  driver?: PreseasonPerEntityScore
  team?:   PreseasonPerEntityScore
  perPosition?: { position: number; picked: string; truth: string | null; correct: boolean; points: number }[]
  pointsTotal: number
  rule: string
}
```

### Seven scorers

| File | Inputs | Logic | Max | Rule string |
|---|---|---|---|---|
| `surprise.ts` | pick, subjective truth | driver match: +4; team match: +4 | 8 | `preseason-surprise-v1` |
| `disappointment.ts` | pick, subjective truth | driver match: +4; team match: +4 | 8 | `preseason-disappointment-v1` |
| `dnf.ts` | pick, observed (most DNFs driver/team) | +4/+4 | 8 | `preseason-dnf-v1` |
| `poles.ts` | pick, observed (most poles driver/team) | +4/+4 | 8 | `preseason-poles-v1` |
| `fastestLap.ts` | pick, observed (most FLs driver/team) | +4/+4 | 8 | `preseason-fastest-lap-v1` |
| `wdcWcc.ts` | pick, observed (WDC, WCC at season end) | +4/+4 | 8 | `preseason-wdc-wcc-v1` |
| `standings.ts` | drivers picks + teams picks + final standings | +3 per correctly-placed driver; +4 per correctly-placed team | 100 | `preseason-standings-v1` |

### Dispatcher (`src/preseason/index.ts`)

```ts
export type PreseasonCategory =
  | 'surprise' | 'disappointment' | 'dnf' | 'poles' | 'fastest_lap' | 'wdc_wcc'

export function scorePreseasonCategory(
  category: PreseasonCategory,
  pick: PreseasonPick,
  observedOrTruth: PreseasonPick
): PreseasonScoreBreakdown
```

`standings` is dispatched separately because its input shape is different (ordered lists, not single picks).

### Observed-truth derivation (`src/preseason/derive.ts`)

Pure functions over crawled data:

- `deriveMostDnfs(results)` — counts DNF-status finishes (`Retired`, `Accident`, `Engine`, `Collision`, `Mechanical`, `Spun off`, `Withdrew`, `Did not start`) across all race + sprint sessions in the season. Returns `(driverCode with most, constructorId with most aggregate)`. Ties broken by lowest standings position (best driver wins).
- `derivePolesitter(results)` — counts `position=1` in `qualifying` sessions only (main qualifying — sprint shootout excluded by default). Returns `(driver, team)`.
- `deriveMostFastestLaps(results)` — counts `fastest_lap = '1'` rows in `race` sessions. Returns `(driver, team)`.
- `deriveWdcWcc(driverStandings, constructorStandings)` — picks `position=1` from each.
- `deriveFinalStandings(driverStandings, constructorStandings)` — returns the two ordered lists in position order.

Each is a pure data-in → data-out function with fixture-driven unit tests.

### Rescorer (`src/preseason/rescorer.ts`)

```ts
export async function rescorePreseasonForSeason(seasonYear: number): Promise<{ users: number; totalPoints: number }>
```

1. Load season; if no standings exist yet, no-op return `{ users: 0, totalPoints: 0 }`.
2. Derive observed truths from `results` + `driver_standing` + `constructor_standing` (via `derive.ts`).
3. Load admin-set subjective truth (may be null → those categories score 0).
4. For each user with at least one preseason pick or standings row, score all 7 categories, upsert into `score` table with `kind='preseason'`.
5. Return summary.

Idempotent: upsert key is `(user_id, kind='preseason', season_year, preseason_category)`.

## API surface

All authenticated unless noted. Uses the existing `registerAuthHook`.

### Questionnaire (per category, independent submission)

| Method | Path | Notes |
|---|---|---|
| GET | `/api/preseason/my` | Caller's full questionnaire state for current season: `{ surprise, disappointment, dnf, poles, fastest_lap, wdc_wcc, standings: { drivers, constructors }, isLocked, locksAt }`. Missing categories return `null`. |
| PUT | `/api/preseason/:category` | Submit/replace caller's single-pick category. Body: `{ driverCode?, constructorId? }` (at least one required). 409 if locked. Idempotent. |
| DELETE | `/api/preseason/:category` | Remove caller's pick. 409 if locked. |
| PUT | `/api/preseason/standings/drivers` | Replace full driver ordering. Body: `{ picks: [{ position, driverCode }, ...] }`. 409 if locked. |
| PUT | `/api/preseason/standings/constructors` | Replace full team ordering. 409 if locked. |
| DELETE | `/api/preseason/standings/drivers` | Clear caller's driver ordering. 409 if locked. |
| DELETE | `/api/preseason/standings/constructors` | Clear caller's team ordering. 409 if locked. |

### Public view (after lock)

| Method | Path | Notes |
|---|---|---|
| GET | `/api/seasons/:year/preseason-truth` | Returns observed truths + subjective truth (if set) + everyone's picks per category. 403 before lock. |

### Score views

| Method | Path | Notes |
|---|---|---|
| GET | `/api/users/me/preseason-scores` | Caller's preseason score history for the season: 7 rows with category, breakdown JSONB, points. |

The existing `/api/leagues/:id/leaderboard` and `/api/leagues/:id/leaderboard/sessions` automatically include preseason rows after the leaderboard SQL extension.

### Admin

| Method | Path | Notes |
|---|---|---|
| POST | `/admin/seasons/:year/subjective-truth` | Body: `{ surpriseDriverCode, surpriseConstructorId, disappointmentDriverCode, disappointmentConstructorId }`. Upserts the row, then triggers `rescorePreseasonForSeason(year)` and returns the summary. |
| POST | `/admin/preseason-rescore/:year` | Force rescore of all preseason categories. Token-gated. |

### Validation (zod)

- **Single-pick body**: at least one of `driverCode`/`constructorId` present. If present, must exist in `driver`/`constructor` table and be in current season's standings (`driverHasStandingForYear` / equivalent for constructors).
- **Standings body**: `positions` form exactly `[1..N]` (no gaps, no duplicates), where N is the season's driver/constructor count from the standings table. All entities exist and are in the current season.
- **Path `:category`**: must be one of the 6 enum values (route rejects with `BAD_REQUEST` otherwise).
- **Subjective-truth body**: all 4 fields required; each must exist in the appropriate table.

### Response shapes

- Single-pick: `{ category, driverCode, constructorId, updatedAt }`.
- Standings: `{ picks: [{ position, driverCode | constructorId }, ...sorted asc by position...] }`.
- Score rows: include the full `breakdown` JSONB verbatim for UI replay (same approach as session scores in sub-project 3).

## Lock enforcement + crawler integration

### Lock helper

```ts
async function getPreseasonLockTime(seasonYear: number): Promise<Date | null> {
  const ev = await eventsRepo.getByRound(seasonYear, 1)
  if (!ev) return null
  const sessions = await sessionsRepo.listForEvent(ev.id)
  if (sessions.length === 0) return null
  return sessions
    .sort((a, b) => a.scheduledStart.getTime() - b.scheduledStart.getTime())[0]!
    .scheduledStart
}

async function requireQuestionnaireUnlocked(seasonYear: number): Promise<void> {
  const lockAt = await getPreseasonLockTime(seasonYear)
  if (lockAt && lockAt.getTime() <= Date.now()) {
    throw new ApiError('CONFLICT', 'Pre-season questionnaire is locked')
  }
}
```

If schedule isn't bootstrapped (no round 1 event), the questionnaire is treated as open. Round 1 in the past locks all mutations.

Mirror helper `requireQuestionnaireLocked` gates `/api/seasons/:year/preseason-truth` (other users' picks visible only after lock).

`GET /api/preseason/my` returns `isLocked: boolean` + `locksAt: Date | null` so the UI doesn't need a second round trip.

### Tick integration

Single new call in `src/crawler/tick.ts`, placed just after the standings refresh block (since preseason derivations read both `session_result` and standings):

```ts
try {
  const summary = await rescorePreseasonForSeason(cur.year)
  console.log('Preseason rescored', { year: cur.year, ...summary })
} catch (err) {
  console.error('Preseason rescore failed', err)
}
```

Wrapped in try/catch so a preseason rescore failure doesn't fail the tick (same pattern as session rescore).

Triggered ~every tick that finishes a session in the current season — handful of times per race weekend, cheap in-memory derivation.

### Subjective-truth endpoint also triggers a rescore

`POST /admin/seasons/:year/subjective-truth` upserts the row, then synchronously calls `rescorePreseasonForSeason(year)`. The admin gets the rescore summary back in the response.

### Empty-truth handling

When subjective truth hasn't been set yet, `surprise`/`disappointment` score 0. When standings exist but season isn't complete, scores reflect the current-as-of-now picture — leaderboards always show what's been scored to date. Same approach as session scoring in sub-project 3.

## Errors

No new `ApiErrorCode` variants. Existing set covers all cases:

| Code | Used for |
|---|---|
| `NOT_FOUND` | Season not found; no pick for caller in category |
| `UNAUTHORIZED` | Bearer or admin-token failure |
| `FORBIDDEN` | Viewing others' picks before lock |
| `CONFLICT` | Submit/edit/delete after lock |
| `VALIDATION` | zod parse failure; wrong picks count for standings; unknown driver/team; entity not in current season; duplicate driver/team in standings |
| `BAD_REQUEST` | Non-numeric `:year`; unknown `:category` value |

## Code layout

```
backend/src/
  preseason/                NEW
    types.ts                Pick, StandingsPick, ScoreBreakdown
    surprise.ts             scorer (pure)
    disappointment.ts       scorer (pure)
    dnf.ts                  scorer (pure)
    poles.ts                scorer (pure)
    fastestLap.ts           scorer (pure)
    wdcWcc.ts               scorer (pure)
    standings.ts            scorer (pure)
    derive.ts               observed-truth derivation (pure)
    index.ts                dispatcher
    rescorer.ts             DB-aware orchestrator
  api/
    routes/
      preseason.ts          NEW — /api/preseason/* + /api/seasons/:year/preseason-truth + /api/users/me/preseason-scores
      admin.ts              EXTEND — subjective-truth + preseason-rescore endpoints
  repo/
    preseasonPicks.ts       NEW
    preseasonStandings.ts   NEW
    subjectiveTruth.ts      NEW
    scores.ts               MODIFY — leaderboard SQL handles preseason rows; new upsertPreseasonScore
  db/
    schema.ts               EXTEND — add 3 tables + enum + score table column changes
    migrations/
      0004_preseason.sql    NEW — extensions, enum, 3 tables, score column changes
  crawler/
    tick.ts                 MODIFY — invoke rescorePreseasonForSeason after standings refresh
```

`src/index.ts` registers `preseason.ts` route group alongside the existing ones.

## Testing

Same conventions as prior sub-projects: vitest single-fork, real Postgres on 5433, `truncateAll` in `beforeEach`. The 3 new tables added to `TABLES`.

### Unit tests (`test/unit/preseason/*.test.ts`)

Pure functions, no DB. Highest-value because scoring math is what users scrutinize.

- `surprise.test.ts` — driver match, team match, both, neither, truth not set (null truth → 0).
- `disappointment.test.ts` — same shape.
- `dnf.test.ts`, `poles.test.ts`, `fastestLap.test.ts`, `wdcWcc.test.ts` — driver match / team match / both / neither.
- `standings.test.ts` — all correct, none correct, some correct, picks shorter than truth, picks longer than truth.
- `dispatcher.test.ts` — unknown category throws.
- `derive.test.ts` — derive functions against fixture data: most DNFs across mixed status values, most poles across multiple qualifying sessions, fastest laps, WDC/WCC, full standings ordering.

### Integration tests (`test/integration/`)

- `repo_preseasonPicks.test.ts` — insert/update/delete per category, cascade from user delete, partial picks (driver only, team only).
- `repo_preseasonStandings.test.ts` — replace-all atomicity, unique-driver-per-user-per-season constraint, listing in position order.
- `repo_subjectiveTruth.test.ts` — upsert overwrite, null fields, cascade from season delete.
- `preseason_rescorer.test.ts` — write picks + results + standings, rescore, verify 7 score rows with correct breakdowns; update standings, rescore again, verify overwrite.
- `crawler_tick_preseason_rescore.test.ts` — full tick path with a preseason pick in DB, verify preseason scores appear after tick.
- `api_preseason.test.ts` — full route flow: signup → submit each category → edit before lock → 409 after lock → GET `/api/preseason/my` returns full state.
- `api_admin_subjective_truth.test.ts` — set truth → rescore runs → surprise/disappointment scores update; token gate verified.
- `api_users_me_preseason_scores.test.ts` — pick → results crawl → score appears in caller's preseason history.
- `api_leaderboard_with_preseason.test.ts` — regression: existing league leaderboard SQL still correct with preseason rows mixed in. Critical because the `score` table mutation is non-trivial.

### Test data builders

`test/helpers/factories.ts` gains:
```ts
makePreseasonPick(userId, seasonYear, category, { driverCode?, constructorId? })
makePreseasonStandings(userId, seasonYear, kind: 'driver' | 'constructor', orderedIds: string[])
setSubjectiveTruth(seasonYear, { surpriseDriverCode, ... })
```

### Out of scope for tests

- Wall-clock lock behavior (use past/future `scheduledStart` directly in fixtures).
- Load testing leaderboard queries.

## What's explicitly NOT in this sub-project

- Per-league questionnaires (sticks with the global-pick / league-leaderboard split from sub-project 3).
- Draft state — submissions are immediately live, just editable until lock.
- Partial credit on standings (per the user's rule; could be added as a `v2` rule later).
- Notifications/reminders about the lock approaching.
- A "see all my picks across all seasons" archive view.
- Flutter UI changes (parallel sub-project).
