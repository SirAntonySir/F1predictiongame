# Predictions & Scoring — Design

**Date:** 2026-05-25
**Status:** Approved (pending user review of this document)
**Sub-project:** 3 of 5 in the F1 Prediction Game rebuild (bundled scope — predictions storage + scoring engine)

## Context

Sub-projects 1 and 2 built the data foundation (sessions, results, standings) and the identity layer (users, sessions, leagues). The backend currently has nothing connecting them — a logged-in user has no way to do anything with the F1 data.

This sub-project adds the heart of the app: each user submits predictions for upcoming F1 sessions, the crawler auto-scores them when results arrive, and leagues expose member-only leaderboards.

It is deliberately bundled. The original 5-sub-project plan kept storage and scoring separate, but the scoring rules turned out to be specific enough that storage shape and scoring rules are tightly coupled — designing them in one slice avoids a schema-then-revise cycle. This sub-project also collapses the "5-of-5" count to "4-of-4": only the pre-season questionnaire and Flutter redesign remain after this lands.

## Goal

Let an authenticated user submit picks for each predictable session of a race weekend, lock those picks at the session's scheduled start, auto-score them when the crawler writes results, and surface league-scoped leaderboards. All in the same single-Node-process + Postgres shape as sub-projects 1 and 2.

## Scoring scheme

Per race weekend, four kinds of predictable sessions:

| Component | Picks | Per-position exact | Right driver, wrong position | Team bonus | Max |
|---|---|---|---|---|---|
| **Qualifying** (P1, P2) | 2 ordered | 3 pts each | 1 pt each | +1 pt if pole-pick's team = pole-actual's team | 7 |
| **Sprint Shootout** (sprint_quali) | 1 (P1) | 1 pt | — | +1 pt if P1-pick's team = P1-actual's team | 2 |
| **Sprint Race** (P1, P2, P3) | 3 ordered | 2 pts each | 1 pt each | +1 pt if winning team correct | 7 |
| **Race** (P1–P5) | 5 ordered | 3 pts each | 1 pt each | +2 pts if winning team correct | 17 |

**Per weekend max:** 24 without sprint (7 quali + 17 race), 33 with sprint (7 quali + 2 shootout + 7 sprint race + 17 race). Per season: 24 × 23 = 552 plus sprint bonuses for the sprint weekends.

**Team is derived from the picked driver**, not stored. `picks[P1].driver.constructor == result[P1].driver.constructor` triggers the team bonus. Drivers and their constructor are already linked via `session_result.constructor_id`.

## Decisions

| # | Decision | Rationale |
|---|---|---|
| D1 | **Bundle predictions + scoring** in one sub-project | Schema shape and scoring rules are tightly coupled — avoid revising one after building the other. |
| D2 | **One prediction per user per session, globally scoped** | Same picks count in every league the user belongs to. Simpler schema (no league_id on predictions), simpler UX (fill out once). Leagues are a leaderboard filter, not a prediction scope. |
| D3 | **Lock at the predicted session's scheduled_start** | Already-present column on the existing `session` table. No buffer, no per-type offset. Matches existing Flutter app behavior. |
| D4 | **Auto-recompute on every result update** | When the tick writes session_result rows, the rescorer runs for that session. Handles FIA penalty corrections automatically. |
| D5 | **One JSONB breakdown per (user, session) score row** | Stores per-position component points + team bonus verbatim. UI replays without recomputing. Includes a `rule` version string for audit when scoring formulas change. |
| D6 | **No partial-credit "podium-presence" bonus** beyond what's in the scoring table | Rules are: exact position (full), right driver in wrong position (1 pt), team bonus. No "you got someone on the podium somewhere" credit. |
| D7 | **Drivers picked must be in the current season** | Enforced at the route layer by joining `driver_standing`. Prevents picking retired drivers. |
| D8 | **Other users' predictions stay private until lock** | Reading anyone else's picks before lock returns 403. After lock, full session prediction list is open. |

## Architecture

Slot into the existing `api → repo → db` shape with two new leaf modules.

```
[ Node process — unchanged shape ]
  ├── Fastify HTTP
  │     ├── existing /api/*, /api/auth/*, /api/leagues/*, /admin/*
  │     ├── /api/predictions/*          (NEW — authenticated)
  │     ├── /api/sessions/:id/...       (NEW endpoints under existing prefix)
  │     ├── /api/leagues/:id/leaderboard (NEW — authenticated + member)
  │     ├── /api/users/me/scores         (NEW — authenticated)
  │     └── /admin/rescore-*             (NEW — token-gated)
  └── Scheduler
        ├── existing 15-min tick now ALSO rescores any session whose results changed
        └── (unchanged: weekly schedule refresh, daily session sweeper)
```

