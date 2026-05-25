# Predictions & Scoring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let authenticated users submit per-session F1 predictions, auto-score them when the crawler imports results, and expose per-league leaderboards.

**Architecture:** Slot into the existing `api → repo → db` shape. Three new tables (`prediction`, `prediction_pick`, `score`). One new pure-functional leaf module `src/scoring/` with four scorers + a dispatcher. One DB-aware `rescorer` invoked from the existing `tick` after results are written. Two new route files (`predictions.ts`, `leaderboard.ts`). Two new admin endpoints for manual rescore.

**Tech Stack:** Same as sub-projects 1–2 — Node 22, TypeScript 5.6, Fastify 5, Drizzle ORM, pg, node-cron, zod, vitest. No new deps.

**Spec:** `docs/superpowers/specs/2026-05-25-predictions-design.md`

---

## File map

All paths under `backend/`.

| Path | Status | Responsibility |
|---|---|---|
| `src/db/schema.ts` | Modify | Add `prediction`, `predictionPick`, `score` table defs |
| `src/db/migrations/0003_predictions.sql` | Create | 3 tables + indexes |
| `src/db/migrations/meta/_journal.json` | Modify | Register migration 0003 |
| `src/db/migrations/meta/0003_snapshot.json` | Create | Snapshot for 0003 |
| `src/domain/types.ts` | Modify | Add `Prediction`, `PredictionPick`, `Score`, `ScoreBreakdown` types |
| `src/scoring/types.ts` | Create | `Pick`, `Finisher`, `ScoreBreakdown` shared types |
| `src/scoring/qualifying.ts` | Create | Pure scorer for `qualifying` |
| `src/scoring/sprintShootout.ts` | Create | Pure scorer for `sprint_quali` |
| `src/scoring/sprintRace.ts` | Create | Pure scorer for `sprint` |
| `src/scoring/race.ts` | Create | Pure scorer for `race` |
| `src/scoring/index.ts` | Create | `scoreSession` dispatcher |
| `src/scoring/rescorer.ts` | Create | DB-aware `rescoreSession(sessionId)` |
| `src/repo/predictions.ts` | Create | Prediction CRUD + listForSessionWithPicks |
| `src/repo/predictionPicks.ts` | Create | Pick replace-all + lookup |
| `src/repo/scores.ts` | Create | Upsert + per-league leaderboard + per-user history |
| `src/crawler/tick.ts` | Modify | Call `rescoreSession` after result upsert |
| `src/api/routes/predictions.ts` | Create | `/api/predictions/*` and `/api/sessions/:id/...` routes |
| `src/api/routes/leaderboard.ts` | Create | `/api/leagues/:id/leaderboard*` + `/api/users/me/scores` |
| `src/api/routes/admin.ts` | Modify | Add `/admin/rescore-session/:id` and `/admin/rescore-season/:year` |
| `src/index.ts` | Modify | Register the two new route groups |
| `test/helpers/db.ts` | Modify | Add 3 new tables to TABLES (truncate order) |
| `test/helpers/factories.ts` | Modify | Add `makeSession`, `makePrediction` |
| `test/unit/scoring/qualifying.test.ts` | Create | Pure scorer tests |
| `test/unit/scoring/sprintShootout.test.ts` | Create | Pure scorer tests |
| `test/unit/scoring/sprintRace.test.ts` | Create | Pure scorer tests |
| `test/unit/scoring/race.test.ts` | Create | Pure scorer tests |
| `test/unit/scoring/dispatcher.test.ts` | Create | Dispatcher tests |
| `test/integration/repo_predictions.test.ts` | Create | Predictions + picks repo tests |
| `test/integration/repo_scores.test.ts` | Create | Scores repo + leaderboard SQL |
| `test/integration/scoring_rescorer.test.ts` | Create | Rescorer end-to-end |
| `test/integration/crawler_tick_rescore.test.ts` | Create | Tick→rescore wiring |
| `test/integration/api_predictions.test.ts` | Create | Routes end-to-end |
| `test/integration/api_leaderboard.test.ts` | Create | Leaderboard routes end-to-end |
| `test/integration/api_admin_rescore.test.ts` | Create | Admin rescore endpoints |
| `README.md` | Modify | Document new endpoints + scoring scheme summary |

---

### Task 1: Schema + migration 0003

**Files:**
- Modify: `backend/src/db/schema.ts`
- Modify: `backend/src/domain/types.ts`
- Create: `backend/src/db/migrations/0003_predictions.sql`
- Modify: `backend/src/db/migrations/meta/_journal.json`
- Create: `backend/src/db/migrations/meta/0003_snapshot.json`
- Modify: `backend/test/helpers/db.ts`

- [ ] **Step 1: Extend `src/db/schema.ts`**

Append to `backend/src/db/schema.ts` (keep all existing exports):

```ts
import { jsonb } from 'drizzle-orm/pg-core'  // add to existing imports

// ... existing tables stay as-is

export const prediction = pgTable('prediction', {
  id: uuid('id').primaryKey().defaultRandom(),
  userId: uuid('user_id').notNull().references(() => user.id, { onDelete: 'cascade' }),
  sessionId: integer('session_id').notNull().references(() => session.id, { onDelete: 'cascade' }),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow()
}, (t) => ({
  userSessionUq: uniqueIndex('prediction_user_session_uq').on(t.userId, t.sessionId),
  sessionIdx: index('prediction_session_idx').on(t.sessionId)
}))

export const predictionPick = pgTable('prediction_pick', {
  predictionId: uuid('prediction_id').notNull().references(() => prediction.id, { onDelete: 'cascade' }),
  position: integer('position').notNull(),
  driverCode: text('driver_code').notNull().references(() => driver.code)
}, (t) => ({
  pk: primaryKey({ columns: [t.predictionId, t.position] }),
  driverIdx: index('prediction_pick_driver_idx').on(t.driverCode)
}))

export const score = pgTable('score', {
  userId: uuid('user_id').notNull().references(() => user.id, { onDelete: 'cascade' }),
  sessionId: integer('session_id').notNull().references(() => session.id, { onDelete: 'cascade' }),
  pointsTotal: integer('points_total').notNull(),
  breakdown: jsonb('breakdown').notNull(),
  computedAt: timestamp('computed_at', { withTimezone: true }).notNull().defaultNow()
}, (t) => ({
  pk: primaryKey({ columns: [t.userId, t.sessionId] }),
  sessionIdx: index('score_session_idx').on(t.sessionId),
  userIdx: index('score_user_idx').on(t.userId)
}))
```

- [ ] **Step 2: Extend `src/domain/types.ts`**

Append:

```ts
export type Prediction = {
  id: string
  userId: string
  sessionId: number
  createdAt: Date
  updatedAt: Date
}

export type PredictionPick = {
  predictionId: string
  position: number
  driverCode: string
}

export type ScoreBreakdownPerPosition = {
  position: number
  exact: boolean
  wrongPos: boolean
  points: number
}

export type ScoreBreakdown = {
  perPosition: ScoreBreakdownPerPosition[]
  teamBonus: { applied: boolean; points: number }
  rule: string
}

export type Score = {
  userId: string
  sessionId: number
  pointsTotal: number
  breakdown: ScoreBreakdown
  computedAt: Date
}
```

- [ ] **Step 3: Create migration `0003_predictions.sql`**

Create `backend/src/db/migrations/0003_predictions.sql`:

```sql
CREATE TABLE "prediction" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" uuid NOT NULL,
	"session_id" integer NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "prediction_user_fk" FOREIGN KEY ("user_id") REFERENCES "user"("id") ON DELETE CASCADE,
	CONSTRAINT "prediction_session_fk" FOREIGN KEY ("session_id") REFERENCES "session"("id") ON DELETE CASCADE
);
--> statement-breakpoint
CREATE UNIQUE INDEX "prediction_user_session_uq" ON "prediction" ("user_id", "session_id");--> statement-breakpoint
CREATE INDEX "prediction_session_idx" ON "prediction" ("session_id");--> statement-breakpoint
CREATE TABLE "prediction_pick" (
	"prediction_id" uuid NOT NULL,
	"position" integer NOT NULL,
	"driver_code" text NOT NULL,
	CONSTRAINT "prediction_pick_pk" PRIMARY KEY ("prediction_id", "position"),
	CONSTRAINT "prediction_pick_prediction_fk" FOREIGN KEY ("prediction_id") REFERENCES "prediction"("id") ON DELETE CASCADE,
	CONSTRAINT "prediction_pick_driver_fk" FOREIGN KEY ("driver_code") REFERENCES "driver"("code")
);
--> statement-breakpoint
CREATE INDEX "prediction_pick_driver_idx" ON "prediction_pick" ("driver_code");--> statement-breakpoint
CREATE TABLE "score" (
	"user_id" uuid NOT NULL,
	"session_id" integer NOT NULL,
	"points_total" integer NOT NULL,
	"breakdown" jsonb NOT NULL,
	"computed_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "score_pk" PRIMARY KEY ("user_id", "session_id"),
	CONSTRAINT "score_user_fk" FOREIGN KEY ("user_id") REFERENCES "user"("id") ON DELETE CASCADE,
	CONSTRAINT "score_session_fk" FOREIGN KEY ("session_id") REFERENCES "session"("id") ON DELETE CASCADE
);
--> statement-breakpoint
CREATE INDEX "score_session_idx" ON "score" ("session_id");--> statement-breakpoint
CREATE INDEX "score_user_idx" ON "score" ("user_id");
```

- [ ] **Step 4: Register migration in `_journal.json`**

Read `backend/src/db/migrations/meta/_journal.json` and append a new entry:

```json
{
  "idx": 3,
  "version": "7",
  "when": <CURRENT_UNIX_MS>,
  "tag": "0003_predictions",
  "breakpoints": true
}
```

Use the current millisecond timestamp for `when`. Use the same `version` string as the existing entries.

- [ ] **Step 5: Create `meta/0003_snapshot.json`**