**Boundary additions:**
- `scoring/` is a new leaf module. Pure functions only. No imports from `repo/`, `api/`, `db/`. Inputs are plain TypeScript data; outputs are plain TypeScript data.
- `scoring/rescorer.ts` is the one exception inside `scoring/` — it imports from `repo/` to bridge the pure scorer to the database. Same sanctioned-exception pattern as `auth/sweeper.ts` in sub-project 2.
- `crawler/` now also imports from `scoring/rescorer.ts`. Additive to the existing `crawler/ → jolpica, wikipedia, repo` rule.

## Entity model

Three new tables. UUIDs for new entities; FK to existing `session(id)` keeps int (cross-type FKs are fine in Postgres).

```
prediction
──────────
id              uuid PK DEFAULT gen_random_uuid()
user_id         uuid FK → user(id)    ON DELETE CASCADE
session_id      int  FK → session(id) ON DELETE CASCADE
created_at      timestamptz DEFAULT now()
updated_at      timestamptz DEFAULT now()
UNIQUE (user_id, session_id)              -- one prediction per (user, session)
INDEX  (session_id)                       -- for "all predictions for this session" lookup

prediction_pick
───────────────
prediction_id   uuid FK → prediction(id) ON DELETE CASCADE
position        int   NOT NULL            -- 1, 2, 3... up to whatever the session type needs
driver_code     text  FK → driver(code)
PK (prediction_id, position)
INDEX (driver_code)                       -- for "who picked driver X" queries

score
─────
user_id         uuid FK → user(id)    ON DELETE CASCADE
session_id      int  FK → session(id) ON DELETE CASCADE
points_total    int  NOT NULL
breakdown       jsonb NOT NULL
computed_at     timestamptz NOT NULL DEFAULT now()
PK (user_id, session_id)
INDEX (session_id)                        -- per-session leaderboard
INDEX (user_id)                           -- per-user history
```

**Breakdown JSONB shape** (stable per session type, includes a version string):

```json
{
  "perPosition": [
    { "position": 1, "exact": true,  "wrongPos": false, "points": 3 },
    { "position": 2, "exact": false, "wrongPos": true,  "points": 1 }
  ],
  "teamBonus": { "applied": true, "points": 1 },
  "rule": "qualifying-v1"
}
```

**Cascades:** Deleting a user → cascades into their predictions (then picks) and scores. Deleting a session (unlikely) → cascades the same way. No orphans possible.

**Migration `0003_predictions.sql`** + drizzle-kit snapshot, following the hand-written-SQL + auto-generated-snapshot pattern that landed cleanly in sub-project 2.

## Scoring engine

Four pure scorers, one dispatcher.

```ts
type Pick      = { position: number; driverCode: string }
type Finisher  = { position: number; driverCode: string; constructorId: string }
type ScoreBreakdown = {
  perPosition: { position: number; exact: boolean; wrongPos: boolean; points: number }[]
  teamBonus:   { applied: boolean; points: number }
  rule:        string
}
type Scorer = (picks: Pick[], finishers: Finisher[]) => ScoreBreakdown
```

| File | Session type | Picks | Per-pos exact | Wrong-pos | Team bonus rule | Max |
|---|---|---|---|---|---|---|
| `scoring/qualifying.ts` | `qualifying` | 2 | 3 | 1 | +1 if P1-pick's team == pole-actual's team | 7 |
| `scoring/sprintShootout.ts` | `sprint_quali` | 1 | 1 | — | +1 if P1-pick's team == P1-actual's team | 2 |
| `scoring/sprintRace.ts` | `sprint` | 3 | 2 | 1 | +1 if P1-pick's team == winner team | 7 |
| `scoring/race.ts` | `race` | 5 | 3 | 1 | +2 if P1-pick's team == winner team | 17 |

**Dispatcher** (`scoring/index.ts`):
```ts
scoreSession(type: SessionType, picks: Pick[], finishers: Finisher[]): ScoreBreakdown
```
Switches on type. Throws if called with picks of wrong count for the type, or with an unknown type. Defensive — the route layer should have rejected first.