Easiest path (mirrors what worked for sub-project 2): run `npm run db:generate` (after step 6's migration is applied locally) so drizzle-kit produces a correct snapshot, then rename/relabel the generated tag to `0003_predictions` if needed. Drop any SQL drizzle-kit produces — Step 3's hand-written SQL is canonical.

If drizzle-kit puts long FK names in the snapshot, hand-edit them to match the short names from the SQL (per the lesson from sub-project 2's Task 1 fix):
- `prediction_user_id_user_id_fk` → `prediction_user_fk`
- `prediction_session_id_session_id_fk` → `prediction_session_fk`
- `prediction_pick_prediction_id_prediction_id_fk` → `prediction_pick_prediction_fk`
- `prediction_pick_driver_code_driver_code_fk` → `prediction_pick_driver_fk`
- `score_user_id_user_id_fk` → `score_user_fk`
- `score_session_id_session_id_fk` → `score_session_fk`

Verify:
```bash
grep -c '_fk' backend/src/db/migrations/meta/0003_snapshot.json
```
The snapshot's FK names must match the migration SQL exactly.

- [ ] **Step 6: Extend `test/helpers/db.ts`**

Add the 3 new tables to the front of TABLES (child-first):

```ts
const TABLES = [
  'score',
  'prediction_pick',
  'prediction',
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

- [ ] **Step 7: Apply the migration locally and verify**

```bash
cd /Users/anton/Dev/Projects/F1predictiongame/backend
set -a && source .env && set +a
npm run db:migrate
```
Expected: `Migrations complete.`

```bash
docker exec backend-db-1 psql -U f1pg -d f1pg -c "\dt"
```
Expected: lists 15 tables including `prediction`, `prediction_pick`, `score`.

- [ ] **Step 8: Run the full test suite**

```bash
cd /Users/anton/Dev/Projects/F1predictiongame/backend
set -a && source .env && set +a
npm test
npx tsc --noEmit
```
Expected: 133/133 still passing (no regressions); tsc clean.

- [ ] **Step 9: Commit**

```bash
cd /Users/anton/Dev/Projects/F1predictiongame
git add backend/src/db/schema.ts backend/src/db/migrations/0003_predictions.sql backend/src/db/migrations/meta/_journal.json backend/src/db/migrations/meta/0003_snapshot.json backend/src/domain/types.ts backend/test/helpers/db.ts
git commit -m "backend: schema + migration for predictions, picks, scores"
```

---

### Task 2: Scoring engine (4 scorers + dispatcher)

**Files:**
- Create: `backend/src/scoring/types.ts`
- Create: `backend/src/scoring/qualifying.ts`
- Create: `backend/src/scoring/sprintShootout.ts`
- Create: `backend/src/scoring/sprintRace.ts`
- Create: `backend/src/scoring/race.ts`
- Create: `backend/src/scoring/index.ts`
- Create: `backend/test/unit/scoring/qualifying.test.ts`
- Create: `backend/test/unit/scoring/sprintShootout.test.ts`
- Create: `backend/test/unit/scoring/sprintRace.test.ts`
- Create: `backend/test/unit/scoring/race.test.ts`
- Create: `backend/test/unit/scoring/dispatcher.test.ts`

Pure functions, no DB. Strict TDD per scorer.

- [ ] **Step 1: Create `src/scoring/types.ts`**

```ts
export type Pick = { position: number; driverCode: string }
export type Finisher = { position: number; driverCode: string; constructorId: string }

export type ScoreBreakdownPerPosition = {
  position: number
  exact: boolean
  wrongPos: boolean
  points: number
}

export type ScoreBreakdown = {
  perPosition: ScoreBreakdownPerPosition[]
  teamBonus: { applied: boolean; points: number }
  rule: string
}
```

- [ ] **Step 2: Write `qualifying.test.ts`**

Create `backend/test/unit/scoring/qualifying.test.ts`:

```ts
import { describe, it, expect } from 'vitest'
import { scoreQualifying } from '../../../src/scoring/qualifying.js'

const VER = { code: 'VER', team: 'red_bull' }
const HAM = { code: 'HAM', team: 'mercedes' }
const NOR = { code: 'NOR', team: 'mclaren' }

function f(position: number, d: { code: string; team: string }) {
  return { position, driverCode: d.code, constructorId: d.team }
}

describe('scoreQualifying', () => {
  it('all exact (3 + 3 + team bonus 1) = 7', () => {
    const picks = [{ position: 1, driverCode: VER.code }, { position: 2, driverCode: HAM.code }]
    const finishers = [f(1, VER), f(2, HAM)]
    const b = scoreQualifying(picks, finishers)
    expect(b.perPosition).toEqual([
      { position: 1, exact: true, wrongPos: false, points: 3 },
      { position: 2, exact: true, wrongPos: false, points: 3 }
    ])
    expect(b.teamBonus).toEqual({ applied: true, points: 1 })
    expect(b.rule).toBe('qualifying-v1')
  })

  it('swapped P1/P2: both wrongPos (1 + 1), team bonus depends on P1', () => {
    const picks = [{ position: 1, driverCode: HAM.code }, { position: 2, driverCode: VER.code }]
    const finishers = [f(1, VER), f(2, HAM)]
    const b = scoreQualifying(picks, finishers)
    expect(b.perPosition[0]).toEqual({ position: 1, exact: false, wrongPos: true, points: 1 })
    expect(b.perPosition[1]).toEqual({ position: 2, exact: false, wrongPos: true, points: 1 })
    // P1-pick HAM is mercedes; pole-actual VER is red_bull → no team bonus
    expect(b.teamBonus).toEqual({ applied: false, points: 0 })
  })

  it('team bonus only: wrong driver, same team', () => {
    const RUS = { code: 'RUS', team: 'mercedes' }
    const picks = [{ position: 1, driverCode: RUS.code }, { position: 2, driverCode: HAM.code }]
    const finishers = [f(1, HAM), f(2, RUS)]
    const b = scoreQualifying(picks, finishers)
    // P1-pick RUS is mercedes; pole-actual HAM is mercedes → team bonus applies
    expect(b.teamBonus).toEqual({ applied: true, points: 1 })
    // Driver scoring: P1 RUS picked, RUS actually finished P2 → wrongPos at P1; P2 HAM picked, HAM finished P1 → wrongPos
    expect(b.perPosition[0]).toEqual({ position: 1, exact: false, wrongPos: true, points: 1 })
    expect(b.perPosition[1]).toEqual({ position: 2, exact: false, wrongPos: true, points: 1 })
  })

  it('no matches at all: 0 points', () => {
    const picks = [{ position: 1, driverCode: NOR.code }, { position: 2, driverCode: NOR.code }]
    const finishers = [f(1, VER), f(2, HAM)]
    const b = scoreQualifying(picks, finishers)
    expect(b.perPosition.every((p) => p.points === 0)).toBe(true)
    expect(b.teamBonus.applied).toBe(false)
  })
})
```

- [ ] **Step 3: Verify failing**

```bash
cd /Users/anton/Dev/Projects/F1predictiongame/backend
set -a && source .env && set +a
npx vitest run test/unit/scoring/qualifying.test.ts
```
Expected: FAIL — module not found.

- [ ] **Step 4: Implement `src/scoring/qualifying.ts`**

```ts
import type { Pick, Finisher, ScoreBreakdown, ScoreBreakdownPerPosition } from './types.js'

const EXACT = 3
const WRONG_POS = 1
const TEAM_BONUS = 1
const RULE = 'qualifying-v1'

export function scoreQualifying(picks: Pick[], finishers: Finisher[]): ScoreBreakdown {
  const perPosition: ScoreBreakdownPerPosition[] = picks.map((p) => {
    const exactFinisher = finishers.find((f) => f.position === p.position)
    if (exactFinisher && exactFinisher.driverCode === p.driverCode) {
      return { position: p.position, exact: true, wrongPos: false, points: EXACT }
    }
    const driverFinishedSomewhere = finishers.some((f) => f.driverCode === p.driverCode)
    if (driverFinishedSomewhere) {
      return { position: p.position, exact: false, wrongPos: true, points: WRONG_POS }
    }
    return { position: p.position, exact: false, wrongPos: false, points: 0 }
  })

  // Team bonus: P1-pick's team == pole-actual's team
  const p1Pick = picks.find((p) => p.position === 1)
  const poleActual = finishers.find((f) => f.position === 1)
  let teamBonus: ScoreBreakdown['teamBonus'] = { applied: false, points: 0 }
  if (p1Pick && poleActual) {
    const pickedDriverActualResult = finishers.find((f) => f.driverCode === p1Pick.driverCode)
    if (pickedDriverActualResult && pickedDriverActualResult.constructorId === poleActual.constructorId) {
      teamBonus = { applied: true, points: TEAM_BONUS }
    }
  }

  return { perPosition, teamBonus, rule: RULE }
}
```

- [ ] **Step 5: Verify passing**

```bash
npx vitest run test/unit/scoring/qualifying.test.ts
```
Expected: PASS (4 tests).

- [ ] **Step 6: Write `sprintShootout.test.ts`**

```ts
import { describe, it, expect } from 'vitest'
import { scoreSprintShootout } from '../../../src/scoring/sprintShootout.js'

const VER = { code: 'VER', team: 'red_bull' }
const HAM = { code: 'HAM', team: 'mercedes' }

function f(position: number, d: { code: string; team: string }) {
  return { position, driverCode: d.code, constructorId: d.team }
}

describe('scoreSprintShootout', () => {
  it('exact P1: 1 + team bonus 1 = 2', () => {
    const picks = [{ position: 1, driverCode: VER.code }]
    const finishers = [f(1, VER), f(2, HAM)]
    const b = scoreSprintShootout(picks, finishers)
    expect(b.perPosition[0]).toEqual({ position: 1, exact: true, wrongPos: false, points: 1 })
    expect(b.teamBonus).toEqual({ applied: true, points: 1 })
  })

  it('wrong driver, no team match: 0', () => {
    const picks = [{ position: 1, driverCode: VER.code }]
    const finishers = [f(1, HAM)]
    const b = scoreSprintShootout(picks, finishers)
    expect(b.perPosition[0].points).toBe(0)
    expect(b.teamBonus.applied).toBe(false)
  })

  it('team match only (right team, wrong driver in P1)', () => {
    const RUS = { code: 'RUS', team: 'mercedes' }
    const picks = [{ position: 1, driverCode: HAM.code }]
    const finishers = [f(1, RUS)]
    const b = scoreSprintShootout(picks, finishers)
    expect(b.perPosition[0].points).toBe(0)  // HAM didn't finish anywhere
    expect(b.teamBonus).toEqual({ applied: true, points: 1 })
  })
})
```

- [ ] **Step 7: Verify failing**

```bash
npx vitest run test/unit/scoring/sprintShootout.test.ts
```
Expected: FAIL.

- [ ] **Step 8: Implement `src/scoring/sprintShootout.ts`**

```ts
import type { Pick, Finisher, ScoreBreakdown, ScoreBreakdownPerPosition } from './types.js'

const EXACT = 1
const TEAM_BONUS = 1
const RULE = 'sprint-shootout-v1'

export function scoreSprintShootout(picks: Pick[], finishers: Finisher[]): ScoreBreakdown {
  const perPosition: ScoreBreakdownPerPosition[] = picks.map((p) => {
    const exactFinisher = finishers.find((f) => f.position === p.position)
    if (exactFinisher && exactFinisher.driverCode === p.driverCode) {
      return { position: p.position, exact: true, wrongPos: false, points: EXACT }
    }
    return { position: p.position, exact: false, wrongPos: false, points: 0 }
  })

  const p1Pick = picks.find((p) => p.position === 1)
  const p1Actual = finishers.find((f) => f.position === 1)
  let teamBonus: ScoreBreakdown['teamBonus'] = { applied: false, points: 0 }
  if (p1Pick && p1Actual) {
    const pickedDriverActualResult = finishers.find((f) => f.driverCode === p1Pick.driverCode)
    if (pickedDriverActualResult && pickedDriverActualResult.constructorId === p1Actual.constructorId) {
      teamBonus = { applied: true, points: TEAM_BONUS }
    }
  }

  return { perPosition, teamBonus, rule: RULE }
}
```

- [ ] **Step 9: Verify passing**

```bash
npx vitest run test/unit/scoring/sprintShootout.test.ts
```
Expected: PASS (3 tests).

- [ ] **Step 10: Write `sprintRace.test.ts`**

```ts
import { describe, it, expect } from 'vitest'
import { scoreSprintRace } from '../../../src/scoring/sprintRace.js'

const VER = { code: 'VER', team: 'red_bull' }
const HAM = { code: 'HAM', team: 'mercedes' }
const NOR = { code: 'NOR', team: 'mclaren' }
const PIA = { code: 'PIA', team: 'mclaren' }

function f(position: number, d: { code: string; team: string }) {
  return { position, driverCode: d.code, constructorId: d.team }
}

describe('scoreSprintRace', () => {
  it('all exact (2 + 2 + 2 + team 1) = 7', () => {
    const picks = [
      { position: 1, driverCode: VER.code },
      { position: 2, driverCode: HAM.code },
      { position: 3, driverCode: NOR.code }
    ]
    const finishers = [f(1, VER), f(2, HAM), f(3, NOR)]
    const b = scoreSprintRace(picks, finishers)
    expect(b.perPosition.every((p) => p.exact)).toBe(true)
    expect(b.perPosition.reduce((s, p) => s + p.points, 0)).toBe(6)
    expect(b.teamBonus).toEqual({ applied: true, points: 1 })
  })

  it('partial podium and team bonus from teammate', () => {
    const picks = [
      { position: 1, driverCode: PIA.code },  // PIA picked for P1
      { position: 2, driverCode: HAM.code },
      { position: 3, driverCode: VER.code }
    ]
    const finishers = [f(1, NOR), f(2, HAM), f(3, VER)]  // NOR actually won
    const b = scoreSprintRace(picks, finishers)
    expect(b.perPosition[0]).toEqual({ position: 1, exact: false, wrongPos: false, points: 0 })  // PIA didn't finish
    expect(b.perPosition[1]).toEqual({ position: 2, exact: true, wrongPos: false, points: 2 })
    expect(b.perPosition[2]).toEqual({ position: 3, exact: true, wrongPos: false, points: 2 })
    // P1-pick PIA is mclaren; winner NOR is mclaren → team bonus applies
    expect(b.teamBonus).toEqual({ applied: true, points: 1 })
  })

  it('no points at all', () => {
    const picks = [
      { position: 1, driverCode: NOR.code },
      { position: 2, driverCode: NOR.code },
      { position: 3, driverCode: NOR.code }
    ]
    const finishers = [f(1, VER), f(2, HAM), f(3, PIA)]
    const b = scoreSprintRace(picks, finishers)
    // NOR didn't finish at all
    expect(b.perPosition.every((p) => p.points === 0)).toBe(true)
    expect(b.teamBonus.applied).toBe(false)
  })
})
```

Note: the second test relies on `finishers.find((f) => f.driverCode === picks[0].driverCode)` returning the team of the PICKED driver — but PIA isn't in finishers here. So `pickedDriverActualResult` is undefined and team bonus would NOT apply. Re-read the spec: "team bonus = +1 if P1-pick's team == winner team". The team of the P1-pick comes from looking up the driver's team. But finishers may not include them (they didn't finish). So we need a way to know PIA's team independently of the finishers — but the scorer only has `finishers` as input.

**Resolution:** The scorer infers team from finishers. If the picked driver isn't a finisher, we can't infer their team from this input, and the bonus doesn't apply. Update the test's expectation accordingly:

```ts
  it('partial podium and team bonus from teammate (only when teammate appears in finishers list)', () => {
    const picks = [
      { position: 1, driverCode: PIA.code },
      { position: 2, driverCode: HAM.code },
      { position: 3, driverCode: VER.code }
    ]
    // PIA didn't finish; scorer can't infer his team from finishers — no team bonus.
    const finishers = [f(1, NOR), f(2, HAM), f(3, VER)]
    const b = scoreSprintRace(picks, finishers)
    expect(b.perPosition[0].points).toBe(0)
    expect(b.perPosition[1]).toEqual({ position: 2, exact: true, wrongPos: false, points: 2 })
    expect(b.perPosition[2]).toEqual({ position: 3, exact: true, wrongPos: false, points: 2 })
    expect(b.teamBonus).toEqual({ applied: false, points: 0 })
  })
```

Use the revised test. This is also a design decision worth carrying forward to the rescorer: if it wants to support "team bonus when picked driver DNF'd but their teammate won," it would need to look up the driver's team from `driver_standing` or another source. **The rescorer in Task 5 should pass a full `finishers` list that includes teams for non-finishers as well.** That means querying `driver_standing` (which has `constructor_id` for each driver in the season) and synthesizing fake `position: 999` entries for non-finishers. We'll do that in Task 5.

For the scorer tests in this task, the inputs are explicit — finishers only include drivers actually present in the result.

- [ ] **Step 11: Verify failing**

```bash
npx vitest run test/unit/scoring/sprintRace.test.ts
```
Expected: FAIL.

- [ ] **Step 12: Implement `src/scoring/sprintRace.ts`**

```ts
import type { Pick, Finisher, ScoreBreakdown, ScoreBreakdownPerPosition } from './types.js'

const EXACT = 2
const WRONG_POS = 1
const TEAM_BONUS = 1
const RULE = 'sprint-race-v1'

export function scoreSprintRace(picks: Pick[], finishers: Finisher[]): ScoreBreakdown {
  const perPosition: ScoreBreakdownPerPosition[] = picks.map((p) => {
    const exactFinisher = finishers.find((f) => f.position === p.position)
    if (exactFinisher && exactFinisher.driverCode === p.driverCode) {
      return { position: p.position, exact: true, wrongPos: false, points: EXACT }
    }
    const driverFinishedSomewhere = finishers.some((f) => f.driverCode === p.driverCode)
    if (driverFinishedSomewhere) {
      return { position: p.position, exact: false, wrongPos: true, points: WRONG_POS }
    }
    return { position: p.position, exact: false, wrongPos: false, points: 0 }
  })

  const p1Pick = picks.find((p) => p.position === 1)
  const winner = finishers.find((f) => f.position === 1)
  let teamBonus: ScoreBreakdown['teamBonus'] = { applied: false, points: 0 }
  if (p1Pick && winner) {
    const pickedDriverActualResult = finishers.find((f) => f.driverCode === p1Pick.driverCode)
    if (pickedDriverActualResult && pickedDriverActualResult.constructorId === winner.constructorId) {
      teamBonus = { applied: true, points: TEAM_BONUS }
    }
  }

  return { perPosition, teamBonus, rule: RULE }
}
```

- [ ] **Step 13: Verify passing**

```bash
npx vitest run test/unit/scoring/sprintRace.test.ts
```
Expected: PASS (3 tests).

- [ ] **Step 14: Write `race.test.ts`**

```ts
import { describe, it, expect } from 'vitest'
import { scoreRace } from '../../../src/scoring/race.js'

const VER = { code: 'VER', team: 'red_bull' }
const HAM = { code: 'HAM', team: 'mercedes' }
const NOR = { code: 'NOR', team: 'mclaren' }
const PIA = { code: 'PIA', team: 'mclaren' }
const RUS = { code: 'RUS', team: 'mercedes' }
const PER = { code: 'PER', team: 'red_bull' }

function f(position: number, d: { code: string; team: string }) {
  return { position, driverCode: d.code, constructorId: d.team }
}

describe('scoreRace', () => {
  it('all 5 exact + team bonus (3*5 + 2) = 17', () => {
    const picks = [
      { position: 1, driverCode: VER.code },
      { position: 2, driverCode: HAM.code },
      { position: 3, driverCode: NOR.code },
      { position: 4, driverCode: PIA.code },
      { position: 5, driverCode: RUS.code }
    ]
    const finishers = [f(1, VER), f(2, HAM), f(3, NOR), f(4, PIA), f(5, RUS)]
    const b = scoreRace(picks, finishers)
    expect(b.perPosition.reduce((s, p) => s + p.points, 0)).toBe(15)
    expect(b.teamBonus).toEqual({ applied: true, points: 2 })
  })

  it('mixed exact + wrong-pos, no team bonus', () => {
    // VER picked for P1, actually finished P2 → wrongPos at P1
    // HAM picked for P2, actually finished P1 → wrongPos at P2
    const picks = [
      { position: 1, driverCode: VER.code },
      { position: 2, driverCode: HAM.code },
      { position: 3, driverCode: NOR.code },
      { position: 4, driverCode: PIA.code },
      { position: 5, driverCode: RUS.code }
    ]
    const finishers = [f(1, HAM), f(2, VER), f(3, NOR), f(4, PIA), f(5, RUS)]
    const b = scoreRace(picks, finishers)
    expect(b.perPosition[0]).toEqual({ position: 1, exact: false, wrongPos: true, points: 1 })
    expect(b.perPosition[1]).toEqual({ position: 2, exact: false, wrongPos: true, points: 1 })
    expect(b.perPosition[2]).toEqual({ position: 3, exact: true, wrongPos: false, points: 3 })
    // VER picked for P1, HAM (mercedes) won. VER is red_bull → no team bonus
    expect(b.teamBonus).toEqual({ applied: false, points: 0 })
  })

  it('team-only bonus (right team, wrong driver in P1)', () => {
    // PER picked for P1, VER (same team red_bull) actually won. PER didn't finish at all.
    const picks = [
      { position: 1, driverCode: PER.code },
      { position: 2, driverCode: HAM.code },
      { position: 3, driverCode: NOR.code },
      { position: 4, driverCode: PIA.code },
      { position: 5, driverCode: RUS.code }
    ]
    const finishers = [f(1, VER), f(2, HAM), f(3, NOR), f(4, PIA), f(5, RUS)]
    const b = scoreRace(picks, finishers)
    expect(b.perPosition[0].points).toBe(0)  // PER not in finishers, no inferrable team → no team bonus
    expect(b.teamBonus).toEqual({ applied: false, points: 0 })
  })

  it('fewer than 5 finishers (DNFs): missing positions score 0', () => {
    const picks = [
      { position: 1, driverCode: VER.code },
      { position: 2, driverCode: HAM.code },
      { position: 3, driverCode: NOR.code },
      { position: 4, driverCode: PIA.code },
      { position: 5, driverCode: RUS.code }
    ]
    // Only 3 finishers
    const finishers = [f(1, VER), f(2, HAM), f(3, NOR)]
    const b = scoreRace(picks, finishers)
    expect(b.perPosition[0].points).toBe(3)
    expect(b.perPosition[1].points).toBe(3)
    expect(b.perPosition[2].points).toBe(3)
    expect(b.perPosition[3].points).toBe(0)
    expect(b.perPosition[4].points).toBe(0)
    expect(b.teamBonus).toEqual({ applied: true, points: 2 })
  })
})
```

- [ ] **Step 15: Verify failing**

```bash
npx vitest run test/unit/scoring/race.test.ts
```
Expected: FAIL.

- [ ] **Step 16: Implement `src/scoring/race.ts`**

```ts
import type { Pick, Finisher, ScoreBreakdown, ScoreBreakdownPerPosition } from './types.js'

const EXACT = 3
const WRONG_POS = 1
const TEAM_BONUS = 2
const RULE = 'race-v1'

export function scoreRace(picks: Pick[], finishers: Finisher[]): ScoreBreakdown {
  const perPosition: ScoreBreakdownPerPosition[] = picks.map((p) => {
    const exactFinisher = finishers.find((f) => f.position === p.position)
    if (exactFinisher && exactFinisher.driverCode === p.driverCode) {
      return { position: p.position, exact: true, wrongPos: false, points: EXACT }
    }
    const driverFinishedSomewhere = finishers.some((f) => f.driverCode === p.driverCode)
    if (driverFinishedSomewhere) {
      return { position: p.position, exact: false, wrongPos: true, points: WRONG_POS }
    }
    return { position: p.position, exact: false, wrongPos: false, points: 0 }
  })

  const p1Pick = picks.find((p) => p.position === 1)
  const winner = finishers.find((f) => f.position === 1)
  let teamBonus: ScoreBreakdown['teamBonus'] = { applied: false, points: 0 }
  if (p1Pick && winner) {
    const pickedDriverActualResult = finishers.find((f) => f.driverCode === p1Pick.driverCode)
    if (pickedDriverActualResult && pickedDriverActualResult.constructorId === winner.constructorId) {
      teamBonus = { applied: true, points: TEAM_BONUS }
    }
  }

  return { perPosition, teamBonus, rule: RULE }
}
```

- [ ] **Step 17: Verify passing**

```bash
npx vitest run test/unit/scoring/race.test.ts
```
Expected: PASS (4 tests).

- [ ] **Step 18: Write `dispatcher.test.ts`**

```ts
import { describe, it, expect } from 'vitest'
import { scoreSession } from '../../../src/scoring/index.js'
import type { SessionType } from '../../../src/domain/types.js'

const VER = { code: 'VER', team: 'red_bull' }
const HAM = { code: 'HAM', team: 'mercedes' }

function f(position: number, d: { code: string; team: string }) {
  return { position, driverCode: d.code, constructorId: d.team }
}

describe('scoreSession dispatcher', () => {
  it('dispatches to scoreRace', () => {
    const picks = Array.from({ length: 5 }, (_, i) => ({ position: i + 1, driverCode: VER.code }))
    const finishers = [f(1, VER)]
    const b = scoreSession('race', picks, finishers)
    expect(b.rule).toBe('race-v1')
  })

  it('dispatches to scoreQualifying', () => {
    const picks = [{ position: 1, driverCode: VER.code }, { position: 2, driverCode: HAM.code }]
    const finishers = [f(1, VER), f(2, HAM)]
    const b = scoreSession('qualifying', picks, finishers)
    expect(b.rule).toBe('qualifying-v1')
  })

  it('throws on unknown session type', () => {
    expect(() => scoreSession('fp1' as SessionType, [], [])).toThrow(/not scorable/i)
  })

  it('throws on wrong pick count for type', () => {
    const tooFew = [{ position: 1, driverCode: VER.code }]  // race needs 5
    expect(() => scoreSession('race', tooFew, [])).toThrow(/expected 5 picks/i)
  })
})
```

- [ ] **Step 19: Verify failing**

```bash
npx vitest run test/unit/scoring/dispatcher.test.ts
```
Expected: FAIL.

- [ ] **Step 20: Implement `src/scoring/index.ts`**

```ts
import type { SessionType } from '../domain/types.js'
import { scoreQualifying } from './qualifying.js'
import { scoreSprintShootout } from './sprintShootout.js'
import { scoreSprintRace } from './sprintRace.js'
import { scoreRace } from './race.js'
import type { Pick, Finisher, ScoreBreakdown } from './types.js'

export type { Pick, Finisher, ScoreBreakdown } from './types.js'

const EXPECTED_PICKS: Partial<Record<SessionType, number>> = {
  qualifying: 2,
  sprint_quali: 1,
  sprint: 3,
  race: 5
}

export function scoreSession(
  type: SessionType,
  picks: Pick[],
  finishers: Finisher[]
): ScoreBreakdown {
  const expected = EXPECTED_PICKS[type]
  if (expected === undefined) {
    throw new Error(`Session type ${type} is not scorable`)
  }
  if (picks.length !== expected) {
    throw new Error(`Session type ${type} expected ${expected} picks, got ${picks.length}`)
  }
  switch (type) {
    case 'qualifying':    return scoreQualifying(picks, finishers)
    case 'sprint_quali':  return scoreSprintShootout(picks, finishers)
    case 'sprint':        return scoreSprintRace(picks, finishers)
    case 'race':          return scoreRace(picks, finishers)
    default:              throw new Error(`Session type ${type} is not scorable`)
  }
}

export function isScorableSessionType(type: SessionType): boolean {
  return EXPECTED_PICKS[type] !== undefined
}

export function picksRequiredFor(type: SessionType): number | null {
  return EXPECTED_PICKS[type] ?? null
}
```

- [ ] **Step 21: Verify passing**

```bash
npx vitest run test/unit/scoring/dispatcher.test.ts
```
Expected: PASS (4 tests).

- [ ] **Step 22: Run all scoring tests + full suite**

```bash
npx vitest run test/unit/scoring/
npm test
npx tsc --noEmit
```
Expected: 18 new tests pass; full suite 151/151 (133 + 18); tsc clean.

- [ ] **Step 23: Commit**

```bash
cd /Users/anton/Dev/Projects/F1predictiongame
git add backend/src/scoring/ backend/test/unit/scoring/
git commit -m "backend: scoring engine (4 scorers + dispatcher)"
```

---

### Task 3: Predictions + picks repos

**Files:**
- Create: `backend/src/repo/predictions.ts`
- Create: `backend/src/repo/predictionPicks.ts`
- Create: `backend/test/integration/repo_predictions.test.ts`

TDD.

- [ ] **Step 1: Write tests**

Create `backend/test/integration/repo_predictions.test.ts`:

```ts
import { describe, it, expect } from 'vitest'
import * as users from '../../src/repo/users.js'
import * as seasons from '../../src/repo/seasons.js'
import * as events from '../../src/repo/events.js'
import * as sessions from '../../src/repo/sessions.js'
import * as drivers from '../../src/repo/drivers.js'
import * as predictions from '../../src/repo/predictions.js'
import * as picks from '../../src/repo/predictionPicks.js'

async function seed() {
  await seasons.upsertSeason({ year: 2026, isCurrent: true })
  const ev = await events.upsertEvent({
    seasonYear: 2026, round: 1, name: 'Bahrain', circuitName: 'BIC', country: 'Bahrain', hasSprint: false
  })
  const ses = await sessions.upsertSession({
    eventId: ev.id, type: 'race',
    scheduledStart: new Date(Date.now() + 60_000),
    scheduledEnd: new Date(Date.now() + 60_000 + 2 * 60 * 60 * 1000),
    status: 'scheduled'
  })
  await drivers.upsertDriver({ code: 'VER', givenName: 'Max', familyName: 'Verstappen', nationality: 'NL', permanentNumber: 33, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null })
  await drivers.upsertDriver({ code: 'HAM', givenName: 'Lewis', familyName: 'Hamilton', nationality: 'GB', permanentNumber: 44, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null })
  const user = await users.insertUser({ email: 't@x.com', passwordHash: 'h', displayName: 'T' })
  return { user, ses }
}

describe('predictions repo', () => {
  it('inserts a prediction with picks and reads them back', async () => {
    const { user, ses } = await seed()
    const p = await predictions.insertPrediction(user.id, ses.id)
    await picks.replaceForPrediction(p.id, [
      { position: 1, driverCode: 'VER' },
      { position: 2, driverCode: 'HAM' }
    ])
    const got = await predictions.getByUserAndSession(user.id, ses.id)
    expect(got?.id).toBe(p.id)
    const list = await picks.listForPrediction(p.id)
    expect(list).toEqual([
      { position: 1, driverCode: 'VER' },
      { position: 2, driverCode: 'HAM' }
    ])
  })

  it('replaces picks atomically', async () => {
    const { user, ses } = await seed()
    const p = await predictions.insertPrediction(user.id, ses.id)
    await picks.replaceForPrediction(p.id, [{ position: 1, driverCode: 'VER' }])
    await picks.replaceForPrediction(p.id, [
      { position: 1, driverCode: 'HAM' },
      { position: 2, driverCode: 'VER' }
    ])
    const list = await picks.listForPrediction(p.id)
    expect(list).toEqual([
      { position: 1, driverCode: 'HAM' },
      { position: 2, driverCode: 'VER' }
    ])
  })

  it('rejects duplicate (user, session)', async () => {
    const { user, ses } = await seed()
    await predictions.insertPrediction(user.id, ses.id)
    await expect(predictions.insertPrediction(user.id, ses.id)).rejects.toThrow(/duplicate|unique/i)
  })

  it('upserts via upsertPredictionWithPicks (idempotent submit)', async () => {
    const { user, ses } = await seed()
    const id1 = await predictions.upsertPredictionWithPicks(user.id, ses.id, [
      { position: 1, driverCode: 'VER' }
    ])
    const id2 = await predictions.upsertPredictionWithPicks(user.id, ses.id, [
      { position: 1, driverCode: 'HAM' }
    ])
    expect(id1).toBe(id2)
    const list = await picks.listForPrediction(id2)
    expect(list).toEqual([{ position: 1, driverCode: 'HAM' }])
  })

  it('deletes a prediction (cascades picks)', async () => {
    const { user, ses } = await seed()
    const p = await predictions.insertPrediction(user.id, ses.id)
    await picks.replaceForPrediction(p.id, [{ position: 1, driverCode: 'VER' }])
    await predictions.deleteByUserAndSession(user.id, ses.id)
    expect(await predictions.getByUserAndSession(user.id, ses.id)).toBeNull()
    expect(await picks.listForPrediction(p.id)).toEqual([])
  })

  it('lists all predictions+picks for a session', async () => {
    const { user, ses } = await seed()
    const u2 = await users.insertUser({ email: 't2@x.com', passwordHash: 'h', displayName: 'T2' })
    const p1 = await predictions.insertPrediction(user.id, ses.id)
    await picks.replaceForPrediction(p1.id, [{ position: 1, driverCode: 'VER' }])
    const p2 = await predictions.insertPrediction(u2.id, ses.id)
    await picks.replaceForPrediction(p2.id, [{ position: 1, driverCode: 'HAM' }])

    const all = await predictions.listForSessionWithPicks(ses.id)
    const byUser = new Map(all.map((x) => [x.userId, x.picks]))
    expect(byUser.get(user.id)).toEqual([{ position: 1, driverCode: 'VER' }])
    expect(byUser.get(u2.id)).toEqual([{ position: 1, driverCode: 'HAM' }])
  })

  it('cascades from user delete', async () => {
    const { user, ses } = await seed()
    const p = await predictions.insertPrediction(user.id, ses.id)
    await picks.replaceForPrediction(p.id, [{ position: 1, driverCode: 'VER' }])
    await users.deleteById(user.id)
    expect(await predictions.getByUserAndSession(user.id, ses.id)).toBeNull()
  })
})
```

- [ ] **Step 2: Verify failing**

```bash
cd /Users/anton/Dev/Projects/F1predictiongame/backend
set -a && source .env && set +a
npx vitest run test/integration/repo_predictions.test.ts
```
Expected: FAIL — modules not found.

- [ ] **Step 3: Implement `src/repo/predictionPicks.ts`**

```ts
import { eq, asc } from 'drizzle-orm'
import { getDb } from '../db/client.js'
import { predictionPick } from '../db/schema.js'
import type { PredictionPick } from '../domain/types.js'

export type PickInput = { position: number; driverCode: string }

export async function replaceForPrediction(predictionId: string, items: PickInput[]): Promise<void> {
  const db = getDb()
  await db.transaction(async (tx) => {
    await tx.delete(predictionPick).where(eq(predictionPick.predictionId, predictionId))
    if (items.length === 0) return
    await tx.insert(predictionPick).values(items.map((i) => ({
      predictionId,
      position: i.position,
      driverCode: i.driverCode
    })))
  })
}

export async function listForPrediction(predictionId: string): Promise<PickInput[]> {
  const db = getDb()
  const rows = await db.select({
    position: predictionPick.position,
    driverCode: predictionPick.driverCode
  }).from(predictionPick).where(eq(predictionPick.predictionId, predictionId)).orderBy(asc(predictionPick.position))
  return rows
}
```

- [ ] **Step 4: Implement `src/repo/predictions.ts`**

```ts
import { and, eq, sql } from 'drizzle-orm'
import { getDb } from '../db/client.js'
import { prediction, predictionPick } from '../db/schema.js'
import type { Prediction } from '../domain/types.js'
import { replaceForPrediction, type PickInput } from './predictionPicks.js'

function toPrediction(row: typeof prediction.$inferSelect): Prediction {
  return {
    id: row.id,
    userId: row.userId,
    sessionId: row.sessionId,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt
  }
}

export async function insertPrediction(userId: string, sessionId: number): Promise<Prediction> {
  const db = getDb()
  const [row] = await db.insert(prediction).values({ userId, sessionId }).returning()
  return toPrediction(row!)
}

export async function getByUserAndSession(userId: string, sessionId: number): Promise<Prediction | null> {
  const db = getDb()
  const rows = await db.select().from(prediction)
    .where(and(eq(prediction.userId, userId), eq(prediction.sessionId, sessionId)))
    .limit(1)
  return rows[0] ? toPrediction(rows[0]) : null
}

export async function deleteByUserAndSession(userId: string, sessionId: number): Promise<void> {
  const db = getDb()
  await db.delete(prediction).where(and(eq(prediction.userId, userId), eq(prediction.sessionId, sessionId)))
}

/**
 * Atomically insert-or-update a prediction and its picks. Returns the prediction id.
 */
export async function upsertPredictionWithPicks(
  userId: string,
  sessionId: number,
  items: PickInput[]
): Promise<string> {
  const db = getDb()
  return db.transaction(async (tx) => {
    const [row] = await tx.insert(prediction)
      .values({ userId, sessionId })
      .onConflictDoUpdate({
        target: [prediction.userId, prediction.sessionId],
        set: { updatedAt: sql`now()` }
      })
      .returning()
    const id = row!.id

    await tx.delete(predictionPick).where(eq(predictionPick.predictionId, id))
    if (items.length > 0) {
      await tx.insert(predictionPick).values(items.map((i) => ({
        predictionId: id,
        position: i.position,
        driverCode: i.driverCode
      })))
    }
    return id
  })
}

export type PredictionWithPicks = {
  userId: string
  predictionId: string
  picks: PickInput[]
}

export async function listForSessionWithPicks(sessionId: number): Promise<PredictionWithPicks[]> {
  const db = getDb()
  const rows = await db
    .select({
      userId: prediction.userId,
      predictionId: prediction.id,
      position: predictionPick.position,
      driverCode: predictionPick.driverCode
    })
    .from(prediction)
    .leftJoin(predictionPick, eq(predictionPick.predictionId, prediction.id))
    .where(eq(prediction.sessionId, sessionId))

  const byPrediction = new Map<string, PredictionWithPicks>()
  for (const r of rows) {
    let p = byPrediction.get(r.predictionId)
    if (!p) {
      p = { userId: r.userId, predictionId: r.predictionId, picks: [] }
      byPrediction.set(r.predictionId, p)
    }
    if (r.position !== null && r.driverCode !== null) {
      p.picks.push({ position: r.position, driverCode: r.driverCode })
    }
  }
  for (const p of byPrediction.values()) {
    p.picks.sort((a, b) => a.position - b.position)
  }
  return Array.from(byPrediction.values())
}
```

`replaceForPrediction` is re-exported from `predictionPicks.ts` and imported above for type/parity only — `upsertPredictionWithPicks` does its own picks replacement inside the same transaction. Don't call the helper from inside the upsert (would nest transactions).

- [ ] **Step 5: Verify tests pass**

```bash
npx vitest run test/integration/repo_predictions.test.ts
```
Expected: PASS (7 tests).

- [ ] **Step 6: Commit**

```bash
cd /Users/anton/Dev/Projects/F1predictiongame
git add backend/src/repo/predictions.ts backend/src/repo/predictionPicks.ts backend/test/integration/repo_predictions.test.ts
git commit -m "backend: predictions + picks repos"
```

---

### Task 4: Scores repo

**Files:**
- Create: `backend/src/repo/scores.ts`
- Create: `backend/test/integration/repo_scores.test.ts`

- [ ] **Step 1: Write tests**

Create `backend/test/integration/repo_scores.test.ts`:

```ts
import { describe, it, expect } from 'vitest'
import * as users from '../../src/repo/users.js'
import * as seasons from '../../src/repo/seasons.js'
import * as events from '../../src/repo/events.js'
import * as sessions from '../../src/repo/sessions.js'
import * as leagues from '../../src/repo/leagues.js'
import * as members from '../../src/repo/leagueMembers.js'
import * as scores from '../../src/repo/scores.js'

async function seedSessions(count = 2) {
  await seasons.upsertSeason({ year: 2026, isCurrent: true })
  const ev = await events.upsertEvent({
    seasonYear: 2026, round: 1, name: 'Bahrain', circuitName: 'BIC', country: 'Bahrain', hasSprint: false
  })
  const out = []
  const types: ('race' | 'qualifying')[] = ['qualifying', 'race']
  for (let i = 0; i < count; i++) {
    const s = await sessions.upsertSession({
      eventId: ev.id, type: types[i % 2]!,
      scheduledStart: new Date(2026, 0, 1 + i),
      scheduledEnd: new Date(2026, 0, 1 + i, 2),
      status: 'scheduled'
    })
    out.push(s)
  }
  return { event: ev, sessions: out }
}

function breakdown(points: number) {
  return {
    perPosition: [{ position: 1, exact: true, wrongPos: false, points }],
    teamBonus: { applied: false, points: 0 },
    rule: 'test-v1'
  }
}

describe('scores repo', () => {
  it('upsert overwrites existing row', async () => {
    const { sessions: ss } = await seedSessions(1)
    const u = await users.insertUser({ email: 'a@x.com', passwordHash: 'h', displayName: 'A' })
    await scores.upsertScore(u.id, ss[0]!.id, 5, breakdown(5))
    await scores.upsertScore(u.id, ss[0]!.id, 12, breakdown(12))
    const list = await scores.listForUser(u.id, 2026)
    expect(list).toHaveLength(1)
    expect(list[0]!.pointsTotal).toBe(12)
  })

  it('league leaderboard sums per member', async () => {
    const { sessions: ss } = await seedSessions(3)
    const owner = await users.insertUser({ email: 'o@x.com', passwordHash: 'h', displayName: 'Owner' })
    const m1 = await users.insertUser({ email: 'm1@x.com', passwordHash: 'h', displayName: 'M1' })
    const m2 = await users.insertUser({ email: 'm2@x.com', passwordHash: 'h', displayName: 'M2' })
    const out = await users.insertUser({ email: 'out@x.com', passwordHash: 'h', displayName: 'Out' })
    const l = await leagues.createLeagueWithOwner({ name: 'L', ownerUserId: owner.id, joinCode: 'LBR001' })
    await members.add(l.id, m1.id)
    await members.add(l.id, m2.id)
    // owner gets points; m1 gets more points; m2 gets nothing; out (not a member) shouldn't appear
    await scores.upsertScore(owner.id, ss[0]!.id, 7,  breakdown(7))
    await scores.upsertScore(owner.id, ss[1]!.id, 3,  breakdown(3))
    await scores.upsertScore(m1.id,    ss[0]!.id, 17, breakdown(17))
    await scores.upsertScore(out.id,   ss[0]!.id, 99, breakdown(99))

    const lb = await scores.leagueLeaderboard(l.id, 2026)
    const byId = new Map(lb.map((r) => [r.userId, r]))
    expect(byId.size).toBe(3)  // owner + m1 + m2; out excluded
    expect(byId.get(owner.id)!.pointsTotal).toBe(10)
    expect(byId.get(owner.id)!.sessionsScored).toBe(2)
    expect(byId.get(m1.id)!.pointsTotal).toBe(17)
    expect(byId.get(m1.id)!.sessionsScored).toBe(1)
    expect(byId.get(m2.id)!.pointsTotal).toBe(0)
    expect(byId.get(m2.id)!.sessionsScored).toBe(0)
    // sort: desc by pointsTotal
    expect(lb[0]!.userId).toBe(m1.id)
  })

  it('leaderboard filters by season via event.season_year', async () => {
    await seasons.upsertSeason({ year: 2024, isCurrent: false })
    const ev2024 = await events.upsertEvent({
      seasonYear: 2024, round: 1, name: 'Old', circuitName: 'X', country: 'X', hasSprint: false
    })
    const old = await sessions.upsertSession({
      eventId: ev2024.id, type: 'race',
      scheduledStart: new Date(2024, 0, 1), scheduledEnd: new Date(2024, 0, 1, 2), status: 'scheduled'
    })
    const { sessions: ss } = await seedSessions(1)
    const owner = await users.insertUser({ email: 'o2@x.com', passwordHash: 'h', displayName: 'O' })
    const l = await leagues.createLeagueWithOwner({ name: 'L2', ownerUserId: owner.id, joinCode: 'LBR002' })
    await scores.upsertScore(owner.id, ss[0]!.id, 10, breakdown(10))
    await scores.upsertScore(owner.id, old.id, 100, breakdown(100))

    const lb2026 = await scores.leagueLeaderboard(l.id, 2026)
    expect(lb2026.find((r) => r.userId === owner.id)!.pointsTotal).toBe(10)

    const lb2024 = await scores.leagueLeaderboard(l.id, 2024)
    expect(lb2024.find((r) => r.userId === owner.id)!.pointsTotal).toBe(100)
  })

  it('listForUser returns scores with breakdown JSONB', async () => {
    const { sessions: ss } = await seedSessions(2)
    const u = await users.insertUser({ email: 'h@x.com', passwordHash: 'h', displayName: 'H' })
    await scores.upsertScore(u.id, ss[0]!.id, 5, breakdown(5))
    await scores.upsertScore(u.id, ss[1]!.id, 12, breakdown(12))
    const list = await scores.listForUser(u.id, 2026)
    expect(list).toHaveLength(2)
    expect(list[0]!.breakdown.rule).toBe('test-v1')
  })

  it('cascades from user delete', async () => {
    const { sessions: ss } = await seedSessions(1)
    const u = await users.insertUser({ email: 'c@x.com', passwordHash: 'h', displayName: 'C' })
    await scores.upsertScore(u.id, ss[0]!.id, 5, breakdown(5))
    await users.deleteById(u.id)
    const list = await scores.listForUser(u.id, 2026)
    expect(list).toEqual([])
  })
})
```

- [ ] **Step 2: Verify failing**

```bash
npx vitest run test/integration/repo_scores.test.ts
```
Expected: FAIL.

- [ ] **Step 3: Implement `src/repo/scores.ts`**

```ts
import { and, desc, eq, sql } from 'drizzle-orm'
import { getDb } from '../db/client.js'
import { score, session, event, leagueMember, user } from '../db/schema.js'
import type { Score, ScoreBreakdown } from '../domain/types.js'

export type LeaderboardRow = {
  userId: string
  displayName: string
  pointsTotal: number
  sessionsScored: number
}

export type UserScoreRow = Score & {
  sessionType: string
  sessionScheduledStart: Date
  eventRound: number
  eventName: string
}

export async function upsertScore(
  userId: string,
  sessionId: number,
  pointsTotal: number,
  breakdown: ScoreBreakdown
): Promise<void> {
  const db = getDb()
  await db.insert(score)
    .values({ userId, sessionId, pointsTotal, breakdown })
    .onConflictDoUpdate({
      target: [score.userId, score.sessionId],
      set: { pointsTotal, breakdown, computedAt: sql`now()` }
    })
}

export async function listForUser(userId: string, seasonYear: number): Promise<UserScoreRow[]> {
  const db = getDb()
  const rows = await db
    .select({
      userId: score.userId,
      sessionId: score.sessionId,
      pointsTotal: score.pointsTotal,
      breakdown: score.breakdown,
      computedAt: score.computedAt,
      sessionType: session.type,
      sessionScheduledStart: session.scheduledStart,
      eventRound: event.round,
      eventName: event.name
    })
    .from(score)
    .innerJoin(session, eq(session.id, score.sessionId))
    .innerJoin(event, eq(event.id, session.eventId))
    .where(and(eq(score.userId, userId), eq(event.seasonYear, seasonYear)))
    .orderBy(desc(session.scheduledStart))

  return rows.map((r) => ({
    userId: r.userId,
    sessionId: r.sessionId,
    pointsTotal: r.pointsTotal,
    breakdown: r.breakdown as ScoreBreakdown,
    computedAt: r.computedAt,
    sessionType: r.sessionType,
    sessionScheduledStart: r.sessionScheduledStart,
    eventRound: r.eventRound,
    eventName: r.eventName
  }))
}

/**
 * Per-league leaderboard for a season. Every league member appears, even those with zero score.
 */
export async function leagueLeaderboard(leagueId: string, seasonYear: number): Promise<LeaderboardRow[]> {
  const db = getDb()
  const rows = await db.execute(sql`
    SELECT
      lm.user_id::text AS "userId",
      u.display_name   AS "displayName",
      COALESCE(SUM(s.points_total), 0)::int AS "pointsTotal",
      COUNT(s.session_id)::int              AS "sessionsScored"
    FROM ${leagueMember} lm
    JOIN ${user} u ON u.id = lm.user_id
    LEFT JOIN ${score} s ON s.user_id = lm.user_id
    LEFT JOIN ${session} ses ON ses.id = s.session_id
    LEFT JOIN ${event} ev ON ev.id = ses.event_id AND ev.season_year = ${seasonYear}
    WHERE lm.league_id = ${leagueId}
      AND (s.session_id IS NULL OR ev.season_year = ${seasonYear})
    GROUP BY lm.user_id, u.display_name
    ORDER BY "pointsTotal" DESC, "displayName" ASC
  `)
  return (rows as unknown as { rows: LeaderboardRow[] }).rows
}

export type SessionLeaderboardRow = {
  sessionId: number
  sessionType: string
  eventRound: number
  eventName: string
  scheduledStart: Date
  members: { userId: string; displayName: string; pointsTotal: number; breakdown: ScoreBreakdown }[]
}

/**
 * Per-session breakdown for a league: every (member, session) row for the season, ordered chronologically.
 * Members with no score for a given session are omitted from that session's `members` array.
 */
export async function leagueSessionBreakdown(leagueId: string, seasonYear: number): Promise<SessionLeaderboardRow[]> {
  const db = getDb()
  const rows = await db
    .select({
      sessionId: score.sessionId,
      sessionType: session.type,
      eventRound: event.round,
      eventName: event.name,
      scheduledStart: session.scheduledStart,
      userId: score.userId,
      displayName: user.displayName,
      pointsTotal: score.pointsTotal,
      breakdown: score.breakdown
    })
    .from(score)
    .innerJoin(session, eq(session.id, score.sessionId))
    .innerJoin(event, eq(event.id, session.eventId))
    .innerJoin(user, eq(user.id, score.userId))
    .innerJoin(leagueMember, and(eq(leagueMember.userId, score.userId), eq(leagueMember.leagueId, leagueId)))
    .where(eq(event.seasonYear, seasonYear))
    .orderBy(desc(session.scheduledStart))

  const bySession = new Map<number, SessionLeaderboardRow>()
  for (const r of rows) {
    let entry = bySession.get(r.sessionId)
    if (!entry) {
      entry = {
        sessionId: r.sessionId,
        sessionType: r.sessionType,
        eventRound: r.eventRound,
        eventName: r.eventName,
        scheduledStart: r.scheduledStart,
        members: []
      }
      bySession.set(r.sessionId, entry)
    }
    entry.members.push({
      userId: r.userId,
      displayName: r.displayName,
      pointsTotal: r.pointsTotal,
      breakdown: r.breakdown as ScoreBreakdown
    })
  }
  return Array.from(bySession.values())
}
```

- [ ] **Step 4: Verify tests pass**

```bash
npx vitest run test/integration/repo_scores.test.ts
```
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
cd /Users/anton/Dev/Projects/F1predictiongame
git add backend/src/repo/scores.ts backend/test/integration/repo_scores.test.ts
git commit -m "backend: scores repo with per-league leaderboard"
```

---

### Task 5: Rescorer + tick integration

**Files:**
- Create: `backend/src/scoring/rescorer.ts`
- Modify: `backend/src/crawler/tick.ts`
- Create: `backend/test/integration/scoring_rescorer.test.ts`
- Create: `backend/test/integration/crawler_tick_rescore.test.ts`

The rescorer needs driver→constructor mappings even for non-finishers (to compute team bonus when the picked driver DNF'd but the teammate won). Use `driver_standing` for the session's season — it has `constructor_id` per driver.

- [ ] **Step 0: Add `listDriverStandings` to `src/repo/standings.ts`**

The rescorer needs to look up each driver's constructor for the team-bonus calculation (including for drivers who DNF'd and thus don't appear in `session_result`). Add this function to `backend/src/repo/standings.ts` (preserve existing exports; add imports `asc`, `and` if missing):

```ts
export async function listDriverStandings(seasonYear: number): Promise<{ driverCode: string; constructorId: string; position: number; points: number; wins: number }[]> {
  const db = getDb()
  const rows = await db.select().from(driverStanding).where(eq(driverStanding.seasonYear, seasonYear)).orderBy(asc(driverStanding.position))
  return rows.map((r) => ({
    driverCode: r.driverCode,
    constructorId: r.constructorId,
    position: r.position,
    points: r.points,
    wins: r.wins
  }))
}
```

- [ ] **Step 1: Write rescorer tests**

Create `backend/test/integration/scoring_rescorer.test.ts`:

```ts
import { describe, it, expect } from 'vitest'
import * as users from '../../src/repo/users.js'
import * as seasons from '../../src/repo/seasons.js'
import * as events from '../../src/repo/events.js'
import * as sessions from '../../src/repo/sessions.js'
import * as drivers from '../../src/repo/drivers.js'
import * as constructors from '../../src/repo/constructors.js'
import * as standings from '../../src/repo/standings.js'
import * as results from '../../src/repo/results.js'
import * as predictions from '../../src/repo/predictions.js'
import * as scores from '../../src/repo/scores.js'
import { rescoreSession } from '../../src/scoring/rescorer.js'

async function seedScene() {
  await seasons.upsertSeason({ year: 2026, isCurrent: true })
  const ev = await events.upsertEvent({
    seasonYear: 2026, round: 1, name: 'Bahrain', circuitName: 'BIC', country: 'Bahrain', hasSprint: false
  })
  const ses = await sessions.upsertSession({
    eventId: ev.id, type: 'race',
    scheduledStart: new Date(2026, 2, 8, 15),
    scheduledEnd: new Date(2026, 2, 8, 17), status: 'scheduled'
  })
  for (const c of [
    { id: 'red_bull', name: 'Red Bull' },
    { id: 'mercedes', name: 'Mercedes' },
    { id: 'mclaren',  name: 'McLaren' }
  ]) {
    await constructors.upsertConstructor({ ...c, nationality: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null })
  }
  for (const d of [
    { code: 'VER', team: 'red_bull' }, { code: 'PER', team: 'red_bull' },
    { code: 'HAM', team: 'mercedes' }, { code: 'RUS', team: 'mercedes' },
    { code: 'NOR', team: 'mclaren' },  { code: 'PIA', team: 'mclaren' }
  ]) {
    await drivers.upsertDriver({
      code: d.code, givenName: d.code, familyName: 'X', nationality: null, permanentNumber: null,
      wikipediaUrl: null, imageUrl: null, imageUrlOverride: null
    })
    await standings.replaceDriverStandings(2026, [
      // We append each driver to a single standings replacement; tests pass standings minimally
    ])
  }
  // Re-do standings with all drivers in one call (replaceDriverStandings truncates first)
  await standings.replaceDriverStandings(2026, [
    { driverCode: 'VER', position: 1, points: 0, wins: 0, constructorId: 'red_bull' },
    { driverCode: 'PER', position: 2, points: 0, wins: 0, constructorId: 'red_bull' },
    { driverCode: 'HAM', position: 3, points: 0, wins: 0, constructorId: 'mercedes' },
    { driverCode: 'RUS', position: 4, points: 0, wins: 0, constructorId: 'mercedes' },
    { driverCode: 'NOR', position: 5, points: 0, wins: 0, constructorId: 'mclaren' },
    { driverCode: 'PIA', position: 6, points: 0, wins: 0, constructorId: 'mclaren' }
  ])
  return ses
}

function resultRow(position: number, code: string, team: string) {
  return {
    sessionId: 0,  // overwritten by replaceForSession
    position, driverCode: code, driverName: code, constructorId: team, constructorName: team,
    raceTime: null, status: 'Finished', points: null,
    fastestLap: null, fastestLapTime: null, fastestLapSpeed: null,
    q1: null, q2: null, q3: null
  }
}

describe('rescoreSession', () => {
  it('writes score rows with breakdown for each predicting user', async () => {
    const ses = await seedScene()
    const u1 = await users.insertUser({ email: 'a@x.com', passwordHash: 'h', displayName: 'A' })
    const u2 = await users.insertUser({ email: 'b@x.com', passwordHash: 'h', displayName: 'B' })

    await predictions.upsertPredictionWithPicks(u1.id, ses.id, [
      { position: 1, driverCode: 'VER' },
      { position: 2, driverCode: 'HAM' },
      { position: 3, driverCode: 'NOR' },
      { position: 4, driverCode: 'PIA' },
      { position: 5, driverCode: 'RUS' }
    ])
    await predictions.upsertPredictionWithPicks(u2.id, ses.id, [
      { position: 1, driverCode: 'HAM' },
      { position: 2, driverCode: 'VER' },
      { position: 3, driverCode: 'NOR' },
      { position: 4, driverCode: 'PIA' },
      { position: 5, driverCode: 'RUS' }
    ])

    await results.replaceForSession(ses.id, [
      resultRow(1, 'VER', 'red_bull'),
      resultRow(2, 'HAM', 'mercedes'),
      resultRow(3, 'NOR', 'mclaren'),
      resultRow(4, 'PIA', 'mclaren'),
      resultRow(5, 'RUS', 'mercedes')
    ])

    const summary = await rescoreSession(ses.id)
    expect(summary.users).toBe(2)

    const u1Scores = await scores.listForUser(u1.id, 2026)
    expect(u1Scores[0]!.pointsTotal).toBe(17)  // all 5 exact + team bonus 2
    const u2Scores = await scores.listForUser(u2.id, 2026)
    // u2 swapped P1/P2 → wrongPos+wrongPos (1+1) + 3+3+3 exact P3-5 + no team bonus (HAM is mercedes, winner VER is red_bull) = 11
    expect(u2Scores[0]!.pointsTotal).toBe(11)
  })

  it('is idempotent: re-running overwrites scores', async () => {
    const ses = await seedScene()
    const u = await users.insertUser({ email: 'i@x.com', passwordHash: 'h', displayName: 'I' })
    await predictions.upsertPredictionWithPicks(u.id, ses.id, [
      { position: 1, driverCode: 'VER' },
      { position: 2, driverCode: 'HAM' },
      { position: 3, driverCode: 'NOR' },
      { position: 4, driverCode: 'PIA' },
      { position: 5, driverCode: 'RUS' }
    ])
    await results.replaceForSession(ses.id, [resultRow(1, 'VER', 'red_bull')])
    await rescoreSession(ses.id)
    const first = (await scores.listForUser(u.id, 2026))[0]!.pointsTotal

    // Add more results — should change the score
    await results.replaceForSession(ses.id, [
      resultRow(1, 'VER', 'red_bull'),
      resultRow(2, 'HAM', 'mercedes'),
      resultRow(3, 'NOR', 'mclaren'),
      resultRow(4, 'PIA', 'mclaren'),
      resultRow(5, 'RUS', 'mercedes')
    ])
    await rescoreSession(ses.id)
    const second = (await scores.listForUser(u.id, 2026))[0]!.pointsTotal
    expect(second).toBeGreaterThan(first)
  })

  it('no-ops if session has no results', async () => {
    const ses = await seedScene()
    const u = await users.insertUser({ email: 'n@x.com', passwordHash: 'h', displayName: 'N' })
    await predictions.upsertPredictionWithPicks(u.id, ses.id, [
      { position: 1, driverCode: 'VER' },
      { position: 2, driverCode: 'HAM' },
      { position: 3, driverCode: 'NOR' },
      { position: 4, driverCode: 'PIA' },
      { position: 5, driverCode: 'RUS' }
    ])
    const summary = await rescoreSession(ses.id)
    expect(summary).toEqual({ users: 0, totalPoints: 0 })
    expect(await scores.listForUser(u.id, 2026)).toEqual([])
  })

  it('no-ops if session type is not scorable', async () => {
    await seasons.upsertSeason({ year: 2026, isCurrent: true })
    const ev = await events.upsertEvent({
      seasonYear: 2026, round: 1, name: 'Bahrain', circuitName: 'BIC', country: 'B', hasSprint: false
    })
    const fp = await sessions.upsertSession({
      eventId: ev.id, type: 'fp1',
      scheduledStart: new Date(2026, 0, 1), scheduledEnd: new Date(2026, 0, 1, 1), status: 'scheduled'
    })
    const summary = await rescoreSession(fp.id)
    expect(summary).toEqual({ users: 0, totalPoints: 0 })
  })

  it('team bonus uses standings for DNF picks', async () => {
    const ses = await seedScene()
    const u = await users.insertUser({ email: 't@x.com', passwordHash: 'h', displayName: 'T' })
    // User picks PER for P1; PER DNF; teammate VER wins → team bonus should apply
    await predictions.upsertPredictionWithPicks(u.id, ses.id, [
      { position: 1, driverCode: 'PER' },
      { position: 2, driverCode: 'HAM' },
      { position: 3, driverCode: 'NOR' },
      { position: 4, driverCode: 'PIA' },
      { position: 5, driverCode: 'RUS' }
    ])
    // PER is absent from results (DNF before classification)
    await results.replaceForSession(ses.id, [
      resultRow(1, 'VER', 'red_bull'),
      resultRow(2, 'HAM', 'mercedes'),
      resultRow(3, 'NOR', 'mclaren'),
      resultRow(4, 'PIA', 'mclaren'),
      resultRow(5, 'RUS', 'mercedes')
    ])
    await rescoreSession(ses.id)
    const sc = (await scores.listForUser(u.id, 2026))[0]!
    // P1 PER no points (DNF, no exact, no wrongPos because not in finishers); P2-P5 all exact = 3*4 = 12; team bonus 2
    expect(sc.pointsTotal).toBe(14)
    expect(sc.breakdown.teamBonus).toEqual({ applied: true, points: 2 })
  })
})
```

- [ ] **Step 2: Verify failing**

```bash
npx vitest run test/integration/scoring_rescorer.test.ts
```
Expected: FAIL — `rescorer.js` module not found.

- [ ] **Step 3: Implement `src/scoring/rescorer.ts`**

```ts
import * as sessionsRepo from '../repo/sessions.js'
import * as eventsRepo from '../repo/events.js'
import * as resultsRepo from '../repo/results.js'
import * as predictionsRepo from '../repo/predictions.js'
import * as scoresRepo from '../repo/scores.js'
import * as standingsRepo from '../repo/standings.js'
import { scoreSession, isScorableSessionType } from './index.js'
import type { Finisher } from './types.js'

export type RescoreSummary = { users: number; totalPoints: number }

/**
 * Recompute and upsert scores for every prediction on this session.
 * No-op if the session type isn't scorable or no results exist yet.
 */
export async function rescoreSession(sessionId: number): Promise<RescoreSummary> {
  const ses = await sessionsRepo.getById(sessionId)
  if (!ses) return { users: 0, totalPoints: 0 }
  if (!isScorableSessionType(ses.type)) return { users: 0, totalPoints: 0 }

  const resultRows = await resultsRepo.listForSession(sessionId)
  if (resultRows.length === 0) return { users: 0, totalPoints: 0 }

  const ev = await eventsRepo.getById(ses.eventId)
  if (!ev) return { users: 0, totalPoints: 0 }

  // Build finisher list. To enable team-bonus calc for picks where the picked driver DNF'd,
  // pad with synthetic high-position entries from standings (one per non-finisher driver in season).
  const finisherCodes = new Set(resultRows.map((r) => r.driverCode))
  const standings = await standingsRepo.listDriverStandings(ev.seasonYear)
  const nonFinishers: Finisher[] = standings
    .filter((s) => !finisherCodes.has(s.driverCode))
    .map((s, i) => ({
      position: 1000 + i,  // arbitrary high — won't match any pick.position
      driverCode: s.driverCode,
      constructorId: s.constructorId
    }))
  const finishers: Finisher[] = [
    ...resultRows.map((r) => ({ position: r.position, driverCode: r.driverCode, constructorId: r.constructorId })),
    ...nonFinishers
  ]

  const predictions = await predictionsRepo.listForSessionWithPicks(sessionId)
  let totalPoints = 0
  for (const p of predictions) {
    if (p.picks.length === 0) continue
    let breakdown
    try {
      breakdown = scoreSession(ses.type, p.picks, finishers)
    } catch {
      continue  // skip predictions with wrong-shape picks (shouldn't happen with route-level validation)
    }
    const pts = breakdown.perPosition.reduce((s, x) => s + x.points, 0) + breakdown.teamBonus.points
    await scoresRepo.upsertScore(p.userId, sessionId, pts, breakdown)
    totalPoints += pts
  }

  return { users: predictions.length, totalPoints }
}
```

- [ ] **Step 4: Verify rescorer tests pass**

```bash
npx vitest run test/integration/scoring_rescorer.test.ts
```
Expected: PASS (5 tests).

(`listDriverStandings` was added in Step 0 above.)

- [ ] **Step 5: Write tick integration test**

Create `backend/test/integration/crawler_tick_rescore.test.ts`:

```ts
import { describe, it, expect, vi } from 'vitest'
import * as seasons from '../../src/repo/seasons.js'
import * as events from '../../src/repo/events.js'
import * as sessions from '../../src/repo/sessions.js'
import * as drivers from '../../src/repo/drivers.js'
import * as constructors from '../../src/repo/constructors.js'
import * as standings from '../../src/repo/standings.js'
import * as users from '../../src/repo/users.js'
import * as predictions from '../../src/repo/predictions.js'
import * as scores from '../../src/repo/scores.js'
import { runTick } from '../../src/crawler/tick.js'

class FakeJolpica {
  async getRaceResults() {
    return {
      MRData: {
        RaceTable: {
          Races: [{
            season: '2026', round: '1', raceName: 'Bahrain',
            Results: [
              { position: '1', Driver: { driverId: 'VER', code: 'VER', givenName: 'M', familyName: 'V', nationality: 'NL', permanentNumber: '33', url: '' }, Constructor: { constructorId: 'red_bull', name: 'Red Bull', nationality: 'A', url: '' }, grid: '1', laps: '1', status: 'Finished', Time: { time: '1:00:00' }, points: '25' }
            ]
          }]
        }
      }
    }
  }
  async getQualifyingResults() { return null }
  async getSprintResults() { return null }
  async getSprintQualifyingResults() { return null }
  async getDriverStandings() { return null }
  async getConstructorStandings() { return null }
}
class FakeWiki {
  async getImageUrl() { return null }
}

describe('tick triggers rescore', () => {
  it('after results upsert, score appears for predicting users', async () => {
    await seasons.upsertSeason({ year: 2026, isCurrent: true })
    const ev = await events.upsertEvent({
      seasonYear: 2026, round: 1, name: 'Bahrain', circuitName: 'BIC', country: 'B', hasSprint: false
    })
    const ses = await sessions.upsertSession({
      eventId: ev.id, type: 'race',
      scheduledStart: new Date(Date.now() - 3 * 60 * 60 * 1000),
      scheduledEnd: new Date(Date.now() - 60 * 60 * 1000),
      status: 'scheduled'
    })
    await constructors.upsertConstructor({ id: 'red_bull', name: 'Red Bull', nationality: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null })
    await drivers.upsertDriver({ code: 'VER', givenName: 'Max', familyName: 'V', nationality: 'NL', permanentNumber: 33, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null })
    await standings.replaceDriverStandings(2026, [
      { driverCode: 'VER', position: 1, points: 0, wins: 0, constructorId: 'red_bull' }
    ])

    const u = await users.insertUser({ email: 't@x.com', passwordHash: 'h', displayName: 'T' })
    await predictions.upsertPredictionWithPicks(u.id, ses.id, [
      { position: 1, driverCode: 'VER' },
      { position: 2, driverCode: 'VER' },  // any drivers; only P1 matters here
      { position: 3, driverCode: 'VER' },
      { position: 4, driverCode: 'VER' },
      { position: 5, driverCode: 'VER' }
    ])

    const summary = await runTick(new FakeJolpica() as any, new FakeWiki() as any)
    expect(summary.errors).toBe(0)

    const userScores = await scores.listForUser(u.id, 2026)
    expect(userScores).toHaveLength(1)
    expect(userScores[0]!.pointsTotal).toBeGreaterThan(0)
  })
})
```

- [ ] **Step 6: Verify failing**

```bash
npx vitest run test/integration/crawler_tick_rescore.test.ts
```
Expected: FAIL — the tick doesn't call rescoreSession yet.

- [ ] **Step 7: Wire rescorer into `src/crawler/tick.ts`**

Add this import at the top alongside other imports:

```ts
import { rescoreSession } from '../scoring/rescorer.js'
```

In `runTick`, inside the `for (const ses of candidates)` loop, AFTER `await sessionsRepo.markFinished(ses.id!)` and AFTER incrementing `summary.sessionsFinished`, add:

```ts
      try {
        const rescore = await rescoreSession(ses.id!)
        console.log('Rescored session', { sessionId: ses.id, ...rescore })
      } catch (err) {
        console.error('Rescore failed (results saved)', { sessionId: ses.id, err })
      }
```

The exact placement: immediately after `summary.sessionsFinished++; anyFinished = true` and before the `} catch (err) {` of the outer try block. The rescore failure is caught here so it doesn't propagate up and double-count `summary.errors`.

- [ ] **Step 8: Verify tick test passes**

```bash
npx vitest run test/integration/crawler_tick_rescore.test.ts
```
Expected: PASS.

- [ ] **Step 9: Run the whole suite**

```bash
npm test
npx tsc --noEmit
```
Expected: tsc clean; all tests still pass (Task 1-5 cumulative count should be a green run with no regressions).

- [ ] **Step 10: Commit**

```bash
cd /Users/anton/Dev/Projects/F1predictiongame
git add backend/src/scoring/rescorer.ts backend/src/crawler/tick.ts backend/test/integration/scoring_rescorer.test.ts backend/test/integration/crawler_tick_rescore.test.ts
git commit -m "backend: rescorer + tick integration"
```

---

### Task 6: Predictions routes

**Files:**
- Create: `backend/src/api/routes/predictions.ts`
- Modify: `backend/src/index.ts` (register routes)
- Create: `backend/test/integration/api_predictions.test.ts`

- [ ] **Step 1: Write tests**

Create `backend/test/integration/api_predictions.test.ts`:

```ts
import { describe, it, expect } from 'vitest'
import { buildApp } from '../../src/index.js'
import * as seasons from '../../src/repo/seasons.js'
import * as events from '../../src/repo/events.js'
import * as sessions from '../../src/repo/sessions.js'
import * as drivers from '../../src/repo/drivers.js'
import * as standings from '../../src/repo/standings.js'
import * as constructors from '../../src/repo/constructors.js'

async function seedScene() {
  await seasons.upsertSeason({ year: 2026, isCurrent: true })
  const ev = await events.upsertEvent({
    seasonYear: 2026, round: 1, name: 'Bahrain', circuitName: 'BIC', country: 'B', hasSprint: false
  })
  for (const c of ['red_bull', 'mercedes', 'mclaren']) {
    await constructors.upsertConstructor({ id: c, name: c, nationality: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null })
  }
  for (const code of ['VER', 'HAM', 'NOR', 'PIA', 'RUS']) {
    await drivers.upsertDriver({ code, givenName: code, familyName: 'X', nationality: null, permanentNumber: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null })
  }
  await standings.replaceDriverStandings(2026, [
    { driverCode: 'VER', position: 1, points: 0, wins: 0, constructorId: 'red_bull' },
    { driverCode: 'HAM', position: 2, points: 0, wins: 0, constructorId: 'mercedes' },
    { driverCode: 'NOR', position: 3, points: 0, wins: 0, constructorId: 'mclaren' },
    { driverCode: 'PIA', position: 4, points: 0, wins: 0, constructorId: 'mclaren' },
    { driverCode: 'RUS', position: 5, points: 0, wins: 0, constructorId: 'mercedes' }
  ])
  const futureSession = await sessions.upsertSession({
    eventId: ev.id, type: 'race',
    scheduledStart: new Date(Date.now() + 60 * 60 * 1000),
    scheduledEnd: new Date(Date.now() + 3 * 60 * 60 * 1000),
    status: 'scheduled'
  })
  const pastSession = await sessions.upsertSession({
    eventId: ev.id, type: 'qualifying',
    scheduledStart: new Date(Date.now() - 60 * 60 * 1000),
    scheduledEnd: new Date(Date.now() - 30 * 60 * 1000),
    status: 'scheduled'
  })
  return { ev, futureSession, pastSession }
}

async function buildAndUser() {
  const a = await buildApp({ scheduler: null })
  const r = await a.inject({ method: 'POST', url: '/api/auth/signup', payload: { email: `u-${Date.now()}@x.com`, password: 'hunter22', displayName: 'U' } })
  return { app: a, token: r.json().token as string }
}

const auth = (token: string) => ({ authorization: `Bearer ${token}` })
const racePicks = [
  { position: 1, driverCode: 'VER' },
  { position: 2, driverCode: 'HAM' },
  { position: 3, driverCode: 'NOR' },
  { position: 4, driverCode: 'PIA' },
  { position: 5, driverCode: 'RUS' }
]

describe('PUT /api/sessions/:id/my-prediction', () => {
  it('submits a race prediction (5 picks)', async () => {
    const { futureSession } = await seedScene()
    const { app, token } = await buildAndUser()
    const res = await app.inject({
      method: 'PUT', url: `/api/sessions/${futureSession.id}/my-prediction`,
      headers: auth(token), payload: { picks: racePicks }
    })
    expect(res.statusCode).toBe(200)
    expect(res.json().prediction.picks).toEqual(racePicks)
    expect(res.json().prediction.isLocked).toBe(false)
  })

  it('rejects after lock with 409', async () => {
    const { pastSession } = await seedScene()
    const { app, token } = await buildAndUser()
    const res = await app.inject({
      method: 'PUT', url: `/api/sessions/${pastSession.id}/my-prediction`,
      headers: auth(token),
      payload: { picks: [{ position: 1, driverCode: 'VER' }, { position: 2, driverCode: 'HAM' }] }
    })
    expect(res.statusCode).toBe(409)
  })

  it('rejects wrong pick count with 422', async () => {
    const { futureSession } = await seedScene()
    const { app, token } = await buildAndUser()
    const res = await app.inject({
      method: 'PUT', url: `/api/sessions/${futureSession.id}/my-prediction`,
      headers: auth(token), payload: { picks: [{ position: 1, driverCode: 'VER' }] }  // race needs 5
    })
    expect(res.statusCode).toBe(422)
  })

  it('rejects duplicate driver in picks with 422', async () => {
    const { futureSession } = await seedScene()
    const { app, token } = await buildAndUser()
    const res = await app.inject({
      method: 'PUT', url: `/api/sessions/${futureSession.id}/my-prediction`,
      headers: auth(token),
      payload: { picks: [
        { position: 1, driverCode: 'VER' }, { position: 2, driverCode: 'VER' },
        { position: 3, driverCode: 'NOR' }, { position: 4, driverCode: 'PIA' }, { position: 5, driverCode: 'RUS' }
      ] }
    })
    expect(res.statusCode).toBe(422)
  })

  it('rejects unknown driver with 422', async () => {
    const { futureSession } = await seedScene()
    const { app, token } = await buildAndUser()
    const res = await app.inject({
      method: 'PUT', url: `/api/sessions/${futureSession.id}/my-prediction`,
      headers: auth(token),
      payload: { picks: [
        { position: 1, driverCode: 'ZZZ' }, { position: 2, driverCode: 'HAM' },
        { position: 3, driverCode: 'NOR' }, { position: 4, driverCode: 'PIA' }, { position: 5, driverCode: 'RUS' }
      ] }
    })
    expect(res.statusCode).toBe(422)
  })

  it('edit replaces existing picks (idempotent)', async () => {
    const { futureSession } = await seedScene()
    const { app, token } = await buildAndUser()
    await app.inject({ method: 'PUT', url: `/api/sessions/${futureSession.id}/my-prediction`, headers: auth(token), payload: { picks: racePicks } })
    const edited = racePicks.map((p, i) => i === 0 ? { ...p, driverCode: 'HAM' } : i === 1 ? { ...p, driverCode: 'VER' } : p)
    const res = await app.inject({ method: 'PUT', url: `/api/sessions/${futureSession.id}/my-prediction`, headers: auth(token), payload: { picks: edited } })
    expect(res.statusCode).toBe(200)
    expect(res.json().prediction.picks[0]!.driverCode).toBe('HAM')
  })
})

describe('GET /api/sessions/:id/my-prediction', () => {
  it('returns 404 if no prediction yet', async () => {
    const { futureSession } = await seedScene()
    const { app, token } = await buildAndUser()
    const res = await app.inject({ method: 'GET', url: `/api/sessions/${futureSession.id}/my-prediction`, headers: auth(token) })
    expect(res.statusCode).toBe(404)
  })

  it('returns the submitted prediction', async () => {
    const { futureSession } = await seedScene()
    const { app, token } = await buildAndUser()
    await app.inject({ method: 'PUT', url: `/api/sessions/${futureSession.id}/my-prediction`, headers: auth(token), payload: { picks: racePicks } })
    const res = await app.inject({ method: 'GET', url: `/api/sessions/${futureSession.id}/my-prediction`, headers: auth(token) })
    expect(res.statusCode).toBe(200)
    expect(res.json().prediction.picks).toEqual(racePicks)
  })
})

describe('DELETE /api/sessions/:id/my-prediction', () => {
  it('removes a prediction before lock', async () => {
    const { futureSession } = await seedScene()
    const { app, token } = await buildAndUser()
    await app.inject({ method: 'PUT', url: `/api/sessions/${futureSession.id}/my-prediction`, headers: auth(token), payload: { picks: racePicks } })
    const del = await app.inject({ method: 'DELETE', url: `/api/sessions/${futureSession.id}/my-prediction`, headers: auth(token) })
    expect(del.statusCode).toBe(200)
    const get = await app.inject({ method: 'GET', url: `/api/sessions/${futureSession.id}/my-prediction`, headers: auth(token) })
    expect(get.statusCode).toBe(404)
  })

  it('409 after lock', async () => {
    const { pastSession } = await seedScene()
    const { app, token } = await buildAndUser()
    const res = await app.inject({ method: 'DELETE', url: `/api/sessions/${pastSession.id}/my-prediction`, headers: auth(token) })
    expect(res.statusCode).toBe(409)
  })
})

describe('GET /api/sessions/:id/predictions', () => {
  it('403 before lock', async () => {
    const { futureSession } = await seedScene()
    const { app, token } = await buildAndUser()
    const res = await app.inject({ method: 'GET', url: `/api/sessions/${futureSession.id}/predictions`, headers: auth(token) })
    expect(res.statusCode).toBe(403)
  })

  it('200 after lock, returns everyone\'s picks', async () => {
    const { pastSession } = await seedScene()
    const { app, token } = await buildAndUser()
    // Submit a prediction first by manipulating data — bypass lock by submitting via PUT on a future-rescheduled session is hard,
    // so for this assertion we just verify the GET endpoint returns 200 for the past session.
    const res = await app.inject({ method: 'GET', url: `/api/sessions/${pastSession.id}/predictions`, headers: auth(token) })
    expect(res.statusCode).toBe(200)
    expect(Array.isArray(res.json().predictions)).toBe(true)
  })
})

describe('GET /api/predictions/upcoming', () => {
  it('lists upcoming scorable sessions with myPicks status', async () => {
    const { futureSession } = await seedScene()
    const { app, token } = await buildAndUser()
    const before = await app.inject({ method: 'GET', url: '/api/predictions/upcoming', headers: auth(token) })
    expect(before.statusCode).toBe(200)
    const entry = before.json().upcoming.find((u: any) => u.session.id === futureSession.id)
    expect(entry).toBeDefined()
    expect(entry.isLocked).toBe(false)
    expect(entry.myPicks).toBeNull()

    await app.inject({ method: 'PUT', url: `/api/sessions/${futureSession.id}/my-prediction`, headers: auth(token), payload: { picks: racePicks } })
    const after = await app.inject({ method: 'GET', url: '/api/predictions/upcoming', headers: auth(token) })
    const entry2 = after.json().upcoming.find((u: any) => u.session.id === futureSession.id)
    expect(entry2.myPicks).toHaveLength(5)
  })
})
```

- [ ] **Step 2: Implement `src/api/routes/predictions.ts`**

```ts
import type { FastifyInstance } from 'fastify'
import { z } from 'zod'
import { ApiError } from '../errors.js'
import { getCurrentUser, registerAuthHook } from '../auth-context.js'
import * as sessionsRepo from '../../repo/sessions.js'
import * as eventsRepo from '../../repo/events.js'
import * as seasonsRepo from '../../repo/seasons.js'
import * as predictionsRepo from '../../repo/predictions.js'
import * as picksRepo from '../../repo/predictionPicks.js'
import * as driversRepo from '../../repo/drivers.js'
import * as standingsRepo from '../../repo/standings.js'
import { isScorableSessionType, picksRequiredFor } from '../../scoring/index.js'
import type { SessionType } from '../../domain/types.js'

const pickSchema = z.object({
  position: z.number().int().min(1).max(20),
  driverCode: z.string().min(1).max(10)
})

const putBody = z.object({
  picks: z.array(pickSchema).min(1).max(20)
})

function parse<T>(schema: z.ZodType<T>, body: unknown): T {
  const r = schema.safeParse(body)
  if (!r.success) throw new ApiError('VALIDATION', r.error.issues[0]?.message ?? 'Invalid request body')
  return r.data
}

async function requireSessionUnlocked(sessionId: number) {
  const s = await sessionsRepo.getById(sessionId)
  if (!s) throw new ApiError('NOT_FOUND', 'Session not found')
  if (s.scheduledStart.getTime() <= Date.now()) {
    throw new ApiError('CONFLICT', 'Predictions for this session are locked')
  }
  return s
}

async function requireSessionLocked(sessionId: number) {
  const s = await sessionsRepo.getById(sessionId)
  if (!s) throw new ApiError('NOT_FOUND', 'Session not found')
  if (s.scheduledStart.getTime() > Date.now()) {
    throw new ApiError('FORBIDDEN', 'Other users\' predictions are visible only after lock')
  }
  return s
}

async function validatePicksForSessionType(sessionType: SessionType, picks: { position: number; driverCode: string }[]) {
  if (!isScorableSessionType(sessionType)) {
    throw new ApiError('VALIDATION', `Session type ${sessionType} is not scorable`)
  }
  const expected = picksRequiredFor(sessionType)!
  if (picks.length !== expected) {
    throw new ApiError('VALIDATION', `${sessionType} expects ${expected} picks, got ${picks.length}`)
  }
  const positions = picks.map((p) => p.position).sort((a, b) => a - b)
  for (let i = 0; i < expected; i++) {
    if (positions[i] !== i + 1) {
      throw new ApiError('VALIDATION', `picks.position must be exactly 1..${expected}`)
    }
  }
  const driverSet = new Set(picks.map((p) => p.driverCode))
  if (driverSet.size !== picks.length) {
    throw new ApiError('VALIDATION', 'duplicate driver in picks')
  }
  // All drivers exist and are in the current season
  const cur = await seasonsRepo.getCurrent()
  if (!cur) throw new ApiError('VALIDATION', 'No current season')
  for (const p of picks) {
    if (!(await driversRepo.exists(p.driverCode))) {
      throw new ApiError('VALIDATION', `Unknown driver: ${p.driverCode}`)
    }
    if (!(await standingsRepo.driverHasStandingForYear(p.driverCode, cur.year))) {
      throw new ApiError('VALIDATION', `Driver ${p.driverCode} not in current season`)
    }
  }
}

export async function registerPredictionRoutes(app: FastifyInstance): Promise<void> {
  registerAuthHook(app)

  app.put<{ Params: { id: string } }>('/api/sessions/:id/my-prediction', async (req) => {
    const u = getCurrentUser(req)
    const sessionId = Number(req.params.id)
    if (!Number.isFinite(sessionId)) throw new ApiError('BAD_REQUEST', 'id must be a number')
    const body = parse(putBody, req.body)
    const s = await requireSessionUnlocked(sessionId)
    await validatePicksForSessionType(s.type, body.picks)
    const sortedPicks = [...body.picks].sort((a, b) => a.position - b.position)
    await predictionsRepo.upsertPredictionWithPicks(u.id, sessionId, sortedPicks)
    return {
      prediction: {
        sessionId,
        picks: sortedPicks,
        isLocked: false
      }
    }
  })

  app.get<{ Params: { id: string } }>('/api/sessions/:id/my-prediction', async (req) => {
    const u = getCurrentUser(req)
    const sessionId = Number(req.params.id)
    if (!Number.isFinite(sessionId)) throw new ApiError('BAD_REQUEST', 'id must be a number')
    const s = await sessionsRepo.getById(sessionId)
    if (!s) throw new ApiError('NOT_FOUND', 'Session not found')
    const p = await predictionsRepo.getByUserAndSession(u.id, sessionId)
    if (!p) throw new ApiError('NOT_FOUND', 'No prediction for this session')
    const picks = await picksRepo.listForPrediction(p.id)
    return {
      prediction: {
        sessionId,
        picks,
        updatedAt: p.updatedAt,
        isLocked: s.scheduledStart.getTime() <= Date.now()
      }
    }
  })

  app.delete<{ Params: { id: string } }>('/api/sessions/:id/my-prediction', async (req) => {
    const u = getCurrentUser(req)
    const sessionId = Number(req.params.id)
    if (!Number.isFinite(sessionId)) throw new ApiError('BAD_REQUEST', 'id must be a number')
    await requireSessionUnlocked(sessionId)
    await predictionsRepo.deleteByUserAndSession(u.id, sessionId)
    return { ok: true }
  })

  app.get<{ Params: { id: string } }>('/api/sessions/:id/predictions', async (req) => {
    const sessionId = Number(req.params.id)
    if (!Number.isFinite(sessionId)) throw new ApiError('BAD_REQUEST', 'id must be a number')
    await requireSessionLocked(sessionId)
    const list = await predictionsRepo.listForSessionWithPicks(sessionId)
    return { predictions: list }
  })

  app.get('/api/predictions/upcoming', async (req) => {
    const u = getCurrentUser(req)
    const cur = await seasonsRepo.getCurrent()
    if (!cur) return { upcoming: [] }
    const events = await eventsRepo.listForSeason(cur.year)
    const upcoming: any[] = []
    for (const ev of events) {
      const allSessions = await sessionsRepo.listForEvent(ev.id)
      for (const s of allSessions) {
        if (!isScorableSessionType(s.type)) continue
        const myPrediction = await predictionsRepo.getByUserAndSession(u.id, s.id)
        const myPicks = myPrediction ? await picksRepo.listForPrediction(myPrediction.id) : null
        upcoming.push({
          session: { id: s.id, type: s.type },
          event: { id: ev.id, round: ev.round, name: ev.name, country: ev.country },
          picksRequired: picksRequiredFor(s.type)!,
          locksAt: s.scheduledStart,
          isLocked: s.scheduledStart.getTime() <= Date.now(),
          myPicks
        })
      }
    }
    upcoming.sort((a, b) => new Date(a.locksAt).getTime() - new Date(b.locksAt).getTime())
    return { upcoming }
  })
}
```

- [ ] **Step 3: Add `driverHasStandingForYear` to standings repo**

Open `backend/src/repo/standings.ts`. Add (preserve existing exports):

```ts
export async function driverHasStandingForYear(driverCode: string, seasonYear: number): Promise<boolean> {
  const db = getDb()
  const rows = await db.select({ c: driverStanding.driverCode })
    .from(driverStanding)
    .where(and(eq(driverStanding.driverCode, driverCode), eq(driverStanding.seasonYear, seasonYear)))
    .limit(1)
  return rows.length > 0
}
```

(If `and`, `eq`, `driverStanding` aren't already imported in that file, add them — match the existing import style. `listDriverStandings` was already added in Task 5 Step 0.)

- [ ] **Step 4: Register route in `src/index.ts`**

Add import alongside other route imports:

```ts
import { registerPredictionRoutes } from './api/routes/predictions.js'
```

Inside `buildApp`, after `await app.register(registerLeagueRoutes)`:

```ts
await app.register(registerPredictionRoutes)
```

- [ ] **Step 5: Verify tests pass**

```bash
cd /Users/anton/Dev/Projects/F1predictiongame/backend
set -a && source .env && set +a
npx vitest run test/integration/api_predictions.test.ts
```
Expected: PASS (~14 tests).

```bash
npm test
npx tsc --noEmit
```
Expected: full suite green; tsc clean.

- [ ] **Step 6: Commit**

```bash
cd /Users/anton/Dev/Projects/F1predictiongame
git add backend/src/api/routes/predictions.ts backend/src/repo/standings.ts backend/src/index.ts backend/test/integration/api_predictions.test.ts
git commit -m "backend: /api/predictions and /api/sessions/:id/my-prediction routes"
```

---

### Task 7: Leaderboard routes + admin rescore endpoints

**Files:**
- Create: `backend/src/api/routes/leaderboard.ts`
- Modify: `backend/src/api/routes/admin.ts` (add 2 rescore endpoints)
- Modify: `backend/src/index.ts` (register leaderboard routes)
- Create: `backend/test/integration/api_leaderboard.test.ts`
- Create: `backend/test/integration/api_admin_rescore.test.ts`

- [ ] **Step 1: Write leaderboard tests**

Create `backend/test/integration/api_leaderboard.test.ts`:

```ts
import { describe, it, expect } from 'vitest'
import { buildApp } from '../../src/index.js'
import * as seasons from '../../src/repo/seasons.js'
import * as events from '../../src/repo/events.js'
import * as sessions from '../../src/repo/sessions.js'
import * as drivers from '../../src/repo/drivers.js'
import * as constructors from '../../src/repo/constructors.js'
import * as standings from '../../src/repo/standings.js'
import * as scores from '../../src/repo/scores.js'

async function seed() {
  await seasons.upsertSeason({ year: 2026, isCurrent: true })
  const ev = await events.upsertEvent({
    seasonYear: 2026, round: 1, name: 'Bahrain', circuitName: 'BIC', country: 'B', hasSprint: false
  })
  await constructors.upsertConstructor({ id: 'red_bull', name: 'Red Bull', nationality: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null })
  await drivers.upsertDriver({ code: 'VER', givenName: 'M', familyName: 'V', nationality: null, permanentNumber: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null })
  await standings.replaceDriverStandings(2026, [{ driverCode: 'VER', position: 1, points: 0, wins: 0, constructorId: 'red_bull' }])
  const s1 = await sessions.upsertSession({
    eventId: ev.id, type: 'race',
    scheduledStart: new Date(2026, 2, 8, 15), scheduledEnd: new Date(2026, 2, 8, 17), status: 'scheduled'
  })
  return { s1 }
}

function bd(points: number) {
  return { perPosition: [{ position: 1, exact: true, wrongPos: false, points }], teamBonus: { applied: false, points: 0 }, rule: 't-v1' }
}

async function buildAndUser(emailHint: string) {
  const a = await buildApp({ scheduler: null })
  const r = await a.inject({ method: 'POST', url: '/api/auth/signup', payload: { email: `${emailHint}-${Date.now()}@x.com`, password: 'hunter22', displayName: emailHint } })
  return { app: a, token: r.json().token as string, userId: r.json().user.id as string }
}

const auth = (t: string) => ({ authorization: `Bearer ${t}` })

describe('GET /api/leagues/:id/leaderboard', () => {
  it('member-only, sorted by points desc', async () => {
    const { s1 } = await seed()
    const owner = await buildAndUser('owner')
    const m1    = await buildAndUser('m1')
    const out   = await buildAndUser('out')
    const lc = await owner.app.inject({ method: 'POST', url: '/api/leagues', headers: auth(owner.token), payload: { name: 'L' } })
    const leagueId = lc.json().league.id
    const code = lc.json().league.joinCode
    await m1.app.inject({ method: 'POST', url: '/api/leagues/join', headers: auth(m1.token), payload: { joinCode: code } })

    await scores.upsertScore(owner.userId, s1.id, 10, bd(10))
    await scores.upsertScore(m1.userId,    s1.id, 25, bd(25))
    await scores.upsertScore(out.userId,   s1.id, 99, bd(99))

    const memberView = await owner.app.inject({ method: 'GET', url: `/api/leagues/${leagueId}/leaderboard`, headers: auth(owner.token) })
    expect(memberView.statusCode).toBe(200)
    const rows = memberView.json().leaderboard
    expect(rows[0]!.userId).toBe(m1.userId)
    expect(rows[0]!.pointsTotal).toBe(25)
    expect(rows[1]!.userId).toBe(owner.userId)
    expect(rows.length).toBe(2)  // 'out' not in league

    const outsiderView = await out.app.inject({ method: 'GET', url: `/api/leagues/${leagueId}/leaderboard`, headers: auth(out.token) })
    expect(outsiderView.statusCode).toBe(403)
  })

  it('season filter via ?season=YYYY', async () => {
    const { s1 } = await seed()
    const owner = await buildAndUser('o')
    const lc = await owner.app.inject({ method: 'POST', url: '/api/leagues', headers: auth(owner.token), payload: { name: 'LX' } })
    const leagueId = lc.json().league.id
    await scores.upsertScore(owner.userId, s1.id, 10, bd(10))
    const r = await owner.app.inject({ method: 'GET', url: `/api/leagues/${leagueId}/leaderboard?season=2024`, headers: auth(owner.token) })
    expect(r.statusCode).toBe(200)
    expect(r.json().leaderboard[0]!.pointsTotal).toBe(0)
  })
})

describe('GET /api/leagues/:id/leaderboard/sessions', () => {
  it('returns per-session per-member rows', async () => {
    const { s1 } = await seed()
    const owner = await buildAndUser('o')
    const m1 = await buildAndUser('m')
    const lc = await owner.app.inject({ method: 'POST', url: '/api/leagues', headers: auth(owner.token), payload: { name: 'LS' } })
    const leagueId = lc.json().league.id
    const code = lc.json().league.joinCode
    await m1.app.inject({ method: 'POST', url: '/api/leagues/join', headers: auth(m1.token), payload: { joinCode: code } })
    await scores.upsertScore(owner.userId, s1.id, 10, bd(10))
    await scores.upsertScore(m1.userId,    s1.id, 7,  bd(7))

    const r = await owner.app.inject({ method: 'GET', url: `/api/leagues/${leagueId}/leaderboard/sessions`, headers: auth(owner.token) })
    expect(r.statusCode).toBe(200)
    const arr = r.json().sessions
    expect(arr).toHaveLength(1)
    expect(arr[0]!.members).toHaveLength(2)
  })
})

describe('GET /api/users/me/scores', () => {
  it('returns caller score history', async () => {
    const { s1 } = await seed()
    const me = await buildAndUser('me')
    await scores.upsertScore(me.userId, s1.id, 7, bd(7))
    const r = await me.app.inject({ method: 'GET', url: '/api/users/me/scores', headers: auth(me.token) })
    expect(r.statusCode).toBe(200)
    expect(r.json().scores).toHaveLength(1)
    expect(r.json().scores[0]!.pointsTotal).toBe(7)
  })
})
```

- [ ] **Step 2: Implement `src/api/routes/leaderboard.ts`**

```ts
import type { FastifyInstance } from 'fastify'
import { ApiError } from '../errors.js'
import { getCurrentUser, registerAuthHook, requireLeagueMember } from '../auth-context.js'
import * as scoresRepo from '../../repo/scores.js'
import * as seasonsRepo from '../../repo/seasons.js'

function seasonFromQuery(q: unknown, fallback: number): number {
  const s = (q as any)?.season
  if (s === undefined) return fallback
  const n = Number(s)
  if (!Number.isFinite(n)) throw new ApiError('BAD_REQUEST', 'season must be a number')
  return n
}

export async function registerLeaderboardRoutes(app: FastifyInstance): Promise<void> {
  registerAuthHook(app)

  app.get<{ Params: { id: string }; Querystring: { season?: string } }>(
    '/api/leagues/:id/leaderboard',
    async (req) => {
      await requireLeagueMember(req, req.params.id)
      const cur = await seasonsRepo.getCurrent()
      const season = seasonFromQuery(req.query, cur?.year ?? new Date().getUTCFullYear())
      const leaderboard = await scoresRepo.leagueLeaderboard(req.params.id, season)
      return { leaderboard, season }
    }
  )

  app.get<{ Params: { id: string }; Querystring: { season?: string } }>(
    '/api/leagues/:id/leaderboard/sessions',
    async (req) => {
      await requireLeagueMember(req, req.params.id)
      const cur = await seasonsRepo.getCurrent()
      const season = seasonFromQuery(req.query, cur?.year ?? new Date().getUTCFullYear())
      const sessions = await scoresRepo.leagueSessionBreakdown(req.params.id, season)
      return { sessions, season }
    }
  )

  app.get<{ Querystring: { season?: string } }>('/api/users/me/scores', async (req) => {
    const u = getCurrentUser(req)
    const cur = await seasonsRepo.getCurrent()
    const season = seasonFromQuery(req.query, cur?.year ?? new Date().getUTCFullYear())
    const scores = await scoresRepo.listForUser(u.id, season)
    return { scores, season }
  })
}
```

- [ ] **Step 3: Register leaderboard routes in `src/index.ts`**

Add import:
```ts
import { registerLeaderboardRoutes } from './api/routes/leaderboard.js'
```

Inside `buildApp`, after `await app.register(registerPredictionRoutes)`:
```ts
await app.register(registerLeaderboardRoutes)
```

- [ ] **Step 4: Extend admin routes**

In `backend/src/api/routes/admin.ts`, add this import alongside existing imports:

```ts
import { rescoreSession } from '../../scoring/rescorer.js'
import * as eventsRepo from '../../repo/events.js'
import * as sessionsRepo from '../../repo/sessions.js'
```

Inside `registerAdminRoutes`, alongside the existing endpoints, add:

```ts
  app.post<{ Params: { id: string } }>('/admin/rescore-session/:id', async (req) => {
    const id = Number(req.params.id)
    if (!Number.isFinite(id)) throw new ApiError('BAD_REQUEST', 'id must be a number')
    const summary = await rescoreSession(id)
    return { ok: true, sessionId: id, ...summary }
  })

  app.post<{ Params: { year: string } }>('/admin/rescore-season/:year', async (req) => {
    const year = Number(req.params.year)
    if (!Number.isFinite(year)) throw new ApiError('BAD_REQUEST', 'year must be a number')
    const evs = await eventsRepo.listForSeason(year)
    let users = 0, totalPoints = 0
    for (const ev of evs) {
      const sessions = await sessionsRepo.listForEvent(ev.id)
      for (const ses of sessions) {
        const summary = await rescoreSession(ses.id)
        users += summary.users
        totalPoints += summary.totalPoints
      }
    }
    return { ok: true, season: year, users, totalPoints }
  })
```

- [ ] **Step 5: Write admin tests**

Create `backend/test/integration/api_admin_rescore.test.ts`:

```ts
import { describe, it, expect } from 'vitest'
import { buildApp } from '../../src/index.js'
import * as seasons from '../../src/repo/seasons.js'
import * as events from '../../src/repo/events.js'
import * as sessions from '../../src/repo/sessions.js'
import * as drivers from '../../src/repo/drivers.js'
import * as constructors from '../../src/repo/constructors.js'
import * as standings from '../../src/repo/standings.js'
import * as results from '../../src/repo/results.js'
import * as users from '../../src/repo/users.js'
import * as predictions from '../../src/repo/predictions.js'
import * as scoresRepo from '../../src/repo/scores.js'

const TOKEN = { 'x-admin-token': 'local-dev-token' }

async function seed() {
  await seasons.upsertSeason({ year: 2026, isCurrent: true })
  const ev = await events.upsertEvent({ seasonYear: 2026, round: 1, name: 'B', circuitName: 'C', country: 'X', hasSprint: false })
  const ses = await sessions.upsertSession({
    eventId: ev.id, type: 'race',
    scheduledStart: new Date(Date.now() - 3 * 60 * 60 * 1000),
    scheduledEnd: new Date(Date.now() - 60 * 60 * 1000), status: 'scheduled'
  })
  await constructors.upsertConstructor({ id: 'red_bull', name: 'Red Bull', nationality: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null })
  await drivers.upsertDriver({ code: 'VER', givenName: 'M', familyName: 'V', nationality: null, permanentNumber: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null })
  await standings.replaceDriverStandings(2026, [{ driverCode: 'VER', position: 1, points: 0, wins: 0, constructorId: 'red_bull' }])
  return { ev, ses }
}

describe('POST /admin/rescore-session/:id', () => {
  it('requires admin token', async () => {
    const { ses } = await seed()
    const app = await buildApp({ scheduler: null })
    const r = await app.inject({ method: 'POST', url: `/admin/rescore-session/${ses.id}` })
    expect(r.statusCode).toBe(401)
  })

  it('rescores a single session', async () => {
    const { ses } = await seed()
    const app = await buildApp({ scheduler: null })
    const u = await users.insertUser({ email: 'ad@x.com', passwordHash: 'h', displayName: 'A' })
    await predictions.upsertPredictionWithPicks(u.id, ses.id, [
      { position: 1, driverCode: 'VER' }, { position: 2, driverCode: 'VER' },
      { position: 3, driverCode: 'VER' }, { position: 4, driverCode: 'VER' }, { position: 5, driverCode: 'VER' }
    ])
    await results.replaceForSession(ses.id, [
      { sessionId: ses.id, position: 1, driverCode: 'VER', driverName: 'V', constructorId: 'red_bull', constructorName: 'RB', raceTime: null, status: 'Finished', points: null, fastestLap: null, fastestLapTime: null, fastestLapSpeed: null, q1: null, q2: null, q3: null }
    ])
    const r = await app.inject({ method: 'POST', url: `/admin/rescore-session/${ses.id}`, headers: TOKEN })
    expect(r.statusCode).toBe(200)
    expect(r.json().users).toBe(1)
    expect((await scoresRepo.listForUser(u.id, 2026))[0]!.pointsTotal).toBeGreaterThan(0)
  })
})

describe('POST /admin/rescore-season/:year', () => {
  it('rescores all sessions in a season', async () => {
    const { ses } = await seed()
    const app = await buildApp({ scheduler: null })
    const u = await users.insertUser({ email: 'ad2@x.com', passwordHash: 'h', displayName: 'A2' })
    await predictions.upsertPredictionWithPicks(u.id, ses.id, [
      { position: 1, driverCode: 'VER' }, { position: 2, driverCode: 'VER' },
      { position: 3, driverCode: 'VER' }, { position: 4, driverCode: 'VER' }, { position: 5, driverCode: 'VER' }
    ])
    await results.replaceForSession(ses.id, [
      { sessionId: ses.id, position: 1, driverCode: 'VER', driverName: 'V', constructorId: 'red_bull', constructorName: 'RB', raceTime: null, status: 'Finished', points: null, fastestLap: null, fastestLapTime: null, fastestLapSpeed: null, q1: null, q2: null, q3: null }
    ])
    const r = await app.inject({ method: 'POST', url: '/admin/rescore-season/2026', headers: TOKEN })
    expect(r.statusCode).toBe(200)
    expect(r.json().users).toBeGreaterThan(0)
  })
})
```

- [ ] **Step 6: Verify all tests pass**

```bash
cd /Users/anton/Dev/Projects/F1predictiongame/backend
set -a && source .env && set +a
npm test
npx tsc --noEmit
```
Expected: full suite green; tsc clean.

- [ ] **Step 7: Commit**

```bash
cd /Users/anton/Dev/Projects/F1predictiongame
git add backend/src/api/routes/leaderboard.ts backend/src/api/routes/admin.ts backend/src/index.ts backend/test/integration/api_leaderboard.test.ts backend/test/integration/api_admin_rescore.test.ts
git commit -m "backend: leaderboard routes + admin rescore endpoints"
```

---

### Task 8: Factories + README + final verification

**Files:**
- Modify: `backend/test/helpers/factories.ts`
- Modify: `backend/README.md`

- [ ] **Step 1: Extend `test/helpers/factories.ts`**

Append (preserve existing `makeUser` and `makeLeague`):

```ts
import * as sessions from '../../src/repo/sessions.js'
import * as predictionsRepo from '../../src/repo/predictions.js'
import type { SessionType } from '../../src/domain/types.js'

export async function makeSession(
  eventId: number,
  type: SessionType = 'race',
  overrides: Partial<{ scheduledStart: Date; scheduledEnd: Date }> = {}
) {
  const start = overrides.scheduledStart ?? new Date(Date.now() + 24 * 60 * 60 * 1000)
  const end = overrides.scheduledEnd ?? new Date(start.getTime() + 2 * 60 * 60 * 1000)
  return sessions.upsertSession({
    eventId, type, scheduledStart: start, scheduledEnd: end, status: 'scheduled'
  })
}

export async function makePrediction(
  userId: string,
  sessionId: number,
  picks: { position: number; driverCode: string }[]
) {
  return predictionsRepo.upsertPredictionWithPicks(userId, sessionId, picks)
}
```

- [ ] **Step 2: Update `backend/README.md`**

Read current README first. Then:

**a)** Add new endpoint rows to the API table (group near related ones — predictions near the auth/league block; admin near the existing `/admin/*` block):

```
| GET  | `/api/predictions/upcoming` | Caller's upcoming scorable sessions, with `myPicks` (bearer) |
| GET  | `/api/sessions/:id/my-prediction` | Caller's prediction for a session (bearer) |
| PUT  | `/api/sessions/:id/my-prediction` | Submit/replace caller's picks; 409 after lock (bearer) |
| DELETE | `/api/sessions/:id/my-prediction` | Remove caller's prediction; 409 after lock (bearer) |
| GET  | `/api/sessions/:id/predictions` | Everyone's picks; only after lock (bearer) |
| GET  | `/api/leagues/:id/leaderboard` | League leaderboard, sums of `score.points_total` (bearer + member) |
| GET  | `/api/leagues/:id/leaderboard/sessions` | Per-session per-member breakdown (bearer + member) |
| GET  | `/api/users/me/scores` | Caller's score history (bearer) |
| POST | `/admin/rescore-session/:id` | Force rescore of one session (token-gated) |
| POST | `/admin/rescore-season/:year` | Rescore every finished session in a season (token-gated) |
```

**b)** Add a "Scoring" section (concise) after the API table:

```
## Scoring

Per race weekend, four scorable session kinds:

| Kind | Picks | Per-position exact | Wrong position | Team bonus | Max |
|---|---|---|---|---|---|
| Qualifying | P1, P2 | 3 each | 1 each | +1 if pole pick's team matches pole | 7 |
| Sprint Shootout | P1 | 1 | — | +1 if P1 pick's team matches | 2 |
| Sprint Race | P1, P2, P3 | 2 each | 1 each | +1 if winning team correct | 7 |
| Race | P1–P5 | 3 each | 1 each | +2 if winning team correct | 17 |

Picks lock at the session's scheduled start. The crawler auto-rescores after writing
results, so FIA penalty updates flow through to scores automatically. Manual rescore
is available via the `/admin/rescore-*` endpoints.
```

**c)** In "What's NOT in this sub-project" — remove anything about predictions/scoring; keep only "pre-season questionnaire, Flutter UI changes" as still-deferred.

- [ ] **Step 3: Run the full test suite**

```bash
cd /Users/anton/Dev/Projects/F1predictiongame/backend
set -a && source .env && set +a
npm test
npx tsc --noEmit
```
Expected: full suite green; tsc clean.

- [ ] **Step 4: Manual smoke test (optional, if dev server is running)**

```bash
TOKEN=$(curl -s -X POST http://localhost:3000/api/auth/signup \
  -H 'content-type: application/json' \
  -d '{"email":"smoke-p@x.com","password":"hunter22","displayName":"SP"}' | jq -r .token)

curl -s -H "authorization: Bearer $TOKEN" http://localhost:3000/api/predictions/upcoming | jq '.upcoming[0]'
```
Expected: returns a session entry with `picksRequired` and `isLocked`. If no current season is bootstrapped or no sessions exist yet, returns `{ upcoming: [] }` — that's also OK.

- [ ] **Step 5: Commit**

```bash
cd /Users/anton/Dev/Projects/F1predictiongame
git add backend/test/helpers/factories.ts backend/README.md
git commit -m "backend: test factories + README update for predictions + scoring"
```

---

## Done

All 8 tasks complete means:

- 3 new tables (`prediction`, `prediction_pick`, `score`) live + migrated
- 4 pure scorers + dispatcher + DB-aware rescorer
- Rescorer fires automatically from `runTick`
- Routes for submit/edit/view predictions, league leaderboard, per-user score history, admin rescore
- Full test suite green; tsc clean
- README documents new endpoints + scoring scheme

Hand-off ready: the Flutter team can implement the predictions form, the leaderboard screen, and the per-race scoring detail view against this backend without further backend changes. The pre-season questionnaire is the final sub-project.