**Rescorer** (`scoring/rescorer.ts`):
```ts
rescoreSession(sessionId: number): Promise<{ users: number; totalPoints: number }>
```
1. Load session (need its `type`). If `type` isn't one of the four scorable kinds, return `{ users: 0, totalPoints: 0 }` immediately — no-op.
2. Load all predictions + picks for the session (one DB call, joined).
3. Load session results joined with `driver → constructor_id` (already a single repo call after a small extension to `repo/results.ts`).
4. For each user, call `scoreSession(...)` and upsert into `score`.
5. Return summary.

If no results exist (session not yet finished, or has no Jolpica data), the rescorer returns `{ users: 0, totalPoints: 0 }` without writing — scores only exist once results do.

**Rule versioning.** Each breakdown carries `"rule": "<type>-v1"`. If scoring formulas ever change, bump the version. Old `score` rows keep their previous breakdown until the next rescore overwrites them.

## API surface

All authenticated unless noted. Uses the existing `registerAuthHook` + league guards from sub-project 2.

### Predictions

| Method | Path | Notes |
|---|---|---|
| GET | `/api/predictions/upcoming` | All upcoming scorable sessions (`qualifying`/`sprint_quali`/`sprint`/`race`) in the current season, chronological. Each entry: `{ session, event, picksRequired, locksAt, myPicks?, isLocked }`. `myPicks` present only if caller has already submitted. |
| GET | `/api/sessions/:id/my-prediction` | Caller's prediction for one session. 404 if none. |
| PUT | `/api/sessions/:id/my-prediction` | Submit or replace caller's prediction. Body: `{ picks: [{ position, driverCode }, ...] }`. Idempotent. 409 if locked. |
| DELETE | `/api/sessions/:id/my-prediction` | Remove caller's prediction. 409 if locked. |
| GET | `/api/sessions/:id/predictions` | Everyone's predictions for a session — ONLY after lock. Before lock: 403. |

### Leaderboard

| Method | Path | Notes |
|---|---|---|
| GET | `/api/leagues/:id/leaderboard` | League leaderboard. Member-only. `[{ userId, displayName, totalPoints, sessionsScored }, ...]` sorted desc. Optional `?season=YYYY`. |
| GET | `/api/leagues/:id/leaderboard/sessions` | Round-by-round breakdown. Per-session per-member points + breakdown JSONB. |
| GET | `/api/users/me/scores` | Caller's own score history. |

### Admin

| Method | Path | Notes |
|---|---|---|
| POST | `/admin/rescore-session/:id` | Force one session's rescore. Token-gated. |
| POST | `/admin/rescore-season/:year` | Rescore every finished session in a season. Token-gated. |

### Validation

zod schemas per body. For prediction submit:
- `picks` array length must match the session type's required count.
- `position` values must be exactly `[1..N]` (no gaps, no dupes).
- `driverCode` must exist in `driver` and not duplicate within the prediction.
- Drivers must be in the current season — enforced by `EXISTS (SELECT 1 FROM driver_standing WHERE driver_code = X AND season_year = current)`.

### Response shapes

- `prediction` returned to caller: `{ sessionId, picks: [...sorted by position asc...], updatedAt, isLocked }`.
- `score` rows include the full `breakdown` JSONB so the UI can render without recomputation.
- Leaderboard rows include `sessionsScored` so the UI can show "12 / 23 races" alongside the point total.

## Lock enforcement + crawler integration

**Lock helper** (one source of truth):

```ts
async function requireSessionUnlocked(sessionId: number): Promise<Session> {
  const s = await sessionsRepo.findById(sessionId)
  if (!s) throw new ApiError('NOT_FOUND', 'Session not found')
  if (s.scheduledStart.getTime() <= Date.now()) {
    throw new ApiError('CONFLICT', 'Predictions for this session are locked')
  }
  return s
}
```

Called by PUT/DELETE `/api/sessions/:id/my-prediction`. The inverse — `requireSessionLocked` — gates `GET /api/sessions/:id/predictions`. Both compare server `Date.now()` against the same `timestamptz` column.

**Tick integration** (one added block in `src/crawler/tick.ts`):

```ts
// after upsertSessionResults(sessionId, rows) succeeds:
try {
  const summary = await rescoreSession(sessionId)
  log.info({ sessionId, ...summary }, 'rescored session')
} catch (err) {
  log.error({ sessionId, err }, 'rescore failed (results saved)')
}
```

**Properties:**
1. First-time scoring lands the same tick that imports the results.
2. FIA penalty re-fetches that change result rows trigger re-rescore automatically.
3. Rescore failure doesn't fail the tick — results are still saved, next tick can recover.

**Idempotency:** `rescoreSession` upserts on `(user_id, session_id)`. Safe to run N times. Each run blows away the previous breakdown.

**Cancelled / postponed sessions:** No results means `rescoreSession` no-ops. Rescheduled sessions update `scheduled_start`; the lock check then naturally re-opens.

## Errors

No new `ApiErrorCode` variants needed. Existing codes cover all cases:

| Code | Used for |
|---|---|
| `NOT_FOUND` | Session doesn't exist; no prediction for caller on this session |
| `UNAUTHORIZED` | Standard bearer-token failure (from `registerAuthHook`) |
| `FORBIDDEN` | Non-member peeking at a league leaderboard; reading others' predictions before lock |
| `CONFLICT` | Submitting/editing/deleting after `scheduled_start` |
| `VALIDATION` | zod body parse failure; wrong picks count; unknown driver code; driver not in current season; duplicate driver in picks |

**`CONFLICT` vs `VALIDATION` rule** (consistent with sub-project 2): VALIDATION = caller can fix locally; CONFLICT = the request is well-formed but server state won't accept it.

## Code layout

```
backend/src/
  scoring/                NEW
    index.ts              dispatcher
    qualifying.ts         scorer (pure)
    sprintShootout.ts     scorer (pure)
    sprintRace.ts         scorer (pure)
    race.ts               scorer (pure)
    rescorer.ts           DB-aware orchestrator
    types.ts              shared types: Pick, Finisher, ScoreBreakdown
  api/
    routes/
      predictions.ts      NEW — /api/predictions/*, /api/sessions/:id/...
      leaderboard.ts      NEW — /api/leagues/:id/leaderboard*, /api/users/me/scores
  repo/
    predictions.ts        NEW
    predictionPicks.ts    NEW
    scores.ts             NEW
    results.ts            EXTEND — add a "results with constructor join" helper
    sessions.ts           EXTEND — add findById helper if missing
  db/
    schema.ts             EXTEND — add 3 tables
    migrations/
      0003_predictions.sql  NEW
  crawler/
    tick.ts               MODIFY — invoke rescoreSession after upsertSessionResults
```

`src/index.ts` registers `predictions.ts` and `leaderboard.ts` route groups alongside the existing ones.

## Testing

Same vitest single-fork pattern, real Postgres on 5433, `truncateAll` in `beforeEach`. The new tables added to the existing `TABLES` list.

**Unit tests** (`test/unit/scoring/*.test.ts`) — one per scorer. Pure functions, no DB. These are the most important tests:

- `qualifying.test.ts` — all-exact, all-wrong, swapped P1↔P2, team-bonus alone, no picks.
- `sprintShootout.test.ts` — exact, wrong driver, team match alone.
- `sprintRace.test.ts` — all-exact, partial podium, partial team bonus.
- `race.test.ts` — all 5 exact, mixed exact/wrong-pos, no team bonus, team-only bonus, fewer than 5 finishers (DNFs).
- `dispatcher.test.ts` — wrong picks count throws, unknown session type throws.

**Integration tests** (`test/integration/`):

- `repo_predictions.test.ts` — insert/update/get/delete, unique (user, session), cascade from user delete.
- `repo_scores.test.ts` — upsert overwrites, leaderboard SQL aggregates per league correctly.
- `api_predictions.test.ts` — full route flow: signup → submit → edit → 409 after lock → view own → 403 on others before lock → 200 after lock.
- `api_leaderboard.test.ts` — two users, three sessions, computed scores, members-only access, sort, season filter.
- `scoring_rescorer.test.ts` — write predictions, write results, rescore, verify breakdown shape; then update results, rescore again, verify overwrite.
- `crawler_tick_rescore.test.ts` — tick path with a prediction present; verify score appears post-tick.

**Test data builders** (`test/helpers/factories.ts`) gain:

```ts
makeSession(eventId, type, scheduledStart?)
makePrediction(userId, sessionId, picks: [{ position, driverCode }, ...])
```

**Out of scope for tests:** real-time lock behavior using wall-clock timers (tests use past or future `scheduledStart` explicitly); load-testing leaderboard queries.

## What's explicitly NOT in this sub-project

- **Predictions on practice sessions (fp1/fp2/fp3)** — not scorable, not interesting to predict.
- **Notifications / reminders** — no "prediction window closing in 1 hour" emails or push.
- **Cumulative-points snapshots** — leaderboards are computed live.
- **Pre-season questionnaire** — separate sub-project (longer-form season predictions: champion, points scorer count, etc.).
- **Flutter UI changes** — happening in parallel as its own track.
- **Admin override to unlock a session post-start** — could be added later if needed.
