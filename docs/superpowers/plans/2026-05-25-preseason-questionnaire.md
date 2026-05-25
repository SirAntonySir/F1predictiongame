# Pre-Season Questionnaire Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the season-long pre-season questionnaire: 8 picks per user per season (6 small categories + 2 ordered lists), locked at the season's first session, auto-scored when standings refresh.

**Architecture:** Three new tables (`preseason_pick`, `preseason_pick_standings_driver`, `preseason_pick_standings_constructor`, `subjective_truth`). The existing `score` table is extended with `kind`, `season_year`, `preseason_category` columns + two partial unique indexes so it holds both session and preseason scores. New leaf module `src/preseason/` (one shared scorer for the 6 single-pick categories + one for the full ordering + a derive layer + a DB-aware rescorer). Two new route files. Tick triggers `rescorePreseasonForSeason` after the standings refresh block.

**Tech Stack:** Same as sub-projects 1-3 — Node 22, TypeScript 5.6, Fastify 5, Drizzle ORM, pg, node-cron, zod, vitest. No new deps.

**Spec:** `docs/superpowers/specs/2026-05-25-preseason-questionnaire-design.md`

**Spec deviation:** The spec describes 7 separate scorer files (one per category). The plan consolidates the 6 single-pick categories (`surprise`, `disappointment`, `dnf`, `poles`, `fastest_lap`, `wdc_wcc`) into one shared `singlePick.ts` scorer driven by a category→rule-string map, since all 6 have identical logic (1 driver match → +4, 1 team match → +4) and differ only in the `rule` version string. `standings.ts` remains separate because its input shape differs. Behavior is identical to 7-file version; the consolidation reduces file proliferation.

---

## File map

All paths under `backend/`.

| Path | Status | Responsibility |
|---|---|---|
| `src/db/schema.ts` | Modify | Add `preseasonPick`, `preseasonPickStandingsDriver`, `preseasonPickStandingsConstructor`, `subjectiveTruth` table defs; add `kind`, `seasonYear`, `preseasonCategory` columns to `score` |
| `src/db/migrations/0004_preseason.sql` | Create | 3 new tables + enum + score column changes |
| `src/db/migrations/meta/_journal.json` | Modify | Register migration 0004 |
| `src/db/migrations/meta/0004_snapshot.json` | Create | Snapshot |
| `src/domain/types.ts` | Modify | Add `PreseasonCategory`, `PreseasonPick`, `PreseasonScoreBreakdown`, `SubjectiveTruth` types |
| `src/preseason/types.ts` | Create | Shared scoring types |
| `src/preseason/singlePick.ts` | Create | Shared scorer for the 6 single-pick categories |
| `src/preseason/standings.ts` | Create | Standings (full ordering) scorer |
| `src/preseason/index.ts` | Create | Dispatcher exports |
| `src/preseason/derive.ts` | Create | Observed-truth derivation from session_result + standings |
| `src/preseason/rescorer.ts` | Create | DB-aware `rescorePreseasonForSeason(year)` |
| `src/repo/preseasonPicks.ts` | Create | Single-pick repo |
| `src/repo/preseasonStandings.ts` | Create | Standings (driver + constructor) repos |
| `src/repo/subjectiveTruth.ts` | Create | Admin truth repo |
| `src/repo/scores.ts` | Modify | Add `upsertPreseasonScore`; rewrite `leagueLeaderboard` SQL to include preseason rows |
| `src/crawler/tick.ts` | Modify | Call `rescorePreseasonForSeason(currentYear)` after standings refresh |
| `src/api/routes/preseason.ts` | Create | `/api/preseason/*`, `/api/seasons/:year/preseason-truth`, `/api/users/me/preseason-scores` |
| `src/api/routes/admin.ts` | Modify | Add `/admin/seasons/:year/subjective-truth` + `/admin/preseason-rescore/:year` |
| `src/index.ts` | Modify | Register `registerPreseasonRoutes` |
| `test/helpers/db.ts` | Modify | Add 3 new tables to TABLES |
| `test/helpers/factories.ts` | Modify | Add `makePreseasonPick`, `makePreseasonStandings`, `setSubjectiveTruth` |
| `test/unit/preseason/singlePick.test.ts` | Create | Pure scorer tests |
| `test/unit/preseason/standings.test.ts` | Create | Standings scorer tests |
| `test/unit/preseason/dispatcher.test.ts` | Create | Dispatcher tests |
| `test/unit/preseason/derive.test.ts` | Create | Observed-truth derivation tests |
| `test/integration/repo_preseasonPicks.test.ts` | Create | Pick repo tests |
| `test/integration/repo_preseasonStandings.test.ts` | Create | Standings repo tests |
| `test/integration/repo_subjectiveTruth.test.ts` | Create | Truth repo tests |
| `test/integration/preseason_rescorer.test.ts` | Create | Rescorer end-to-end |
| `test/integration/crawler_tick_preseason_rescore.test.ts` | Create | Tick→preseason rescore wiring |
| `test/integration/api_preseason.test.ts` | Create | Routes end-to-end |
| `test/integration/api_admin_subjective_truth.test.ts` | Create | Admin endpoint tests |
| `test/integration/api_leaderboard_with_preseason.test.ts` | Create | Regression: leaderboard sums preseason + session rows |
| `README.md` | Modify | Document new endpoints + preseason scoring scheme |

---

### Task 1: Schema + migration 0004

**Files:**
- Modify: `backend/src/db/schema.ts`
- Modify: `backend/src/domain/types.ts`
- Create: `backend/src/db/migrations/0004_preseason.sql`
- Modify: `backend/src/db/migrations/meta/_journal.json`
- Create: `backend/src/db/migrations/meta/0004_snapshot.json`
- Modify: `backend/test/helpers/db.ts`

- [ ] **Step 1: Extend `src/db/schema.ts`**

Append to `backend/src/db/schema.ts`:

```ts
export const preseasonCategory = pgEnum('preseason_category', [
  'surprise', 'disappointment', 'dnf', 'poles', 'fastest_lap', 'wdc_wcc'
])

export const preseasonPick = pgTable('preseason_pick', {
  userId: uuid('user_id').notNull().references(() => user.id, { onDelete: 'cascade' }),
  seasonYear: integer('season_year').notNull().references(() => season.year, { onDelete: 'cascade' }),
  category: preseasonCategory('category').notNull(),
  driverCode: text('driver_code').references(() => driver.code),
  constructorId: text('constructor_id').references(() => constructor.id),
  updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow()
}, (t) => ({
  pk: primaryKey({ columns: [t.userId, t.seasonYear, t.category] }),
  seasonCategoryIdx: index('preseason_pick_season_category_idx').on(t.seasonYear, t.category)
}))

export const preseasonPickStandingsDriver = pgTable('preseason_pick_standings_driver', {
  userId: uuid('user_id').notNull().references(() => user.id, { onDelete: 'cascade' }),
  seasonYear: integer('season_year').notNull().references(() => season.year, { onDelete: 'cascade' }),
  position: integer('position').notNull(),
  driverCode: text('driver_code').notNull().references(() => driver.code)
}, (t) => ({
  pk: primaryKey({ columns: [t.userId, t.seasonYear, t.position] }),
  driverUq: uniqueIndex('preseason_psd_driver_uq').on(t.userId, t.seasonYear, t.driverCode),
  seasonIdx: index('preseason_psd_season_idx').on(t.seasonYear)
}))

export const preseasonPickStandingsConstructor = pgTable('preseason_pick_standings_constructor', {
  userId: uuid('user_id').notNull().references(() => user.id, { onDelete: 'cascade' }),
  seasonYear: integer('season_year').notNull().references(() => season.year, { onDelete: 'cascade' }),
  position: integer('position').notNull(),
  constructorId: text('constructor_id').notNull().references(() => constructor.id)
}, (t) => ({
  pk: primaryKey({ columns: [t.userId, t.seasonYear, t.position] }),
  constructorUq: uniqueIndex('preseason_psc_constructor_uq').on(t.userId, t.seasonYear, t.constructorId),
  seasonIdx: index('preseason_psc_season_idx').on(t.seasonYear)
}))

export const subjectiveTruth = pgTable('subjective_truth', {
  seasonYear: integer('season_year').primaryKey().references(() => season.year, { onDelete: 'cascade' }),
  surpriseDriverCode: text('surprise_driver_code').references(() => driver.code),
  surpriseConstructorId: text('surprise_constructor_id').references(() => constructor.id),
  disappointmentDriverCode: text('disappointment_driver_code').references(() => driver.code),
  disappointmentConstructorId: text('disappointment_constructor_id').references(() => constructor.id),
  setAt: timestamp('set_at', { withTimezone: true }).notNull().defaultNow()
})
```

Then MODIFY the existing `score` table definition. Replace its current definition with:

```ts
export const score = pgTable('score', {
  userId: uuid('user_id').notNull().references(() => user.id, { onDelete: 'cascade' }),
  sessionId: integer('session_id').references(() => session.id, { onDelete: 'cascade' }),
  pointsTotal: integer('points_total').notNull(),
  breakdown: jsonb('breakdown').notNull(),
  computedAt: timestamp('computed_at', { withTimezone: true }).notNull().defaultNow(),
  kind: text('kind').notNull().default('session'),
  seasonYear: integer('season_year').references(() => season.year, { onDelete: 'cascade' }),
  preseasonCategory: text('preseason_category')
}, (t) => ({
  sessionUq: uniqueIndex('score_session_uq').on(t.userId, t.sessionId).where(sql`${t.kind} = 'session'`),
  preseasonUq: uniqueIndex('score_preseason_uq').on(t.userId, t.seasonYear, t.preseasonCategory).where(sql`${t.kind} = 'preseason'`),
  sessionIdx: index('score_session_idx').on(t.sessionId),
  userIdx: index('score_user_idx').on(t.userId)
}))
```

Note: `sessionId` is now nullable. The previous primary-key constraint is dropped in the migration SQL. The two `uniqueIndex` calls use Drizzle's `.where()` for partial indexes (Drizzle 0.36+ supports this).

If Drizzle 0.36's TypeScript types don't accept `.where()` on `uniqueIndex`, fall back to declaring the indexes as plain `index()` in the schema (since they're enforced by the migration SQL anyway — the schema TS is mainly for type inference). The runtime constraint comes from migration SQL.

- [ ] **Step 2: Extend `src/domain/types.ts`**

Append:

```ts
export type PreseasonCategory =
  | 'surprise' | 'disappointment' | 'dnf' | 'poles' | 'fastest_lap' | 'wdc_wcc'

export type PreseasonPick = {
  userId: string
  seasonYear: number
  category: PreseasonCategory
  driverCode: string | null
  constructorId: string | null
  updatedAt: Date
}

export type PreseasonStandingsPickRow = {
  userId: string
  seasonYear: number
  position: number
  entityId: string  // driverCode or constructorId
}

export type SubjectiveTruth = {
  seasonYear: number
  surpriseDriverCode: string | null
  surpriseConstructorId: string | null
  disappointmentDriverCode: string | null
  disappointmentConstructorId: string | null
  setAt: Date
}

export type PreseasonScoreBreakdown = {
  driver?: { picked: string | null; truth: string | null; correct: boolean; points: number }
  team?:   { picked: string | null; truth: string | null; correct: boolean; points: number }
  perPosition?: { position: number; picked: string; truth: string | null; correct: boolean; points: number }[]
  pointsTotal: number
  rule: string
}
```

- [ ] **Step 3: Create migration `0004_preseason.sql`**

Create `backend/src/db/migrations/0004_preseason.sql`:

```sql
CREATE TYPE "public"."preseason_category" AS ENUM('surprise', 'disappointment', 'dnf', 'poles', 'fastest_lap', 'wdc_wcc');--> statement-breakpoint
CREATE TABLE "preseason_pick" (
	"user_id" uuid NOT NULL,
	"season_year" integer NOT NULL,
	"category" "preseason_category" NOT NULL,
	"driver_code" text,
	"constructor_id" text,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "preseason_pick_pk" PRIMARY KEY ("user_id", "season_year", "category"),
	CONSTRAINT "preseason_pick_user_fk" FOREIGN KEY ("user_id") REFERENCES "user"("id") ON DELETE CASCADE,
	CONSTRAINT "preseason_pick_season_fk" FOREIGN KEY ("season_year") REFERENCES "season"("year") ON DELETE CASCADE,
	CONSTRAINT "preseason_pick_driver_fk" FOREIGN KEY ("driver_code") REFERENCES "driver"("code"),
	CONSTRAINT "preseason_pick_constructor_fk" FOREIGN KEY ("constructor_id") REFERENCES "constructor"("id")
);
--> statement-breakpoint
CREATE INDEX "preseason_pick_season_category_idx" ON "preseason_pick" ("season_year", "category");--> statement-breakpoint
CREATE TABLE "preseason_pick_standings_driver" (
	"user_id" uuid NOT NULL,
	"season_year" integer NOT NULL,
	"position" integer NOT NULL,
	"driver_code" text NOT NULL,
	CONSTRAINT "preseason_psd_pk" PRIMARY KEY ("user_id", "season_year", "position"),
	CONSTRAINT "preseason_psd_user_fk" FOREIGN KEY ("user_id") REFERENCES "user"("id") ON DELETE CASCADE,
	CONSTRAINT "preseason_psd_season_fk" FOREIGN KEY ("season_year") REFERENCES "season"("year") ON DELETE CASCADE,
	CONSTRAINT "preseason_psd_driver_fk" FOREIGN KEY ("driver_code") REFERENCES "driver"("code")
);
--> statement-breakpoint
CREATE UNIQUE INDEX "preseason_psd_driver_uq" ON "preseason_pick_standings_driver" ("user_id", "season_year", "driver_code");--> statement-breakpoint
CREATE INDEX "preseason_psd_season_idx" ON "preseason_pick_standings_driver" ("season_year");--> statement-breakpoint
CREATE TABLE "preseason_pick_standings_constructor" (
	"user_id" uuid NOT NULL,
	"season_year" integer NOT NULL,
	"position" integer NOT NULL,
	"constructor_id" text NOT NULL,
	CONSTRAINT "preseason_psc_pk" PRIMARY KEY ("user_id", "season_year", "position"),
	CONSTRAINT "preseason_psc_user_fk" FOREIGN KEY ("user_id") REFERENCES "user"("id") ON DELETE CASCADE,
	CONSTRAINT "preseason_psc_season_fk" FOREIGN KEY ("season_year") REFERENCES "season"("year") ON DELETE CASCADE,
	CONSTRAINT "preseason_psc_constructor_fk" FOREIGN KEY ("constructor_id") REFERENCES "constructor"("id")
);
--> statement-breakpoint
CREATE UNIQUE INDEX "preseason_psc_constructor_uq" ON "preseason_pick_standings_constructor" ("user_id", "season_year", "constructor_id");--> statement-breakpoint
CREATE INDEX "preseason_psc_season_idx" ON "preseason_pick_standings_constructor" ("season_year");--> statement-breakpoint
CREATE TABLE "subjective_truth" (
	"season_year" integer PRIMARY KEY NOT NULL,
	"surprise_driver_code" text,
	"surprise_constructor_id" text,
	"disappointment_driver_code" text,
	"disappointment_constructor_id" text,
	"set_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "subjective_truth_season_fk" FOREIGN KEY ("season_year") REFERENCES "season"("year") ON DELETE CASCADE,
	CONSTRAINT "subjective_truth_sdriver_fk" FOREIGN KEY ("surprise_driver_code") REFERENCES "driver"("code"),
	CONSTRAINT "subjective_truth_sctor_fk" FOREIGN KEY ("surprise_constructor_id") REFERENCES "constructor"("id"),
	CONSTRAINT "subjective_truth_ddriver_fk" FOREIGN KEY ("disappointment_driver_code") REFERENCES "driver"("code"),
	CONSTRAINT "subjective_truth_dctor_fk" FOREIGN KEY ("disappointment_constructor_id") REFERENCES "constructor"("id")
);
--> statement-breakpoint
ALTER TABLE "score" ADD COLUMN "kind" text NOT NULL DEFAULT 'session';--> statement-breakpoint
ALTER TABLE "score" ADD COLUMN "season_year" integer;--> statement-breakpoint
ALTER TABLE "score" ADD COLUMN "preseason_category" text;--> statement-breakpoint
ALTER TABLE "score" ADD CONSTRAINT "score_seasonyear_fk" FOREIGN KEY ("season_year") REFERENCES "season"("year") ON DELETE CASCADE;--> statement-breakpoint
ALTER TABLE "score" ALTER COLUMN "session_id" DROP NOT NULL;--> statement-breakpoint
ALTER TABLE "score" DROP CONSTRAINT "score_pk";--> statement-breakpoint
CREATE UNIQUE INDEX "score_session_uq" ON "score" ("user_id", "session_id") WHERE kind = 'session';--> statement-breakpoint
CREATE UNIQUE INDEX "score_preseason_uq" ON "score" ("user_id", "season_year", "preseason_category") WHERE kind = 'preseason';
```

- [ ] **Step 4: Register migration in `_journal.json`**

Read current `backend/src/db/migrations/meta/_journal.json`, append:

```json
{
  "idx": 4,
  "version": "7",
  "when": <CURRENT_UNIX_MS>,
  "tag": "0004_preseason",
  "breakpoints": true
}
```

Use the current ms timestamp for `when`. Match `version` to prior entries.

- [ ] **Step 5: Create `0004_snapshot.json`**

Easiest path (mirroring sub-projects 2-3): run `npm run db:generate` after step 6 applies the migration, then rename the auto-generated tag if needed and hand-edit any long FK names down to the short names declared in the migration SQL.

The long-name pattern that needs fixing:
- `preseason_pick_user_id_user_id_fk` → `preseason_pick_user_fk`
- `preseason_pick_season_year_season_year_fk` → `preseason_pick_season_fk`
- `preseason_pick_driver_code_driver_code_fk` → `preseason_pick_driver_fk`
- `preseason_pick_constructor_id_constructor_id_fk` → `preseason_pick_constructor_fk`
- (and similar for the two standings tables and subjective_truth)
- `score_season_year_season_year_fk` → `score_seasonyear_fk`

Verify after editing:
```bash
grep -E '_id_(user|session|league|driver|constructor|season)_(id|year|code)_fk' backend/src/db/migrations/meta/0004_snapshot.json
```
Should print nothing.

- [ ] **Step 6: Extend `test/helpers/db.ts`**

Update TABLES (child-first):

```ts
const TABLES = [
  'subjective_truth',
  'preseason_pick_standings_constructor',
  'preseason_pick_standings_driver',
  'preseason_pick',
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
Expected: lists 18 tables including the 4 new ones.

```bash
docker exec backend-db-1 psql -U f1pg -d f1pg -c "\d score"
```
Expected: 8 columns including `kind`, `session_year`, `preseason_category`. Two unique indexes with `WHERE` clauses. `session_id` nullable.

- [ ] **Step 8: Verify full test suite still passes (no regressions yet)**

```bash
cd /Users/anton/Dev/Projects/F1predictiongame/backend
set -a && source .env && set +a
npm test
npx tsc --noEmit
```

Expected: all 189 prior tests still pass. tsc clean.

**If `upsertScore` (in `repo/scores.ts`) breaks because the old PK `(user_id, session_id)` no longer exists**, the test failure should show as an ON CONFLICT error. Fix: update `upsertScore` to also include the partial-index `where` clause. This is a small fix that belongs here since the migration broke it. Apply this surgical change to `backend/src/repo/scores.ts`:

```ts
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
      targetWhere: sql`kind = 'session'`,
      set: { pointsTotal, breakdown, computedAt: sql`now()` }
    })
}
```

If `targetWhere` isn't supported in your Drizzle version, fall back to raw SQL:

```ts
export async function upsertScore(
  userId: string,
  sessionId: number,
  pointsTotal: number,
  breakdown: ScoreBreakdown
): Promise<void> {
  const db = getDb()
  await db.execute(sql`
    INSERT INTO ${score} ("user_id", "session_id", "points_total", "breakdown", "kind")
    VALUES (${userId}::uuid, ${sessionId}, ${pointsTotal}, ${JSON.stringify(breakdown)}::jsonb, 'session')
    ON CONFLICT ("user_id", "session_id") WHERE kind = 'session'
    DO UPDATE SET points_total = EXCLUDED.points_total,
                  breakdown    = EXCLUDED.breakdown,
                  computed_at  = now()
  `)
}
```

Verify all tests pass after the fix.

- [ ] **Step 9: Commit**

```bash
cd /Users/anton/Dev/Projects/F1predictiongame
git add backend/src/db/schema.ts backend/src/db/migrations/0004_preseason.sql backend/src/db/migrations/meta/_journal.json backend/src/db/migrations/meta/0004_snapshot.json backend/src/domain/types.ts backend/test/helpers/db.ts backend/src/repo/scores.ts
git commit -m "backend: schema + migration for preseason questionnaire"
```

---

### Task 2: Scoring engine (singlePick + standings + dispatcher)

**Files:**
- Create: `backend/src/preseason/types.ts`
- Create: `backend/src/preseason/singlePick.ts`
- Create: `backend/src/preseason/standings.ts`
- Create: `backend/src/preseason/index.ts`
- Create: `backend/test/unit/preseason/singlePick.test.ts`
- Create: `backend/test/unit/preseason/standings.test.ts`
- Create: `backend/test/unit/preseason/dispatcher.test.ts`

Pure functions, no DB. TDD.

- [ ] **Step 1: Create `src/preseason/types.ts`**

```ts
import type { PreseasonCategory, PreseasonScoreBreakdown } from '../domain/types.js'

export type { PreseasonCategory, PreseasonScoreBreakdown }

export type PreseasonPickInput = {
  driverCode: string | null
  constructorId: string | null
}

export type StandingsEntry = {
  position: number
  entityId: string  // driver_code or constructor_id
}
```

- [ ] **Step 2: Write `singlePick.test.ts`**

Create `backend/test/unit/preseason/singlePick.test.ts`:

```ts
import { describe, it, expect } from 'vitest'
import { scoreSinglePick } from '../../../src/preseason/singlePick.js'

describe('scoreSinglePick', () => {
  it('both match: driver +4, team +4 = 8', () => {
    const b = scoreSinglePick('surprise',
      { driverCode: 'VER', constructorId: 'red_bull' },
      { driverCode: 'VER', constructorId: 'red_bull' })
    expect(b.driver).toEqual({ picked: 'VER', truth: 'VER', correct: true, points: 4 })
    expect(b.team).toEqual({ picked: 'red_bull', truth: 'red_bull', correct: true, points: 4 })
    expect(b.pointsTotal).toBe(8)
    expect(b.rule).toBe('preseason-surprise-v1')
  })

  it('driver only match: 4', () => {
    const b = scoreSinglePick('dnf',
      { driverCode: 'VER', constructorId: 'red_bull' },
      { driverCode: 'VER', constructorId: 'mercedes' })
    expect(b.driver?.points).toBe(4)
    expect(b.team?.points).toBe(0)
    expect(b.pointsTotal).toBe(4)
    expect(b.rule).toBe('preseason-dnf-v1')
  })

  it('team only match: 4', () => {
    const b = scoreSinglePick('poles',
      { driverCode: 'HAM', constructorId: 'red_bull' },
      { driverCode: 'VER', constructorId: 'red_bull' })
    expect(b.driver?.points).toBe(0)
    expect(b.team?.points).toBe(4)
    expect(b.pointsTotal).toBe(4)
  })

  it('neither matches: 0', () => {
    const b = scoreSinglePick('fastest_lap',
      { driverCode: 'HAM', constructorId: 'mercedes' },
      { driverCode: 'VER', constructorId: 'red_bull' })
    expect(b.pointsTotal).toBe(0)
  })

  it('null truth (e.g. subjective not set yet): 0', () => {
    const b = scoreSinglePick('surprise',
      { driverCode: 'VER', constructorId: 'red_bull' },
      { driverCode: null, constructorId: null })
    expect(b.pointsTotal).toBe(0)
    expect(b.driver?.correct).toBe(false)
    expect(b.team?.correct).toBe(false)
  })

  it('null pick (user didn\'t pick): 0', () => {
    const b = scoreSinglePick('wdc_wcc',
      { driverCode: null, constructorId: null },
      { driverCode: 'VER', constructorId: 'red_bull' })
    expect(b.pointsTotal).toBe(0)
  })

  it('partial pick (driver only) with full truth: scores the matching half', () => {
    const b = scoreSinglePick('wdc_wcc',
      { driverCode: 'VER', constructorId: null },
      { driverCode: 'VER', constructorId: 'red_bull' })
    expect(b.driver?.points).toBe(4)
    expect(b.team?.points).toBe(0)
    expect(b.pointsTotal).toBe(4)
  })

  it('uses correct rule string per category', () => {
    expect(scoreSinglePick('surprise',       { driverCode: null, constructorId: null }, { driverCode: null, constructorId: null }).rule).toBe('preseason-surprise-v1')
    expect(scoreSinglePick('disappointment', { driverCode: null, constructorId: null }, { driverCode: null, constructorId: null }).rule).toBe('preseason-disappointment-v1')
    expect(scoreSinglePick('dnf',            { driverCode: null, constructorId: null }, { driverCode: null, constructorId: null }).rule).toBe('preseason-dnf-v1')
    expect(scoreSinglePick('poles',          { driverCode: null, constructorId: null }, { driverCode: null, constructorId: null }).rule).toBe('preseason-poles-v1')
    expect(scoreSinglePick('fastest_lap',    { driverCode: null, constructorId: null }, { driverCode: null, constructorId: null }).rule).toBe('preseason-fastest-lap-v1')
    expect(scoreSinglePick('wdc_wcc',        { driverCode: null, constructorId: null }, { driverCode: null, constructorId: null }).rule).toBe('preseason-wdc-wcc-v1')
  })
})
```

- [ ] **Step 3: Verify failing**

```bash
cd /Users/anton/Dev/Projects/F1predictiongame/backend
set -a && source .env && set +a
npx vitest run test/unit/preseason/singlePick.test.ts
```
Expected: FAIL — module not found.

- [ ] **Step 4: Implement `src/preseason/singlePick.ts`**

```ts
import type { PreseasonCategory, PreseasonScoreBreakdown, PreseasonPickInput } from './types.js'

const POINTS_PER_MATCH = 4

const RULES: Record<PreseasonCategory, string> = {
  surprise:        'preseason-surprise-v1',
  disappointment:  'preseason-disappointment-v1',
  dnf:             'preseason-dnf-v1',
  poles:           'preseason-poles-v1',
  fastest_lap:     'preseason-fastest-lap-v1',
  wdc_wcc:         'preseason-wdc-wcc-v1'
}

export function scoreSinglePick(
  category: PreseasonCategory,
  pick: PreseasonPickInput,
  truth: PreseasonPickInput
): PreseasonScoreBreakdown {
  const driverCorrect = pick.driverCode !== null && truth.driverCode !== null && pick.driverCode === truth.driverCode
  const teamCorrect   = pick.constructorId !== null && truth.constructorId !== null && pick.constructorId === truth.constructorId

  const driverPoints = driverCorrect ? POINTS_PER_MATCH : 0
  const teamPoints   = teamCorrect   ? POINTS_PER_MATCH : 0

  return {
    driver: { picked: pick.driverCode,    truth: truth.driverCode,    correct: driverCorrect, points: driverPoints },
    team:   { picked: pick.constructorId, truth: truth.constructorId, correct: teamCorrect,   points: teamPoints },
    pointsTotal: driverPoints + teamPoints,
    rule: RULES[category]
  }
}
```

- [ ] **Step 5: Verify passing**

```bash
npx vitest run test/unit/preseason/singlePick.test.ts
```
Expected: PASS (8 tests).

- [ ] **Step 6: Write `standings.test.ts`**

```ts
import { describe, it, expect } from 'vitest'
import { scoreStandings } from '../../../src/preseason/standings.js'

describe('scoreStandings', () => {
  const truthDrivers = [
    { position: 1, entityId: 'VER' },
    { position: 2, entityId: 'HAM' },
    { position: 3, entityId: 'NOR' },
    { position: 4, entityId: 'PIA' },
    { position: 5, entityId: 'RUS' }
  ]
  const truthTeams = [
    { position: 1, entityId: 'red_bull' },
    { position: 2, entityId: 'mercedes' },
    { position: 3, entityId: 'mclaren' }
  ]

  it('all 5 drivers correct + all 3 teams correct = 5*3 + 3*4 = 27', () => {
    const b = scoreStandings(
      [
        { position: 1, entityId: 'VER' },
        { position: 2, entityId: 'HAM' },
        { position: 3, entityId: 'NOR' },
        { position: 4, entityId: 'PIA' },
        { position: 5, entityId: 'RUS' }
      ],
      [
        { position: 1, entityId: 'red_bull' },
        { position: 2, entityId: 'mercedes' },
        { position: 3, entityId: 'mclaren' }
      ],
      truthDrivers, truthTeams
    )
    expect(b.pointsTotal).toBe(27)
    expect(b.rule).toBe('preseason-standings-v1')
    expect(b.perPosition).toHaveLength(8)
  })

  it('drivers all wrong + teams half correct', () => {
    const b = scoreStandings(
      [
        { position: 1, entityId: 'PIA' },
        { position: 2, entityId: 'PIA' },
        { position: 3, entityId: 'PIA' },
        { position: 4, entityId: 'PIA' },
        { position: 5, entityId: 'PIA' }
      ],
      [
        { position: 1, entityId: 'red_bull' },     // correct
        { position: 2, entityId: 'mclaren' },      // wrong
        { position: 3, entityId: 'mercedes' }      // wrong
      ],
      truthDrivers, truthTeams
    )
    // 0 driver points; 1 team correct = 4
    expect(b.pointsTotal).toBe(4)
  })

  it('shorter picks than truth: only scored positions count', () => {
    const b = scoreStandings(
      [{ position: 1, entityId: 'VER' }],
      [{ position: 1, entityId: 'red_bull' }],
      truthDrivers, truthTeams
    )
    expect(b.pointsTotal).toBe(3 + 4)  // 1 driver correct + 1 team correct
  })

  it('positions in pick missing from truth score 0 (but track)', () => {
    const b = scoreStandings(
      [{ position: 99, entityId: 'VER' }],
      [{ position: 99, entityId: 'red_bull' }],
      truthDrivers, truthTeams
    )
    expect(b.pointsTotal).toBe(0)
  })

  it('empty picks: 0', () => {
    const b = scoreStandings([], [], truthDrivers, truthTeams)
    expect(b.pointsTotal).toBe(0)
    expect(b.perPosition).toEqual([])
  })

  it('empty truth: 0 (e.g. season hasn\'t finished)', () => {
    const b = scoreStandings(
      [{ position: 1, entityId: 'VER' }],
      [{ position: 1, entityId: 'red_bull' }],
      [], []
    )
    expect(b.pointsTotal).toBe(0)
  })
})
```

- [ ] **Step 7: Verify failing**

```bash
npx vitest run test/unit/preseason/standings.test.ts
```
Expected: FAIL.

- [ ] **Step 8: Implement `src/preseason/standings.ts`**

```ts
import type { PreseasonScoreBreakdown, StandingsEntry } from './types.js'

const DRIVER_POINTS_PER_CORRECT = 3
const TEAM_POINTS_PER_CORRECT = 4
const RULE = 'preseason-standings-v1'

export function scoreStandings(
  driverPicks: StandingsEntry[],
  constructorPicks: StandingsEntry[],
  driverTruth: StandingsEntry[],
  constructorTruth: StandingsEntry[]
): PreseasonScoreBreakdown {
  const driverTruthByPos = new Map(driverTruth.map((e) => [e.position, e.entityId]))
  const teamTruthByPos = new Map(constructorTruth.map((e) => [e.position, e.entityId]))

  const perPosition: NonNullable<PreseasonScoreBreakdown['perPosition']> = []
  let total = 0

  for (const p of driverPicks) {
    const truth = driverTruthByPos.get(p.position) ?? null
    const correct = truth !== null && truth === p.entityId
    const points = correct ? DRIVER_POINTS_PER_CORRECT : 0
    perPosition.push({ position: p.position, picked: p.entityId, truth, correct, points })
    total += points
  }
  for (const p of constructorPicks) {
    const truth = teamTruthByPos.get(p.position) ?? null
    const correct = truth !== null && truth === p.entityId
    const points = correct ? TEAM_POINTS_PER_CORRECT : 0
    // distinguish driver vs team rows by position+entityId nature; the consumer separates by entity-id format
    perPosition.push({ position: p.position, picked: p.entityId, truth, correct, points })
    total += points
  }

  return { perPosition, pointsTotal: total, rule: RULE }
}
```

- [ ] **Step 9: Verify passing**

```bash
npx vitest run test/unit/preseason/standings.test.ts
```
Expected: PASS (6 tests).

- [ ] **Step 10: Write `dispatcher.test.ts`**

```ts
import { describe, it, expect } from 'vitest'
import { scorePreseasonCategory } from '../../../src/preseason/index.js'

describe('scorePreseasonCategory dispatcher', () => {
  it('dispatches to scoreSinglePick for surprise', () => {
    const b = scorePreseasonCategory('surprise',
      { driverCode: 'VER', constructorId: 'red_bull' },
      { driverCode: 'VER', constructorId: 'red_bull' })
    expect(b.rule).toBe('preseason-surprise-v1')
  })

  it('dispatches for each of the 6 single-pick categories', () => {
    const cats = ['surprise', 'disappointment', 'dnf', 'poles', 'fastest_lap', 'wdc_wcc'] as const
    for (const c of cats) {
      const b = scorePreseasonCategory(c,
        { driverCode: null, constructorId: null },
        { driverCode: null, constructorId: null })
      expect(b.rule).toContain('preseason-')
    }
  })

  it('throws on unknown category', () => {
    expect(() => scorePreseasonCategory('not_a_real_cat' as any,
      { driverCode: null, constructorId: null },
      { driverCode: null, constructorId: null })).toThrow(/unknown/i)
  })
})
```

- [ ] **Step 11: Verify failing**

```bash
npx vitest run test/unit/preseason/dispatcher.test.ts
```
Expected: FAIL.

- [ ] **Step 12: Implement `src/preseason/index.ts`**

```ts
import type { PreseasonCategory, PreseasonPickInput } from './types.js'
import { scoreSinglePick } from './singlePick.js'
import { scoreStandings } from './standings.js'
import type { PreseasonScoreBreakdown } from './types.js'

export type { PreseasonCategory, PreseasonPickInput, PreseasonScoreBreakdown } from './types.js'
export { scoreSinglePick, scoreStandings }

const VALID_CATEGORIES: ReadonlyArray<PreseasonCategory> = [
  'surprise', 'disappointment', 'dnf', 'poles', 'fastest_lap', 'wdc_wcc'
]

export function scorePreseasonCategory(
  category: PreseasonCategory,
  pick: PreseasonPickInput,
  truth: PreseasonPickInput
): PreseasonScoreBreakdown {
  if (!VALID_CATEGORIES.includes(category)) {
    throw new Error(`Unknown preseason category: ${category}`)
  }
  return scoreSinglePick(category, pick, truth)
}
```

- [ ] **Step 13: Verify passing + full suite**

```bash
npx vitest run test/unit/preseason/
npm test
npx tsc --noEmit
```
Expected: 17 new unit tests pass (8 + 6 + 3); full suite green; tsc clean.

- [ ] **Step 14: Commit**

```bash
cd /Users/anton/Dev/Projects/F1predictiongame
git add backend/src/preseason/types.ts backend/src/preseason/singlePick.ts backend/src/preseason/standings.ts backend/src/preseason/index.ts backend/test/unit/preseason/
git commit -m "backend: preseason scoring engine (singlePick + standings + dispatcher)"
```

---

### Task 3: Observed-truth derivation

**Files:**
- Create: `backend/src/preseason/derive.ts`
- Create: `backend/test/unit/preseason/derive.test.ts`

Pure functions that consume crawled data and return the (driver, team) pair each rule needs.

- [ ] **Step 1: Write `derive.test.ts`**

```ts
import { describe, it, expect } from 'vitest'
import {
  deriveMostDnfs,
  derivePolesitter,
  deriveMostFastestLaps,
  deriveWdcWcc,
  deriveFinalStandings
} from '../../../src/preseason/derive.js'
import type { SessionResultRow, DriverStanding, ConstructorStanding } from '../../../src/domain/types.js'
import type { StoredSession } from '../../../src/repo/sessions.js'

function r(sessionId: number, position: number, code: string, team: string, opts: Partial<SessionResultRow> = {}): SessionResultRow {
  return {
    sessionId, position, driverCode: code, driverName: code,
    constructorId: team, constructorName: team,
    raceTime: null, status: 'Finished', points: null,
    fastestLap: null, fastestLapTime: null, fastestLapSpeed: null,
    q1: null, q2: null, q3: null,
    ...opts
  }
}

function s(id: number, type: StoredSession['type']): StoredSession {
  return {
    id, eventId: 1, type,
    scheduledStart: new Date(2026, 0, 1),
    scheduledEnd: new Date(2026, 0, 1, 2),
    status: 'finished'
  } as StoredSession
}

describe('deriveMostDnfs', () => {
  it('counts DNF statuses across all race + sprint sessions', () => {
    const sessions = [s(1, 'race'), s(2, 'race'), s(3, 'sprint'), s(4, 'qualifying')]
    const results = [
      r(1, 1, 'VER', 'red_bull'),
      r(1, 20, 'HAM', 'mercedes', { status: 'Retired' }),
      r(1, 19, 'RUS', 'mercedes', { status: 'Engine' }),
      r(2, 18, 'HAM', 'mercedes', { status: 'Collision' }),
      r(3, 18, 'HAM', 'mercedes', { status: 'Accident' }),  // sprint counts too
      r(4, 20, 'HAM', 'mercedes', { status: 'Engine' })     // qualifying SKIPPED
    ]
    const result = deriveMostDnfs(results, sessions)
    expect(result.driverCode).toBe('HAM')  // 3 DNFs (race1, race2, sprint3) — quali skipped
    expect(result.constructorId).toBe('mercedes')  // 4 (HAM x3 + RUS x1)
  })
})

describe('derivePolesitter', () => {
  it('returns driver with most position-1 in qualifying sessions', () => {
    const sessions = [s(1, 'qualifying'), s(2, 'qualifying'), s(3, 'sprint_quali'), s(4, 'race')]
    const results = [
      r(1, 1, 'VER', 'red_bull'),
      r(2, 1, 'VER', 'red_bull'),
      r(3, 1, 'HAM', 'mercedes'),  // sprint_quali — excluded from main poles
      r(4, 1, 'NOR', 'mclaren')    // race — excluded
    ]
    const result = derivePolesitter(results, sessions)
    expect(result.driverCode).toBe('VER')
    expect(result.constructorId).toBe('red_bull')
  })
})

describe('deriveMostFastestLaps', () => {
  it('counts fastestLap = "1" in race sessions only', () => {
    const sessions = [s(1, 'race'), s(2, 'race'), s(3, 'sprint')]
    const results = [
      r(1, 1, 'VER', 'red_bull', { fastestLap: '1' }),
      r(1, 2, 'HAM', 'mercedes', { fastestLap: '2' }),
      r(2, 5, 'VER', 'red_bull', { fastestLap: '1' }),
      r(3, 1, 'HAM', 'mercedes', { fastestLap: '1' })  // sprint excluded
    ]
    const result = deriveMostFastestLaps(results, sessions)
    expect(result.driverCode).toBe('VER')
  })
})

describe('deriveWdcWcc', () => {
  it('picks position=1 from each standings table', () => {
    const drivers: DriverStanding[] = [
      { seasonYear: 2026, driverCode: 'VER', position: 1, points: 400, wins: 10, constructorId: 'red_bull' },
      { seasonYear: 2026, driverCode: 'HAM', position: 2, points: 300, wins: 4, constructorId: 'mercedes' }
    ]
    const constructors: ConstructorStanding[] = [
      { seasonYear: 2026, constructorId: 'mclaren',  position: 1, points: 700, wins: 8 },
      { seasonYear: 2026, constructorId: 'red_bull', position: 2, points: 600, wins: 10 }
    ]
    const result = deriveWdcWcc(drivers, constructors)
    expect(result.driverCode).toBe('VER')
    expect(result.constructorId).toBe('mclaren')
  })
})

describe('deriveFinalStandings', () => {
  it('returns ordered lists', () => {
    const drivers: DriverStanding[] = [
      { seasonYear: 2026, driverCode: 'HAM', position: 2, points: 300, wins: 4, constructorId: 'mercedes' },
      { seasonYear: 2026, driverCode: 'VER', position: 1, points: 400, wins: 10, constructorId: 'red_bull' }
    ]
    const constructors: ConstructorStanding[] = [
      { seasonYear: 2026, constructorId: 'red_bull', position: 2, points: 600, wins: 10 },
      { seasonYear: 2026, constructorId: 'mclaren',  position: 1, points: 700, wins: 8 }
    ]
    const r = deriveFinalStandings(drivers, constructors)
    expect(r.drivers).toEqual([
      { position: 1, entityId: 'VER' },
      { position: 2, entityId: 'HAM' }
    ])
    expect(r.constructors).toEqual([
      { position: 1, entityId: 'mclaren' },
      { position: 2, entityId: 'red_bull' }
    ])
  })
})
```

- [ ] **Step 2: Verify failing**

```bash
npx vitest run test/unit/preseason/derive.test.ts
```
Expected: FAIL.

- [ ] **Step 3: Implement `src/preseason/derive.ts`**

```ts
import type { SessionResultRow, DriverStanding, ConstructorStanding } from '../domain/types.js'
import type { StoredSession } from '../repo/sessions.js'
import type { StandingsEntry } from './types.js'

const DNF_STATUSES = new Set([
  'Retired', 'Accident', 'Engine', 'Collision', 'Mechanical',
  'Spun off', 'Withdrew', 'Did not start', 'Disqualified'
])

type DerivedPair = { driverCode: string | null; constructorId: string | null }

function topCount<K extends string>(counts: Map<K, number>): K | null {
  let best: K | null = null
  let bestCount = 0
  for (const [k, c] of counts) {
    if (c > bestCount) { best = k; bestCount = c }
  }
  return best
}

export function deriveMostDnfs(results: SessionResultRow[], sessions: StoredSession[]): DerivedPair {
  const eligibleSessionIds = new Set(
    sessions.filter((s) => s.type === 'race' || s.type === 'sprint').map((s) => s.id)
  )
  const driverCounts = new Map<string, number>()
  const teamCounts = new Map<string, number>()
  for (const r of results) {
    if (!eligibleSessionIds.has(r.sessionId)) continue
    if (!r.status || !DNF_STATUSES.has(r.status)) continue
    driverCounts.set(r.driverCode, (driverCounts.get(r.driverCode) ?? 0) + 1)
    teamCounts.set(r.constructorId, (teamCounts.get(r.constructorId) ?? 0) + 1)
  }
  return { driverCode: topCount(driverCounts), constructorId: topCount(teamCounts) }
}

export function derivePolesitter(results: SessionResultRow[], sessions: StoredSession[]): DerivedPair {
  const qualifyingIds = new Set(sessions.filter((s) => s.type === 'qualifying').map((s) => s.id))
  const driverCounts = new Map<string, number>()
  const teamCounts = new Map<string, number>()
  for (const r of results) {
    if (!qualifyingIds.has(r.sessionId)) continue
    if (r.position !== 1) continue
    driverCounts.set(r.driverCode, (driverCounts.get(r.driverCode) ?? 0) + 1)
    teamCounts.set(r.constructorId, (teamCounts.get(r.constructorId) ?? 0) + 1)
  }
  return { driverCode: topCount(driverCounts), constructorId: topCount(teamCounts) }
}

export function deriveMostFastestLaps(results: SessionResultRow[], sessions: StoredSession[]): DerivedPair {
  const raceIds = new Set(sessions.filter((s) => s.type === 'race').map((s) => s.id))
  const driverCounts = new Map<string, number>()
  const teamCounts = new Map<string, number>()
  for (const r of results) {
    if (!raceIds.has(r.sessionId)) continue
    if (r.fastestLap !== '1') continue
    driverCounts.set(r.driverCode, (driverCounts.get(r.driverCode) ?? 0) + 1)
    teamCounts.set(r.constructorId, (teamCounts.get(r.constructorId) ?? 0) + 1)
  }
  return { driverCode: topCount(driverCounts), constructorId: topCount(teamCounts) }
}

export function deriveWdcWcc(drivers: DriverStanding[], constructors: ConstructorStanding[]): DerivedPair {
  const wdc = drivers.find((d) => d.position === 1) ?? null
  const wcc = constructors.find((c) => c.position === 1) ?? null
  return {
    driverCode: wdc?.driverCode ?? null,
    constructorId: wcc?.constructorId ?? null
  }
}

export function deriveFinalStandings(drivers: DriverStanding[], constructors: ConstructorStanding[]): {
  drivers: StandingsEntry[]
  constructors: StandingsEntry[]
} {
  return {
    drivers: drivers
      .slice()
      .sort((a, b) => a.position - b.position)
      .map((d) => ({ position: d.position, entityId: d.driverCode })),
    constructors: constructors
      .slice()
      .sort((a, b) => a.position - b.position)
      .map((c) => ({ position: c.position, entityId: c.constructorId }))
  }
}
```

- [ ] **Step 4: Verify passing**

```bash
npx vitest run test/unit/preseason/derive.test.ts
```
Expected: PASS (5 tests).

- [ ] **Step 5: Run full suite**

```bash
npm test
npx tsc --noEmit
```
Expected: green; tsc clean.

- [ ] **Step 6: Commit**

```bash
cd /Users/anton/Dev/Projects/F1predictiongame
git add backend/src/preseason/derive.ts backend/test/unit/preseason/derive.test.ts
git commit -m "backend: preseason observed-truth derivation (DNFs, poles, FLs, WDC/WCC, standings)"
```

---

### Task 4: Preseason repos

**Files:**
- Create: `backend/src/repo/preseasonPicks.ts`
- Create: `backend/src/repo/preseasonStandings.ts`
- Create: `backend/src/repo/subjectiveTruth.ts`
- Create: `backend/test/integration/repo_preseasonPicks.test.ts`
- Create: `backend/test/integration/repo_preseasonStandings.test.ts`
- Create: `backend/test/integration/repo_subjectiveTruth.test.ts`

- [ ] **Step 1: Implement `src/repo/preseasonPicks.ts`**

```ts
import { and, eq, sql } from 'drizzle-orm'
import { getDb } from '../db/client.js'
import { preseasonPick } from '../db/schema.js'
import type { PreseasonCategory, PreseasonPick } from '../domain/types.js'

function toPick(row: typeof preseasonPick.$inferSelect): PreseasonPick {
  return {
    userId: row.userId,
    seasonYear: row.seasonYear,
    category: row.category,
    driverCode: row.driverCode,
    constructorId: row.constructorId,
    updatedAt: row.updatedAt
  }
}

export async function upsertPick(
  userId: string,
  seasonYear: number,
  category: PreseasonCategory,
  values: { driverCode: string | null; constructorId: string | null }
): Promise<PreseasonPick> {
  const db = getDb()
  const [row] = await db.insert(preseasonPick)
    .values({ userId, seasonYear, category, driverCode: values.driverCode, constructorId: values.constructorId })
    .onConflictDoUpdate({
      target: [preseasonPick.userId, preseasonPick.seasonYear, preseasonPick.category],
      set: {
        driverCode: values.driverCode,
        constructorId: values.constructorId,
        updatedAt: sql`now()`
      }
    })
    .returning()
  return toPick(row!)
}

export async function getPick(userId: string, seasonYear: number, category: PreseasonCategory): Promise<PreseasonPick | null> {
  const db = getDb()
  const rows = await db.select().from(preseasonPick)
    .where(and(
      eq(preseasonPick.userId, userId),
      eq(preseasonPick.seasonYear, seasonYear),
      eq(preseasonPick.category, category)
    )).limit(1)
  return rows[0] ? toPick(rows[0]) : null
}

export async function listForUser(userId: string, seasonYear: number): Promise<PreseasonPick[]> {
  const db = getDb()
  const rows = await db.select().from(preseasonPick)
    .where(and(eq(preseasonPick.userId, userId), eq(preseasonPick.seasonYear, seasonYear)))
  return rows.map(toPick)
}

export async function listForSeason(seasonYear: number): Promise<PreseasonPick[]> {
  const db = getDb()
  const rows = await db.select().from(preseasonPick).where(eq(preseasonPick.seasonYear, seasonYear))
  return rows.map(toPick)
}

export async function deletePick(userId: string, seasonYear: number, category: PreseasonCategory): Promise<void> {
  const db = getDb()
  await db.delete(preseasonPick).where(and(
    eq(preseasonPick.userId, userId),
    eq(preseasonPick.seasonYear, seasonYear),
    eq(preseasonPick.category, category)
  ))
}
```

- [ ] **Step 2: Implement `src/repo/preseasonStandings.ts`**

```ts
import { and, eq, asc } from 'drizzle-orm'
import { getDb } from '../db/client.js'
import { preseasonPickStandingsDriver, preseasonPickStandingsConstructor } from '../db/schema.js'

export type StandingsPickInput = { position: number; entityId: string }

export async function replaceDriverPicks(userId: string, seasonYear: number, picks: StandingsPickInput[]): Promise<void> {
  const db = getDb()
  await db.transaction(async (tx) => {
    await tx.delete(preseasonPickStandingsDriver).where(and(
      eq(preseasonPickStandingsDriver.userId, userId),
      eq(preseasonPickStandingsDriver.seasonYear, seasonYear)
    ))
    if (picks.length === 0) return
    await tx.insert(preseasonPickStandingsDriver).values(picks.map((p) => ({
      userId, seasonYear, position: p.position, driverCode: p.entityId
    })))
  })
}

export async function replaceConstructorPicks(userId: string, seasonYear: number, picks: StandingsPickInput[]): Promise<void> {
  const db = getDb()
  await db.transaction(async (tx) => {
    await tx.delete(preseasonPickStandingsConstructor).where(and(
      eq(preseasonPickStandingsConstructor.userId, userId),
      eq(preseasonPickStandingsConstructor.seasonYear, seasonYear)
    ))
    if (picks.length === 0) return
    await tx.insert(preseasonPickStandingsConstructor).values(picks.map((p) => ({
      userId, seasonYear, position: p.position, constructorId: p.entityId
    })))
  })
}

export async function listDriverPicks(userId: string, seasonYear: number): Promise<StandingsPickInput[]> {
  const db = getDb()
  const rows = await db.select({
    position: preseasonPickStandingsDriver.position,
    entityId: preseasonPickStandingsDriver.driverCode
  })
    .from(preseasonPickStandingsDriver)
    .where(and(eq(preseasonPickStandingsDriver.userId, userId), eq(preseasonPickStandingsDriver.seasonYear, seasonYear)))
    .orderBy(asc(preseasonPickStandingsDriver.position))
  return rows
}

export async function listConstructorPicks(userId: string, seasonYear: number): Promise<StandingsPickInput[]> {
  const db = getDb()
  const rows = await db.select({
    position: preseasonPickStandingsConstructor.position,
    entityId: preseasonPickStandingsConstructor.constructorId
  })
    .from(preseasonPickStandingsConstructor)
    .where(and(eq(preseasonPickStandingsConstructor.userId, userId), eq(preseasonPickStandingsConstructor.seasonYear, seasonYear)))
    .orderBy(asc(preseasonPickStandingsConstructor.position))
  return rows
}
```

- [ ] **Step 3: Implement `src/repo/subjectiveTruth.ts`**

```ts
import { eq, sql } from 'drizzle-orm'
import { getDb } from '../db/client.js'
import { subjectiveTruth } from '../db/schema.js'
import type { SubjectiveTruth } from '../domain/types.js'

export type TruthInput = {
  surpriseDriverCode: string | null
  surpriseConstructorId: string | null
  disappointmentDriverCode: string | null
  disappointmentConstructorId: string | null
}

function toTruth(row: typeof subjectiveTruth.$inferSelect): SubjectiveTruth {
  return {
    seasonYear: row.seasonYear,
    surpriseDriverCode: row.surpriseDriverCode,
    surpriseConstructorId: row.surpriseConstructorId,
    disappointmentDriverCode: row.disappointmentDriverCode,
    disappointmentConstructorId: row.disappointmentConstructorId,
    setAt: row.setAt
  }
}

export async function upsertTruth(seasonYear: number, input: TruthInput): Promise<SubjectiveTruth> {
  const db = getDb()
  const [row] = await db.insert(subjectiveTruth)
    .values({ seasonYear, ...input })
    .onConflictDoUpdate({
      target: [subjectiveTruth.seasonYear],
      set: { ...input, setAt: sql`now()` }
    })
    .returning()
  return toTruth(row!)
}

export async function getTruth(seasonYear: number): Promise<SubjectiveTruth | null> {
  const db = getDb()
  const rows = await db.select().from(subjectiveTruth).where(eq(subjectiveTruth.seasonYear, seasonYear)).limit(1)
  return rows[0] ? toTruth(rows[0]) : null
}
```

- [ ] **Step 4: Write tests**

Create `backend/test/integration/repo_preseasonPicks.test.ts`:

```ts
import { describe, it, expect } from 'vitest'
import * as users from '../../src/repo/users.js'
import * as seasons from '../../src/repo/seasons.js'
import * as drivers from '../../src/repo/drivers.js'
import * as constructors from '../../src/repo/constructors.js'
import * as picks from '../../src/repo/preseasonPicks.js'

async function seed() {
  await seasons.upsertSeason({ year: 2026, isCurrent: true })
  await constructors.upsertConstructor({ id: 'red_bull', name: 'Red Bull', nationality: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null })
  await drivers.upsertDriver({ code: 'VER', givenName: 'Max', familyName: 'V', nationality: null, permanentNumber: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null })
  return await users.insertUser({ email: 't@x.com', passwordHash: 'h', displayName: 'T' })
}

describe('preseasonPicks repo', () => {
  it('upserts and reads a pick back', async () => {
    const u = await seed()
    await picks.upsertPick(u.id, 2026, 'surprise', { driverCode: 'VER', constructorId: 'red_bull' })
    const got = await picks.getPick(u.id, 2026, 'surprise')
    expect(got?.driverCode).toBe('VER')
    expect(got?.constructorId).toBe('red_bull')
  })

  it('upsert replaces existing values', async () => {
    const u = await seed()
    await picks.upsertPick(u.id, 2026, 'dnf', { driverCode: 'VER', constructorId: null })
    await picks.upsertPick(u.id, 2026, 'dnf', { driverCode: null, constructorId: 'red_bull' })
    const got = await picks.getPick(u.id, 2026, 'dnf')
    expect(got?.driverCode).toBeNull()
    expect(got?.constructorId).toBe('red_bull')
  })

  it('accepts driver-only and team-only picks (nullable columns)', async () => {
    const u = await seed()
    await picks.upsertPick(u.id, 2026, 'poles', { driverCode: 'VER', constructorId: null })
    const got = await picks.getPick(u.id, 2026, 'poles')
    expect(got?.driverCode).toBe('VER')
    expect(got?.constructorId).toBeNull()
  })

  it('listForUser returns all picks for a season', async () => {
    const u = await seed()
    await picks.upsertPick(u.id, 2026, 'surprise', { driverCode: 'VER', constructorId: null })
    await picks.upsertPick(u.id, 2026, 'dnf', { driverCode: null, constructorId: 'red_bull' })
    const all = await picks.listForUser(u.id, 2026)
    expect(all).toHaveLength(2)
  })

  it('deletePick removes the row', async () => {
    const u = await seed()
    await picks.upsertPick(u.id, 2026, 'fastest_lap', { driverCode: 'VER', constructorId: 'red_bull' })
    await picks.deletePick(u.id, 2026, 'fastest_lap')
    expect(await picks.getPick(u.id, 2026, 'fastest_lap')).toBeNull()
  })

  it('cascades from user delete', async () => {
    const u = await seed()
    await picks.upsertPick(u.id, 2026, 'wdc_wcc', { driverCode: 'VER', constructorId: 'red_bull' })
    await users.deleteById(u.id)
    expect(await picks.getPick(u.id, 2026, 'wdc_wcc')).toBeNull()
  })
})
```

Create `backend/test/integration/repo_preseasonStandings.test.ts`:

```ts
import { describe, it, expect } from 'vitest'
import * as users from '../../src/repo/users.js'
import * as seasons from '../../src/repo/seasons.js'
import * as drivers from '../../src/repo/drivers.js'
import * as constructors from '../../src/repo/constructors.js'
import * as standings from '../../src/repo/preseasonStandings.js'

async function seedDriversAndUser() {
  await seasons.upsertSeason({ year: 2026, isCurrent: true })
  for (const c of ['red_bull', 'mercedes', 'mclaren']) {
    await constructors.upsertConstructor({ id: c, name: c, nationality: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null })
  }
  for (const code of ['VER', 'PER', 'HAM', 'RUS', 'NOR']) {
    await drivers.upsertDriver({ code, givenName: code, familyName: 'X', nationality: null, permanentNumber: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null })
  }
  return await users.insertUser({ email: 's@x.com', passwordHash: 'h', displayName: 'S' })
}

describe('preseasonStandings repo', () => {
  it('replaces driver picks atomically', async () => {
    const u = await seedDriversAndUser()
    await standings.replaceDriverPicks(u.id, 2026, [
      { position: 1, entityId: 'VER' },
      { position: 2, entityId: 'HAM' }
    ])
    let list = await standings.listDriverPicks(u.id, 2026)
    expect(list).toEqual([
      { position: 1, entityId: 'VER' },
      { position: 2, entityId: 'HAM' }
    ])

    await standings.replaceDriverPicks(u.id, 2026, [
      { position: 1, entityId: 'HAM' }
    ])
    list = await standings.listDriverPicks(u.id, 2026)
    expect(list).toEqual([{ position: 1, entityId: 'HAM' }])
  })

  it('rejects duplicate driver within a season for the same user', async () => {
    const u = await seedDriversAndUser()
    await expect(standings.replaceDriverPicks(u.id, 2026, [
      { position: 1, entityId: 'VER' },
      { position: 2, entityId: 'VER' }
    ])).rejects.toThrow(/duplicate|unique/i)
  })

  it('replaces constructor picks', async () => {
    const u = await seedDriversAndUser()
    await standings.replaceConstructorPicks(u.id, 2026, [
      { position: 1, entityId: 'red_bull' },
      { position: 2, entityId: 'mercedes' }
    ])
    const list = await standings.listConstructorPicks(u.id, 2026)
    expect(list).toEqual([
      { position: 1, entityId: 'red_bull' },
      { position: 2, entityId: 'mercedes' }
    ])
  })

  it('empty replace clears the picks', async () => {
    const u = await seedDriversAndUser()
    await standings.replaceDriverPicks(u.id, 2026, [{ position: 1, entityId: 'VER' }])
    await standings.replaceDriverPicks(u.id, 2026, [])
    expect(await standings.listDriverPicks(u.id, 2026)).toEqual([])
  })

  it('cascades from user delete', async () => {
    const u = await seedDriversAndUser()
    await standings.replaceDriverPicks(u.id, 2026, [{ position: 1, entityId: 'VER' }])
    await users.deleteById(u.id)
    expect(await standings.listDriverPicks(u.id, 2026)).toEqual([])
  })
})
```

Create `backend/test/integration/repo_subjectiveTruth.test.ts`:

```ts
import { describe, it, expect } from 'vitest'
import * as seasons from '../../src/repo/seasons.js'
import * as drivers from '../../src/repo/drivers.js'
import * as constructors from '../../src/repo/constructors.js'
import * as truth from '../../src/repo/subjectiveTruth.js'

async function seed() {
  await seasons.upsertSeason({ year: 2026, isCurrent: true })
  await constructors.upsertConstructor({ id: 'red_bull', name: 'Red Bull', nationality: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null })
  await constructors.upsertConstructor({ id: 'mercedes', name: 'Mercedes', nationality: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null })
  await drivers.upsertDriver({ code: 'VER', givenName: 'M', familyName: 'V', nationality: null, permanentNumber: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null })
  await drivers.upsertDriver({ code: 'HAM', givenName: 'L', familyName: 'H', nationality: null, permanentNumber: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null })
}

describe('subjectiveTruth repo', () => {
  it('upserts and reads back', async () => {
    await seed()
    await truth.upsertTruth(2026, {
      surpriseDriverCode: 'VER',
      surpriseConstructorId: 'red_bull',
      disappointmentDriverCode: 'HAM',
      disappointmentConstructorId: 'mercedes'
    })
    const got = await truth.getTruth(2026)
    expect(got?.surpriseDriverCode).toBe('VER')
    expect(got?.disappointmentDriverCode).toBe('HAM')
  })

  it('upsert replaces existing row', async () => {
    await seed()
    await truth.upsertTruth(2026, {
      surpriseDriverCode: 'VER', surpriseConstructorId: 'red_bull',
      disappointmentDriverCode: null, disappointmentConstructorId: null
    })
    await truth.upsertTruth(2026, {
      surpriseDriverCode: 'HAM', surpriseConstructorId: 'mercedes',
      disappointmentDriverCode: null, disappointmentConstructorId: null
    })
    const got = await truth.getTruth(2026)
    expect(got?.surpriseDriverCode).toBe('HAM')
  })

  it('returns null for an unknown season', async () => {
    await seed()
    expect(await truth.getTruth(2099)).toBeNull()
  })

  it('accepts all-null fields', async () => {
    await seed()
    await truth.upsertTruth(2026, {
      surpriseDriverCode: null, surpriseConstructorId: null,
      disappointmentDriverCode: null, disappointmentConstructorId: null
    })
    const got = await truth.getTruth(2026)
    expect(got?.surpriseDriverCode).toBeNull()
  })
})
```

- [ ] **Step 5: Run all new tests + full suite**

```bash
cd /Users/anton/Dev/Projects/F1predictiongame/backend
set -a && source .env && set +a
npx vitest run test/integration/repo_preseason
npm test
npx tsc --noEmit
```
Expected: 16 new tests pass; full suite green; tsc clean.

- [ ] **Step 6: Commit**

```bash
cd /Users/anton/Dev/Projects/F1predictiongame
git add backend/src/repo/preseasonPicks.ts backend/src/repo/preseasonStandings.ts backend/src/repo/subjectiveTruth.ts backend/test/integration/repo_preseason
git commit -m "backend: preseason picks, standings, and subjective truth repos"
```

---

### Task 5: Scores repo updates

**Files:**
- Modify: `backend/src/repo/scores.ts`
- Modify: `backend/test/integration/repo_scores.test.ts` (regression coverage)
- Create: `backend/test/integration/api_leaderboard_with_preseason.test.ts` (new — covers the SQL change)

Adds `upsertPreseasonScore`, `listPreseasonForUser`, and modifies `leagueLeaderboard` SQL to UNION preseason rows so the league leaderboard sums both.

- [ ] **Step 1: Modify `src/repo/scores.ts`**

Read the existing file. Apply these changes:

1. At the top, the imports already include `score, session, event, leagueMember, user`. No changes there.

2. Replace `leagueLeaderboard` (the existing SQL needs to UNION preseason rows):

```ts
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
    LEFT JOIN (
      SELECT s.user_id, s.session_id, s.points_total
      FROM ${score} s
      JOIN ${session} ses ON ses.id = s.session_id
      JOIN ${event} ev ON ev.id = ses.event_id
      WHERE s.kind = 'session' AND ev.season_year = ${seasonYear}
      UNION ALL
      SELECT s.user_id, NULL::int AS session_id, s.points_total
      FROM ${score} s
      WHERE s.kind = 'preseason' AND s.season_year = ${seasonYear}
    ) s ON s.user_id = lm.user_id
    WHERE lm.league_id = ${leagueId}
    GROUP BY lm.user_id, u.display_name
    ORDER BY "pointsTotal" DESC, "displayName" ASC
  `)
  return (rows as unknown as { rows: LeaderboardRow[] }).rows
}
```

3. Append new functions at the end of the file:

```ts
export type UserPreseasonScoreRow = {
  userId: string
  seasonYear: number
  category: string
  pointsTotal: number
  breakdown: ScoreBreakdown
  computedAt: Date
}

export async function upsertPreseasonScore(
  userId: string,
  seasonYear: number,
  category: string,
  pointsTotal: number,
  breakdown: ScoreBreakdown
): Promise<void> {
  const db = getDb()
  await db.execute(sql`
    INSERT INTO ${score} ("user_id", "session_id", "points_total", "breakdown", "kind", "season_year", "preseason_category")
    VALUES (${userId}::uuid, NULL, ${pointsTotal}, ${JSON.stringify(breakdown)}::jsonb, 'preseason', ${seasonYear}, ${category})
    ON CONFLICT ("user_id", "season_year", "preseason_category") WHERE kind = 'preseason'
    DO UPDATE SET points_total = EXCLUDED.points_total,
                  breakdown    = EXCLUDED.breakdown,
                  computed_at  = now()
  `)
}

export async function listPreseasonForUser(userId: string, seasonYear: number): Promise<UserPreseasonScoreRow[]> {
  const db = getDb()
  const rows = await db.execute(sql`
    SELECT
      "user_id"::text       AS "userId",
      "season_year"         AS "seasonYear",
      "preseason_category"  AS "category",
      "points_total"        AS "pointsTotal",
      "breakdown"           AS "breakdown",
      "computed_at"         AS "computedAt"
    FROM ${score}
    WHERE "user_id" = ${userId}::uuid
      AND "kind" = 'preseason'
      AND "season_year" = ${seasonYear}
    ORDER BY "preseason_category"
  `)
  return ((rows as unknown as { rows: any[] }).rows).map((r) => ({
    userId: r.userId,
    seasonYear: r.seasonYear,
    category: r.category,
    pointsTotal: r.pointsTotal,
    breakdown: r.breakdown as ScoreBreakdown,
    computedAt: new Date(r.computedAt)
  }))
}
```

- [ ] **Step 2: Add regression test for leaderboard with preseason rows**

Create `backend/test/integration/api_leaderboard_with_preseason.test.ts`:

```ts
import { describe, it, expect } from 'vitest'
import * as users from '../../src/repo/users.js'
import * as seasons from '../../src/repo/seasons.js'
import * as events from '../../src/repo/events.js'
import * as sessions from '../../src/repo/sessions.js'
import * as leagues from '../../src/repo/leagues.js'
import * as members from '../../src/repo/leagueMembers.js'
import * as scores from '../../src/repo/scores.js'

const bd = (p: number) => ({
  perPosition: [{ position: 1, exact: true, wrongPos: false, points: p }],
  teamBonus: { applied: false, points: 0 },
  rule: 'test-v1'
})
const bdp = (p: number) => ({
  driver: { picked: 'VER', truth: 'VER', correct: true, points: p },
  team: { picked: null, truth: null, correct: false, points: 0 },
  pointsTotal: p,
  rule: 'preseason-surprise-v1'
})

async function seedSession() {
  await seasons.upsertSeason({ year: 2026, isCurrent: true })
  const ev = await events.upsertEvent({
    seasonYear: 2026, round: 1, name: 'B', circuitName: 'C', country: 'X', hasSprint: false
  })
  return sessions.upsertSession({
    eventId: ev.id, type: 'race',
    scheduledStart: new Date(2026, 2, 8, 15), scheduledEnd: new Date(2026, 2, 8, 17), status: 'scheduled'
  })
}

describe('leaderboard sums session + preseason scores', () => {
  it('a user with both kinds gets the combined total', async () => {
    const ses = await seedSession()
    const owner = await users.insertUser({ email: 'o@x.com', passwordHash: 'h', displayName: 'O' })
    const l = await leagues.createLeagueWithOwner({ name: 'L', ownerUserId: owner.id, joinCode: 'CMB001' })

    // Session score: 10 pts
    await scores.upsertScore(owner.id, ses.id, 10, bd(10))
    // Preseason scores: 4 + 8 = 12 pts across 2 categories
    await scores.upsertPreseasonScore(owner.id, 2026, 'surprise', 4, bdp(4))
    await scores.upsertPreseasonScore(owner.id, 2026, 'dnf',      8, bdp(8))

    const lb = await scores.leagueLeaderboard(l.id, 2026)
    const me = lb.find((r) => r.userId === owner.id)!
    expect(me.pointsTotal).toBe(22)
    expect(me.sessionsScored).toBe(1)  // only 1 session, preseason doesn't count
  })

  it('preseason-only user still appears with their points', async () => {
    await seedSession()
    const owner = await users.insertUser({ email: 'p@x.com', passwordHash: 'h', displayName: 'P' })
    const l = await leagues.createLeagueWithOwner({ name: 'LP', ownerUserId: owner.id, joinCode: 'CMB002' })
    await scores.upsertPreseasonScore(owner.id, 2026, 'wdc_wcc', 8, bdp(8))
    const lb = await scores.leagueLeaderboard(l.id, 2026)
    const me = lb.find((r) => r.userId === owner.id)!
    expect(me.pointsTotal).toBe(8)
    expect(me.sessionsScored).toBe(0)
  })

  it('zero-score member still appears', async () => {
    await seedSession()
    const owner = await users.insertUser({ email: 'z@x.com', passwordHash: 'h', displayName: 'Z' })
    const l = await leagues.createLeagueWithOwner({ name: 'LZ', ownerUserId: owner.id, joinCode: 'CMB003' })
    const lb = await scores.leagueLeaderboard(l.id, 2026)
    expect(lb.find((r) => r.userId === owner.id)!.pointsTotal).toBe(0)
  })

  it('season filter excludes preseason from other seasons', async () => {
    await seedSession()
    await seasons.upsertSeason({ year: 2024, isCurrent: false })
    const owner = await users.insertUser({ email: 'f@x.com', passwordHash: 'h', displayName: 'F' })
    const l = await leagues.createLeagueWithOwner({ name: 'LF', ownerUserId: owner.id, joinCode: 'CMB004' })
    await scores.upsertPreseasonScore(owner.id, 2024, 'surprise', 99, bdp(99))
    const lb = await scores.leagueLeaderboard(l.id, 2026)
    expect(lb.find((r) => r.userId === owner.id)!.pointsTotal).toBe(0)
  })
})
```

- [ ] **Step 3: Verify tests pass**

```bash
cd /Users/anton/Dev/Projects/F1predictiongame/backend
set -a && source .env && set +a
npx vitest run test/integration/api_leaderboard_with_preseason.test.ts
npm test
npx tsc --noEmit
```
Expected: 4 new tests pass; existing scores tests still pass; tsc clean.

- [ ] **Step 4: Commit**

```bash
cd /Users/anton/Dev/Projects/F1predictiongame
git add backend/src/repo/scores.ts backend/test/integration/api_leaderboard_with_preseason.test.ts
git commit -m "backend: scores repo gains preseason upsert + leaderboard SQL unions both kinds"
```

---

### Task 6: Rescorer + tick integration

**Files:**
- Create: `backend/src/preseason/rescorer.ts`
- Modify: `backend/src/crawler/tick.ts`
- Create: `backend/test/integration/preseason_rescorer.test.ts`
- Create: `backend/test/integration/crawler_tick_preseason_rescore.test.ts`

- [ ] **Step 1: Implement `src/preseason/rescorer.ts`**

```ts
import * as seasonsRepo from '../repo/seasons.js'
import * as eventsRepo from '../repo/events.js'
import * as sessionsRepo from '../repo/sessions.js'
import * as resultsRepo from '../repo/results.js'
import * as standingsRepo from '../repo/standings.js'
import * as picksRepo from '../repo/preseasonPicks.js'
import * as preseasonStandingsRepo from '../repo/preseasonStandings.js'
import * as truthRepo from '../repo/subjectiveTruth.js'
import * as scoresRepo from '../repo/scores.js'
import { scorePreseasonCategory, scoreStandings } from './index.js'
import {
  deriveMostDnfs, derivePolesitter, deriveMostFastestLaps, deriveWdcWcc, deriveFinalStandings
} from './derive.js'
import type { PreseasonCategory } from '../domain/types.js'

export type RescoreSummary = { users: number; totalPoints: number }

const ALL_SINGLE_CATEGORIES: PreseasonCategory[] = [
  'surprise', 'disappointment', 'dnf', 'poles', 'fastest_lap', 'wdc_wcc'
]

export async function rescorePreseasonForSeason(seasonYear: number): Promise<RescoreSummary> {
  // Need events + sessions of the season for the derive layer (which gates by session type)
  const events = await eventsRepo.listForSeason(seasonYear)
  if (events.length === 0) return { users: 0, totalPoints: 0 }
  const allSessions: Awaited<ReturnType<typeof sessionsRepo.listForEvent>> = []
  const allResults = []
  for (const ev of events) {
    const sessions = await sessionsRepo.listForEvent(ev.id)
    allSessions.push(...sessions)
    for (const s of sessions) {
      const rows = await resultsRepo.listForSession(s.id)
      allResults.push(...rows)
    }
  }
  const driverStandings = await standingsRepo.listDriverStandings(seasonYear)
  const constructorStandings = await standingsRepo.listConstructorStandings(seasonYear)

  // Derive observed truths
  const dnfPair    = deriveMostDnfs(allResults, allSessions)
  const polesPair  = derivePolesitter(allResults, allSessions)
  const flPair     = deriveMostFastestLaps(allResults, allSessions)
  const wdcWccPair = deriveWdcWcc(driverStandings, constructorStandings)
  const finalStandings = deriveFinalStandings(driverStandings, constructorStandings)

  // Subjective truth (may be null)
  const subjective = await truthRepo.getTruth(seasonYear)
  const surpriseTruth = {
    driverCode: subjective?.surpriseDriverCode ?? null,
    constructorId: subjective?.surpriseConstructorId ?? null
  }
  const disappointmentTruth = {
    driverCode: subjective?.disappointmentDriverCode ?? null,
    constructorId: subjective?.disappointmentConstructorId ?? null
  }

  // Find all users with at least one preseason pick (single or standings) for this season
  const allPicks = await picksRepo.listForSeason(seasonYear)
  const usersWithPicks = new Set(allPicks.map((p) => p.userId))
  // Also include users with standings picks (the listForSeason query above only sees single-picks)
  // Cheap approach: query the standings tables and union
  const standingsDriverUsers = await usersWithDriverStandings(seasonYear)
  const standingsCtorUsers = await usersWithConstructorStandings(seasonYear)
  for (const id of standingsDriverUsers) usersWithPicks.add(id)
  for (const id of standingsCtorUsers) usersWithPicks.add(id)

  let totalPoints = 0
  for (const userId of usersWithPicks) {
    // 6 single-pick categories
    for (const category of ALL_SINGLE_CATEGORIES) {
      const pick = await picksRepo.getPick(userId, seasonYear, category)
      const truth = truthForCategory(category, { dnfPair, polesPair, flPair, wdcWccPair, surpriseTruth, disappointmentTruth })
      const pickInput = {
        driverCode: pick?.driverCode ?? null,
        constructorId: pick?.constructorId ?? null
      }
      const breakdown = scorePreseasonCategory(category, pickInput, truth)
      await scoresRepo.upsertPreseasonScore(userId, seasonYear, category, breakdown.pointsTotal, breakdown)
      totalPoints += breakdown.pointsTotal
    }
    // Standings category
    const driverPicks = await preseasonStandingsRepo.listDriverPicks(userId, seasonYear)
    const constructorPicks = await preseasonStandingsRepo.listConstructorPicks(userId, seasonYear)
    const standingsBreakdown = scoreStandings(driverPicks, constructorPicks, finalStandings.drivers, finalStandings.constructors)
    await scoresRepo.upsertPreseasonScore(userId, seasonYear, 'standings', standingsBreakdown.pointsTotal, standingsBreakdown)
    totalPoints += standingsBreakdown.pointsTotal
  }

  return { users: usersWithPicks.size, totalPoints }
}

function truthForCategory(
  category: PreseasonCategory,
  data: {
    dnfPair: { driverCode: string | null; constructorId: string | null }
    polesPair: { driverCode: string | null; constructorId: string | null }
    flPair: { driverCode: string | null; constructorId: string | null }
    wdcWccPair: { driverCode: string | null; constructorId: string | null }
    surpriseTruth: { driverCode: string | null; constructorId: string | null }
    disappointmentTruth: { driverCode: string | null; constructorId: string | null }
  }
): { driverCode: string | null; constructorId: string | null } {
  switch (category) {
    case 'surprise':       return data.surpriseTruth
    case 'disappointment': return data.disappointmentTruth
    case 'dnf':            return data.dnfPair
    case 'poles':          return data.polesPair
    case 'fastest_lap':    return data.flPair
    case 'wdc_wcc':        return data.wdcWccPair
  }
}

// Small helpers — could live in standings repo but only used here. Inline for now.
async function usersWithDriverStandings(seasonYear: number): Promise<string[]> {
  const { getDb } = await import('../db/client.js')
  const { sql } = await import('drizzle-orm')
  const { preseasonPickStandingsDriver } = await import('../db/schema.js')
  const db = getDb()
  const rows = await db.execute(sql`SELECT DISTINCT user_id::text AS "userId" FROM ${preseasonPickStandingsDriver} WHERE season_year = ${seasonYear}`)
  return (rows as unknown as { rows: { userId: string }[] }).rows.map((r) => r.userId)
}

async function usersWithConstructorStandings(seasonYear: number): Promise<string[]> {
  const { getDb } = await import('../db/client.js')
  const { sql } = await import('drizzle-orm')
  const { preseasonPickStandingsConstructor } = await import('../db/schema.js')
  const db = getDb()
  const rows = await db.execute(sql`SELECT DISTINCT user_id::text AS "userId" FROM ${preseasonPickStandingsConstructor} WHERE season_year = ${seasonYear}`)
  return (rows as unknown as { rows: { userId: string }[] }).rows.map((r) => r.userId)
}
```

(If `standingsRepo.listConstructorStandings` doesn't exist, add it; mirrors `listDriverStandings` shape — see Task 6 Step 2.)

- [ ] **Step 2: Ensure `listConstructorStandings` exists in `src/repo/standings.ts`**

Open `backend/src/repo/standings.ts`. If `listConstructorStandings` is missing, add it:

```ts
export async function listConstructorStandings(seasonYear: number): Promise<{ constructorId: string; position: number; points: number; wins: number; seasonYear: number }[]> {
  const db = getDb()
  const rows = await db.select().from(constructorStanding)
    .where(eq(constructorStanding.seasonYear, seasonYear))
    .orderBy(asc(constructorStanding.position))
  return rows.map((r) => ({
    seasonYear: r.seasonYear,
    constructorId: r.constructorId,
    position: r.position,
    points: r.points,
    wins: r.wins
  }))
}
```

(Add `constructorStanding` to imports if missing.)

- [ ] **Step 3: Write rescorer tests**

Create `backend/test/integration/preseason_rescorer.test.ts`:

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
import * as picks from '../../src/repo/preseasonPicks.js'
import * as preseasonStandings from '../../src/repo/preseasonStandings.js'
import * as truth from '../../src/repo/subjectiveTruth.js'
import * as scores from '../../src/repo/scores.js'
import { rescorePreseasonForSeason } from '../../src/preseason/rescorer.js'

async function seedSeason() {
  await seasons.upsertSeason({ year: 2026, isCurrent: true })
  for (const c of ['red_bull', 'mercedes', 'mclaren']) {
    await constructors.upsertConstructor({ id: c, name: c, nationality: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null })
  }
  for (const code of ['VER', 'PER', 'HAM', 'RUS', 'NOR', 'PIA']) {
    await drivers.upsertDriver({ code, givenName: code, familyName: 'X', nationality: null, permanentNumber: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null })
  }
  const ev = await events.upsertEvent({ seasonYear: 2026, round: 1, name: 'B', circuitName: 'C', country: 'X', hasSprint: false })
  const race = await sessions.upsertSession({
    eventId: ev.id, type: 'race',
    scheduledStart: new Date(2026, 2, 8, 15), scheduledEnd: new Date(2026, 2, 8, 17), status: 'scheduled'
  })
  const quali = await sessions.upsertSession({
    eventId: ev.id, type: 'qualifying',
    scheduledStart: new Date(2026, 2, 7, 14), scheduledEnd: new Date(2026, 2, 7, 15), status: 'scheduled'
  })
  await standings.replaceDriverStandings(2026, [
    { driverCode: 'VER', position: 1, points: 400, wins: 10, constructorId: 'red_bull' },
    { driverCode: 'HAM', position: 2, points: 300, wins: 4,  constructorId: 'mercedes' },
    { driverCode: 'NOR', position: 3, points: 250, wins: 3,  constructorId: 'mclaren' }
  ])
  await standings.replaceConstructorStandings(2026, [
    { constructorId: 'red_bull', position: 1, points: 700, wins: 11 },
    { constructorId: 'mclaren',  position: 2, points: 600, wins: 6 },
    { constructorId: 'mercedes', position: 3, points: 500, wins: 5 }
  ])
  return { race, quali }
}

function rr(sessionId: number, position: number, code: string, team: string, opts: Record<string, any> = {}) {
  return {
    sessionId, position, driverCode: code, driverName: code,
    constructorId: team, constructorName: team,
    raceTime: null, status: 'Finished', points: null,
    fastestLap: null, fastestLapTime: null, fastestLapSpeed: null,
    q1: null, q2: null, q3: null,
    ...opts
  }
}

describe('rescorePreseasonForSeason', () => {
  it('scores all 7 category rows per user with at least one pick', async () => {
    const { race, quali } = await seedSeason()
    await results.replaceForSession(race.id, [
      rr(race.id, 1, 'VER', 'red_bull', { fastestLap: '1' }),
      rr(race.id, 2, 'HAM', 'mercedes'),
      rr(race.id, 20, 'PER', 'red_bull', { status: 'Retired' })
    ])
    await results.replaceForSession(quali.id, [
      rr(quali.id, 1, 'VER', 'red_bull')
    ])

    const u = await users.insertUser({ email: 't@x.com', passwordHash: 'h', displayName: 'T' })
    // Correct picks
    await picks.upsertPick(u.id, 2026, 'dnf', { driverCode: 'PER', constructorId: 'red_bull' })
    await picks.upsertPick(u.id, 2026, 'poles', { driverCode: 'VER', constructorId: 'red_bull' })
    await picks.upsertPick(u.id, 2026, 'fastest_lap', { driverCode: 'VER', constructorId: 'red_bull' })
    await picks.upsertPick(u.id, 2026, 'wdc_wcc', { driverCode: 'VER', constructorId: 'red_bull' })

    const summary = await rescorePreseasonForSeason(2026)
    expect(summary.users).toBe(1)

    const list = await scores.listPreseasonForUser(u.id, 2026)
    // Expect 7 rows (6 single + 1 standings)
    expect(list).toHaveLength(7)

    const byCategory = new Map(list.map((r) => [r.category, r.pointsTotal]))
    expect(byCategory.get('dnf')).toBe(8)         // both correct
    expect(byCategory.get('poles')).toBe(8)
    expect(byCategory.get('fastest_lap')).toBe(8)
    expect(byCategory.get('wdc_wcc')).toBe(8)
    expect(byCategory.get('surprise')).toBe(0)    // truth not set
    expect(byCategory.get('disappointment')).toBe(0)
    expect(byCategory.get('standings')).toBe(0)   // no standings picks submitted
  })

  it('scores subjective categories after admin sets truth', async () => {
    await seedSeason()
    const u = await users.insertUser({ email: 's@x.com', passwordHash: 'h', displayName: 'S' })
    await picks.upsertPick(u.id, 2026, 'surprise', { driverCode: 'HAM', constructorId: 'mclaren' })

    let summary = await rescorePreseasonForSeason(2026)
    let list = await scores.listPreseasonForUser(u.id, 2026)
    expect(list.find((r) => r.category === 'surprise')!.pointsTotal).toBe(0)

    await truth.upsertTruth(2026, {
      surpriseDriverCode: 'HAM', surpriseConstructorId: 'mclaren',
      disappointmentDriverCode: null, disappointmentConstructorId: null
    })
    summary = await rescorePreseasonForSeason(2026)
    list = await scores.listPreseasonForUser(u.id, 2026)
    expect(list.find((r) => r.category === 'surprise')!.pointsTotal).toBe(8)
  })

  it('scores standings picks against final ordering', async () => {
    await seedSeason()
    const u = await users.insertUser({ email: 'st@x.com', passwordHash: 'h', displayName: 'St' })
    await preseasonStandings.replaceDriverPicks(u.id, 2026, [
      { position: 1, entityId: 'VER' },   // correct
      { position: 2, entityId: 'NOR' },   // wrong (truth: HAM)
      { position: 3, entityId: 'HAM' }    // wrong (truth: NOR)
    ])
    await preseasonStandings.replaceConstructorPicks(u.id, 2026, [
      { position: 1, entityId: 'red_bull' }   // correct
    ])
    await rescorePreseasonForSeason(2026)
    const list = await scores.listPreseasonForUser(u.id, 2026)
    const standings = list.find((r) => r.category === 'standings')!
    expect(standings.pointsTotal).toBe(3 + 4)  // 1 driver correct + 1 team correct
  })

  it('is idempotent', async () => {
    await seedSeason()
    const u = await users.insertUser({ email: 'i@x.com', passwordHash: 'h', displayName: 'I' })
    await picks.upsertPick(u.id, 2026, 'wdc_wcc', { driverCode: 'VER', constructorId: 'red_bull' })
    await rescorePreseasonForSeason(2026)
    await rescorePreseasonForSeason(2026)
    const list = await scores.listPreseasonForUser(u.id, 2026)
    expect(list).toHaveLength(7)
    expect(list.find((r) => r.category === 'wdc_wcc')!.pointsTotal).toBe(8)
  })

  it('no-op when season has no events', async () => {
    await seasons.upsertSeason({ year: 2099, isCurrent: false })
    const summary = await rescorePreseasonForSeason(2099)
    expect(summary).toEqual({ users: 0, totalPoints: 0 })
  })
})
```

- [ ] **Step 4: Verify rescorer tests pass**

```bash
cd /Users/anton/Dev/Projects/F1predictiongame/backend
set -a && source .env && set +a
npx vitest run test/integration/preseason_rescorer.test.ts
```
Expected: PASS (5 tests).

- [ ] **Step 5: Wire rescorer into `src/crawler/tick.ts`**

Open `backend/src/crawler/tick.ts`. Add this import at the top alongside other imports:

```ts
import { rescorePreseasonForSeason } from '../preseason/rescorer.js'
```

Find the `if (anyFinished)` block at the end of `runTick`. Inside that block, after both `replaceDriverStandings` and `replaceConstructorStandings` complete (i.e. after the existing inner try/catch), add:

```ts
      try {
        const summary = await rescorePreseasonForSeason(cur.year)
        console.log('Preseason rescored', { year: cur.year, ...summary })
      } catch (err) {
        console.error('Preseason rescore failed', err)
      }
```

Place it INSIDE the existing `if (cur)` block, AFTER the `replaceConstructorStandings(...)` call, BEFORE the outer `} catch (err) {`.

- [ ] **Step 6: Write tick integration test**

Create `backend/test/integration/crawler_tick_preseason_rescore.test.ts`:

```ts
import { describe, it, expect } from 'vitest'
import * as seasons from '../../src/repo/seasons.js'
import * as events from '../../src/repo/events.js'
import * as sessions from '../../src/repo/sessions.js'
import * as drivers from '../../src/repo/drivers.js'
import * as constructors from '../../src/repo/constructors.js'
import * as standings from '../../src/repo/standings.js'
import * as users from '../../src/repo/users.js'
import * as picks from '../../src/repo/preseasonPicks.js'
import * as scores from '../../src/repo/scores.js'
import { runTick } from '../../src/crawler/tick.js'

class FakeJolpica {
  async getRaceResults() {
    return {
      MRData: { RaceTable: { Races: [{
        season: '2026', round: '1', raceName: 'Bahrain',
        Results: [{
          position: '1',
          Driver: { driverId: 'VER', code: 'VER', givenName: 'M', familyName: 'V', nationality: 'NL', permanentNumber: '33', url: '' },
          Constructor: { constructorId: 'red_bull', name: 'Red Bull', nationality: 'A', url: '' },
          grid: '1', laps: '1', status: 'Finished', Time: { time: '1:00:00' }, points: '25'
        }]
      }] } }
    }
  }
  async getQualifyingResults() { return null }
  async getSprintResults() { return null }
  async getSprintQualifyingResults() { return null }
  async getDriverStandings() {
    return {
      MRData: { StandingsTable: { StandingsLists: [{
        DriverStandings: [{
          position: '1', points: '25', wins: '1',
          Driver: { driverId: 'VER', code: 'VER', givenName: 'M', familyName: 'V', nationality: 'NL', permanentNumber: '33', url: '' },
          Constructors: [{ constructorId: 'red_bull', name: 'Red Bull', nationality: 'A', url: '' }]
        }]
      }] } }
    }
  }
  async getConstructorStandings() {
    return {
      MRData: { StandingsTable: { StandingsLists: [{
        ConstructorStandings: [{
          position: '1', points: '25', wins: '1',
          Constructor: { constructorId: 'red_bull', name: 'Red Bull', nationality: 'A', url: '' }
        }]
      }] } }
    }
  }
}
class FakeWiki {
  async getImageUrl() { return null }
}

describe('tick triggers preseason rescore', () => {
  it('after standings refresh, preseason scores appear for predicting users', async () => {
    await seasons.upsertSeason({ year: 2026, isCurrent: true })
    const ev = await events.upsertEvent({ seasonYear: 2026, round: 1, name: 'B', circuitName: 'C', country: 'B', hasSprint: false })
    const ses = await sessions.upsertSession({
      eventId: ev.id, type: 'race',
      scheduledStart: new Date(Date.now() - 3 * 60 * 60 * 1000),
      scheduledEnd: new Date(Date.now() - 60 * 60 * 1000), status: 'scheduled'
    })
    await constructors.upsertConstructor({ id: 'red_bull', name: 'Red Bull', nationality: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null })
    await drivers.upsertDriver({ code: 'VER', givenName: 'M', familyName: 'V', nationality: null, permanentNumber: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null })
    await standings.replaceDriverStandings(2026, [{ driverCode: 'VER', position: 1, points: 0, wins: 0, constructorId: 'red_bull' }])

    const u = await users.insertUser({ email: 't@x.com', passwordHash: 'h', displayName: 'T' })
    await picks.upsertPick(u.id, 2026, 'wdc_wcc', { driverCode: 'VER', constructorId: 'red_bull' })

    const summary = await runTick(new FakeJolpica() as any, new FakeWiki() as any)
    expect(summary.errors).toBe(0)

    const list = await scores.listPreseasonForUser(u.id, 2026)
    expect(list).toHaveLength(7)
    expect(list.find((r) => r.category === 'wdc_wcc')!.pointsTotal).toBe(8)
  })
})
```

- [ ] **Step 7: Verify all tests pass**

```bash
cd /Users/anton/Dev/Projects/F1predictiongame/backend
set -a && source .env && set +a
npm test
npx tsc --noEmit
```
Expected: 6 new tests + everything prior; tsc clean.

- [ ] **Step 8: Commit**

```bash
cd /Users/anton/Dev/Projects/F1predictiongame
git add backend/src/preseason/rescorer.ts backend/src/crawler/tick.ts backend/src/repo/standings.ts backend/test/integration/preseason_rescorer.test.ts backend/test/integration/crawler_tick_preseason_rescore.test.ts
git commit -m "backend: preseason rescorer + tick integration"
```

---

### Task 7: Preseason routes

**Files:**
- Create: `backend/src/api/routes/preseason.ts`
- Modify: `backend/src/index.ts`
- Create: `backend/test/integration/api_preseason.test.ts`

7 endpoints:
- GET `/api/preseason/my`
- PUT/DELETE `/api/preseason/:category`
- PUT/DELETE `/api/preseason/standings/drivers`
- PUT/DELETE `/api/preseason/standings/constructors`
- GET `/api/seasons/:year/preseason-truth`
- GET `/api/users/me/preseason-scores`

Plus the lock helper logic.

- [ ] **Step 1: Implement `src/api/routes/preseason.ts`**

```ts
import type { FastifyInstance, FastifyRequest } from 'fastify'
import { z } from 'zod'
import { ApiError } from '../errors.js'
import { getCurrentUser, registerAuthHook } from '../auth-context.js'
import * as seasonsRepo from '../../repo/seasons.js'
import * as eventsRepo from '../../repo/events.js'
import * as sessionsRepo from '../../repo/sessions.js'
import * as driversRepo from '../../repo/drivers.js'
import * as constructorsRepo from '../../repo/constructors.js'
import * as standingsRepo from '../../repo/standings.js'
import * as picksRepo from '../../repo/preseasonPicks.js'
import * as preseasonStandingsRepo from '../../repo/preseasonStandings.js'
import * as truthRepo from '../../repo/subjectiveTruth.js'
import * as scoresRepo from '../../repo/scores.js'
import type { PreseasonCategory } from '../../domain/types.js'

const CATEGORIES: PreseasonCategory[] = ['surprise', 'disappointment', 'dnf', 'poles', 'fastest_lap', 'wdc_wcc']

const singlePickBody = z.object({
  driverCode: z.string().min(1).max(10).nullable().optional(),
  constructorId: z.string().min(1).max(50).nullable().optional()
}).refine((b) => (b.driverCode ?? null) !== null || (b.constructorId ?? null) !== null, {
  message: 'at least one of driverCode or constructorId must be provided'
})

const standingsBody = z.object({
  picks: z.array(z.object({
    position: z.number().int().min(1).max(50),
    driverCode: z.string().min(1).max(10).optional(),
    constructorId: z.string().min(1).max(50).optional()
  })).max(50)
})

function parse<T>(schema: z.ZodType<T>, body: unknown): T {
  const r = schema.safeParse(body)
  if (!r.success) throw new ApiError('VALIDATION', r.error.issues[0]?.message ?? 'Invalid request body')
  return r.data
}

function parseCategory(raw: string): PreseasonCategory {
  if (!CATEGORIES.includes(raw as PreseasonCategory)) {
    throw new ApiError('BAD_REQUEST', `Unknown category: ${raw}`)
  }
  return raw as PreseasonCategory
}

async function getPreseasonLockTime(seasonYear: number): Promise<Date | null> {
  const ev = await eventsRepo.getByRound(seasonYear, 1)
  if (!ev) return null
  const sessions = await sessionsRepo.listForEvent(ev.id)
  if (sessions.length === 0) return null
  return sessions.sort((a, b) => a.scheduledStart.getTime() - b.scheduledStart.getTime())[0]!.scheduledStart
}

async function requireQuestionnaireUnlocked(seasonYear: number): Promise<void> {
  const lockAt = await getPreseasonLockTime(seasonYear)
  if (lockAt && lockAt.getTime() <= Date.now()) {
    throw new ApiError('CONFLICT', 'Pre-season questionnaire is locked')
  }
}

async function requireQuestionnaireLocked(seasonYear: number): Promise<void> {
  const lockAt = await getPreseasonLockTime(seasonYear)
  if (!lockAt || lockAt.getTime() > Date.now()) {
    throw new ApiError('FORBIDDEN', 'Other users\' picks are visible only after lock')
  }
}

async function getCurrentSeasonYear(): Promise<number> {
  const cur = await seasonsRepo.getCurrent()
  if (!cur) throw new ApiError('NOT_FOUND', 'No current season')
  return cur.year
}

async function validateSinglePick(seasonYear: number, body: { driverCode?: string | null; constructorId?: string | null }): Promise<void> {
  if (body.driverCode) {
    if (!(await driversRepo.exists(body.driverCode))) throw new ApiError('VALIDATION', `Unknown driver: ${body.driverCode}`)
    if (!(await standingsRepo.driverHasStandingForYear(body.driverCode, seasonYear))) {
      throw new ApiError('VALIDATION', `Driver ${body.driverCode} not in season ${seasonYear}`)
    }
  }
  if (body.constructorId) {
    if (!(await constructorsRepo.exists(body.constructorId))) throw new ApiError('VALIDATION', `Unknown constructor: ${body.constructorId}`)
    if (!(await standingsRepo.constructorHasStandingForYear(body.constructorId, seasonYear))) {
      throw new ApiError('VALIDATION', `Constructor ${body.constructorId} not in season ${seasonYear}`)
    }
  }
}

export async function registerPreseasonRoutes(app: FastifyInstance): Promise<void> {
  registerAuthHook(app)

  app.get('/api/preseason/my', async (req) => {
    const u = getCurrentUser(req)
    const year = await getCurrentSeasonYear()
    const lockAt = await getPreseasonLockTime(year)
    const allPicks = await picksRepo.listForUser(u.id, year)
    const byCategory = new Map(allPicks.map((p) => [p.category, p]))
    const driverPicks = await preseasonStandingsRepo.listDriverPicks(u.id, year)
    const constructorPicks = await preseasonStandingsRepo.listConstructorPicks(u.id, year)
    return {
      seasonYear: year,
      isLocked: lockAt !== null && lockAt.getTime() <= Date.now(),
      locksAt: lockAt,
      surprise:       byCategory.get('surprise')       ?? null,
      disappointment: byCategory.get('disappointment') ?? null,
      dnf:            byCategory.get('dnf')            ?? null,
      poles:          byCategory.get('poles')          ?? null,
      fastest_lap:    byCategory.get('fastest_lap')    ?? null,
      wdc_wcc:        byCategory.get('wdc_wcc')        ?? null,
      standings: {
        drivers: driverPicks,
        constructors: constructorPicks
      }
    }
  })

  app.put<{ Params: { category: string } }>('/api/preseason/:category', async (req) => {
    const u = getCurrentUser(req)
    const year = await getCurrentSeasonYear()
    const cat = parseCategory(req.params.category)
    const body = parse(singlePickBody, req.body)
    await requireQuestionnaireUnlocked(year)
    await validateSinglePick(year, body)
    const pick = await picksRepo.upsertPick(u.id, year, cat, {
      driverCode: body.driverCode ?? null,
      constructorId: body.constructorId ?? null
    })
    return { pick }
  })

  app.delete<{ Params: { category: string } }>('/api/preseason/:category', async (req) => {
    const u = getCurrentUser(req)
    const year = await getCurrentSeasonYear()
    const cat = parseCategory(req.params.category)
    await requireQuestionnaireUnlocked(year)
    await picksRepo.deletePick(u.id, year, cat)
    return { ok: true }
  })

  app.put('/api/preseason/standings/drivers', async (req) => {
    const u = getCurrentUser(req)
    const year = await getCurrentSeasonYear()
    const body = parse(standingsBody, req.body)
    await requireQuestionnaireUnlocked(year)
    const picks: { position: number; entityId: string }[] = body.picks.map((p) => {
      if (!p.driverCode) throw new ApiError('VALIDATION', 'each pick requires driverCode')
      return { position: p.position, entityId: p.driverCode }
    })
    // positions form [1..N]
    const positions = picks.map((p) => p.position).sort((a, b) => a - b)
    for (let i = 0; i < positions.length; i++) {
      if (positions[i] !== i + 1) throw new ApiError('VALIDATION', 'positions must be a contiguous 1..N range')
    }
    const driverSet = new Set(picks.map((p) => p.entityId))
    if (driverSet.size !== picks.length) throw new ApiError('VALIDATION', 'duplicate driver in standings picks')
    for (const p of picks) {
      if (!(await driversRepo.exists(p.entityId))) throw new ApiError('VALIDATION', `Unknown driver: ${p.entityId}`)
      if (!(await standingsRepo.driverHasStandingForYear(p.entityId, year))) {
        throw new ApiError('VALIDATION', `Driver ${p.entityId} not in season ${year}`)
      }
    }
    await preseasonStandingsRepo.replaceDriverPicks(u.id, year, picks)
    return { picks }
  })

  app.put('/api/preseason/standings/constructors', async (req) => {
    const u = getCurrentUser(req)
    const year = await getCurrentSeasonYear()
    const body = parse(standingsBody, req.body)
    await requireQuestionnaireUnlocked(year)
    const picks: { position: number; entityId: string }[] = body.picks.map((p) => {
      if (!p.constructorId) throw new ApiError('VALIDATION', 'each pick requires constructorId')
      return { position: p.position, entityId: p.constructorId }
    })
    const positions = picks.map((p) => p.position).sort((a, b) => a - b)
    for (let i = 0; i < positions.length; i++) {
      if (positions[i] !== i + 1) throw new ApiError('VALIDATION', 'positions must be a contiguous 1..N range')
    }
    const teamSet = new Set(picks.map((p) => p.entityId))
    if (teamSet.size !== picks.length) throw new ApiError('VALIDATION', 'duplicate constructor in standings picks')
    for (const p of picks) {
      if (!(await constructorsRepo.exists(p.entityId))) throw new ApiError('VALIDATION', `Unknown constructor: ${p.entityId}`)
      if (!(await standingsRepo.constructorHasStandingForYear(p.entityId, year))) {
        throw new ApiError('VALIDATION', `Constructor ${p.entityId} not in season ${year}`)
      }
    }
    await preseasonStandingsRepo.replaceConstructorPicks(u.id, year, picks)
    return { picks }
  })

  app.delete('/api/preseason/standings/drivers', async (req) => {
    const u = getCurrentUser(req)
    const year = await getCurrentSeasonYear()
    await requireQuestionnaireUnlocked(year)
    await preseasonStandingsRepo.replaceDriverPicks(u.id, year, [])
    return { ok: true }
  })

  app.delete('/api/preseason/standings/constructors', async (req) => {
    const u = getCurrentUser(req)
    const year = await getCurrentSeasonYear()
    await requireQuestionnaireUnlocked(year)
    await preseasonStandingsRepo.replaceConstructorPicks(u.id, year, [])
    return { ok: true }
  })

  app.get<{ Params: { year: string } }>('/api/seasons/:year/preseason-truth', async (req) => {
    const year = Number(req.params.year)
    if (!Number.isFinite(year)) throw new ApiError('BAD_REQUEST', 'year must be a number')
    await requireQuestionnaireLocked(year)
    const subjective = await truthRepo.getTruth(year)
    return { seasonYear: year, subjective }
  })

  app.get('/api/users/me/preseason-scores', async (req) => {
    const u = getCurrentUser(req)
    const year = await getCurrentSeasonYear()
    const scores = await scoresRepo.listPreseasonForUser(u.id, year)
    return { scores, seasonYear: year }
  })
}
```

- [ ] **Step 2: Add `constructorHasStandingForYear` to standings repo**

Open `backend/src/repo/standings.ts`. Add:

```ts
export async function constructorHasStandingForYear(constructorId: string, seasonYear: number): Promise<boolean> {
  const db = getDb()
  const rows = await db.select({ c: constructorStanding.constructorId })
    .from(constructorStanding)
    .where(and(eq(constructorStanding.constructorId, constructorId), eq(constructorStanding.seasonYear, seasonYear)))
    .limit(1)
  return rows.length > 0
}
```

(Match imports already added in earlier sub-projects.)

- [ ] **Step 3: Register routes in `src/index.ts`**

Add import alongside other route imports:
```ts
import { registerPreseasonRoutes } from './api/routes/preseason.js'
```

Inside `buildApp`, after `await app.register(registerLeaderboardRoutes)`:
```ts
await app.register(registerPreseasonRoutes)
```

- [ ] **Step 4: Write tests**

Create `backend/test/integration/api_preseason.test.ts`:

```ts
import { describe, it, expect } from 'vitest'
import { buildApp } from '../../src/index.js'
import * as seasons from '../../src/repo/seasons.js'
import * as events from '../../src/repo/events.js'
import * as sessions from '../../src/repo/sessions.js'
import * as drivers from '../../src/repo/drivers.js'
import * as constructors from '../../src/repo/constructors.js'
import * as standings from '../../src/repo/standings.js'

async function seedFuture() {
  await seasons.upsertSeason({ year: 2026, isCurrent: true })
  for (const c of ['red_bull', 'mercedes', 'mclaren']) {
    await constructors.upsertConstructor({ id: c, name: c, nationality: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null })
  }
  for (const code of ['VER', 'HAM', 'NOR']) {
    await drivers.upsertDriver({ code, givenName: code, familyName: 'X', nationality: null, permanentNumber: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null })
  }
  await standings.replaceDriverStandings(2026, [
    { driverCode: 'VER', position: 1, points: 0, wins: 0, constructorId: 'red_bull' },
    { driverCode: 'HAM', position: 2, points: 0, wins: 0, constructorId: 'mercedes' },
    { driverCode: 'NOR', position: 3, points: 0, wins: 0, constructorId: 'mclaren' }
  ])
  await standings.replaceConstructorStandings(2026, [
    { constructorId: 'red_bull', position: 1, points: 0, wins: 0 },
    { constructorId: 'mercedes', position: 2, points: 0, wins: 0 },
    { constructorId: 'mclaren',  position: 3, points: 0, wins: 0 }
  ])
  const ev = await events.upsertEvent({ seasonYear: 2026, round: 1, name: 'B', circuitName: 'C', country: 'X', hasSprint: false })
  // Lock in the future
  await sessions.upsertSession({
    eventId: ev.id, type: 'fp1',
    scheduledStart: new Date(Date.now() + 24 * 60 * 60 * 1000),
    scheduledEnd: new Date(Date.now() + 25 * 60 * 60 * 1000), status: 'scheduled'
  })
}

async function seedPast() {
  await seedFuture()
  const ev = await events.getByRound(2026, 1)
  // Add an FP1 in the past instead
  await sessions.upsertSession({
    eventId: ev!.id, type: 'fp1',
    scheduledStart: new Date(Date.now() - 60 * 60 * 1000),
    scheduledEnd: new Date(Date.now() - 30 * 60 * 1000), status: 'scheduled'
  })
}

async function buildAndUser() {
  const a = await buildApp({ scheduler: null })
  const r = await a.inject({ method: 'POST', url: '/api/auth/signup', payload: { email: `u-${Date.now()}@x.com`, password: 'hunter22', displayName: 'U' } })
  return { app: a, token: r.json().token as string }
}

const auth = (t: string) => ({ authorization: `Bearer ${t}` })

describe('PUT /api/preseason/:category', () => {
  it('submits a single-pick category', async () => {
    await seedFuture()
    const { app, token } = await buildAndUser()
    const res = await app.inject({
      method: 'PUT', url: '/api/preseason/wdc_wcc', headers: auth(token),
      payload: { driverCode: 'VER', constructorId: 'red_bull' }
    })
    expect(res.statusCode).toBe(200)
    expect(res.json().pick.driverCode).toBe('VER')
  })

  it('accepts driver-only pick', async () => {
    await seedFuture()
    const { app, token } = await buildAndUser()
    const res = await app.inject({
      method: 'PUT', url: '/api/preseason/poles', headers: auth(token),
      payload: { driverCode: 'VER' }
    })
    expect(res.statusCode).toBe(200)
    expect(res.json().pick.constructorId).toBeNull()
  })

  it('rejects with 422 when neither driver nor team provided', async () => {
    await seedFuture()
    const { app, token } = await buildAndUser()
    const res = await app.inject({
      method: 'PUT', url: '/api/preseason/poles', headers: auth(token),
      payload: {}
    })
    expect(res.statusCode).toBe(422)
  })

  it('rejects unknown category with 400', async () => {
    await seedFuture()
    const { app, token } = await buildAndUser()
    const res = await app.inject({
      method: 'PUT', url: '/api/preseason/bogus', headers: auth(token),
      payload: { driverCode: 'VER' }
    })
    expect(res.statusCode).toBe(400)
  })

  it('rejects driver not in season with 422', async () => {
    await seedFuture()
    const { app, token } = await buildAndUser()
    await drivers.upsertDriver({ code: 'OLD', givenName: 'O', familyName: 'X', nationality: null, permanentNumber: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null })
    const res = await app.inject({
      method: 'PUT', url: '/api/preseason/dnf', headers: auth(token),
      payload: { driverCode: 'OLD' }
    })
    expect(res.statusCode).toBe(422)
  })

  it('409 after lock', async () => {
    await seedPast()
    const { app, token } = await buildAndUser()
    const res = await app.inject({
      method: 'PUT', url: '/api/preseason/wdc_wcc', headers: auth(token),
      payload: { driverCode: 'VER' }
    })
    expect(res.statusCode).toBe(409)
  })
})

describe('PUT /api/preseason/standings/drivers', () => {
  it('accepts a [1..N] driver ordering', async () => {
    await seedFuture()
    const { app, token } = await buildAndUser()
    const res = await app.inject({
      method: 'PUT', url: '/api/preseason/standings/drivers', headers: auth(token),
      payload: { picks: [
        { position: 1, driverCode: 'VER' },
        { position: 2, driverCode: 'HAM' },
        { position: 3, driverCode: 'NOR' }
      ] }
    })
    expect(res.statusCode).toBe(200)
    expect(res.json().picks).toHaveLength(3)
  })

  it('rejects gap in positions', async () => {
    await seedFuture()
    const { app, token } = await buildAndUser()
    const res = await app.inject({
      method: 'PUT', url: '/api/preseason/standings/drivers', headers: auth(token),
      payload: { picks: [
        { position: 1, driverCode: 'VER' },
        { position: 3, driverCode: 'HAM' }
      ] }
    })
    expect(res.statusCode).toBe(422)
  })

  it('rejects duplicate driver', async () => {
    await seedFuture()
    const { app, token } = await buildAndUser()
    const res = await app.inject({
      method: 'PUT', url: '/api/preseason/standings/drivers', headers: auth(token),
      payload: { picks: [
        { position: 1, driverCode: 'VER' },
        { position: 2, driverCode: 'VER' }
      ] }
    })
    expect(res.statusCode).toBe(422)
  })
})

describe('GET /api/preseason/my', () => {
  it('returns the complete questionnaire state', async () => {
    await seedFuture()
    const { app, token } = await buildAndUser()
    await app.inject({ method: 'PUT', url: '/api/preseason/wdc_wcc', headers: auth(token), payload: { driverCode: 'VER', constructorId: 'red_bull' } })
    const res = await app.inject({ method: 'GET', url: '/api/preseason/my', headers: auth(token) })
    expect(res.statusCode).toBe(200)
    expect(res.json().wdc_wcc.driverCode).toBe('VER')
    expect(res.json().surprise).toBeNull()
    expect(res.json().isLocked).toBe(false)
    expect(res.json().locksAt).not.toBeNull()
  })
})

describe('DELETE /api/preseason/:category', () => {
  it('removes the pick before lock', async () => {
    await seedFuture()
    const { app, token } = await buildAndUser()
    await app.inject({ method: 'PUT', url: '/api/preseason/dnf', headers: auth(token), payload: { driverCode: 'VER' } })
    const del = await app.inject({ method: 'DELETE', url: '/api/preseason/dnf', headers: auth(token) })
    expect(del.statusCode).toBe(200)
    const my = await app.inject({ method: 'GET', url: '/api/preseason/my', headers: auth(token) })
    expect(my.json().dnf).toBeNull()
  })
})

describe('GET /api/seasons/:year/preseason-truth', () => {
  it('403 before lock', async () => {
    await seedFuture()
    const { app, token } = await buildAndUser()
    const res = await app.inject({ method: 'GET', url: '/api/seasons/2026/preseason-truth', headers: auth(token) })
    expect(res.statusCode).toBe(403)
  })

  it('200 after lock returns null subjective initially', async () => {
    await seedPast()
    const { app, token } = await buildAndUser()
    const res = await app.inject({ method: 'GET', url: '/api/seasons/2026/preseason-truth', headers: auth(token) })
    expect(res.statusCode).toBe(200)
    expect(res.json().subjective).toBeNull()
  })
})
```

- [ ] **Step 5: Verify tests pass**

```bash
cd /Users/anton/Dev/Projects/F1predictiongame/backend
set -a && source .env && set +a
npx vitest run test/integration/api_preseason.test.ts
npm test
npx tsc --noEmit
```
Expected: 12 new route tests pass; full suite green; tsc clean.

- [ ] **Step 6: Commit**

```bash
cd /Users/anton/Dev/Projects/F1predictiongame
git add backend/src/api/routes/preseason.ts backend/src/repo/standings.ts backend/src/index.ts backend/test/integration/api_preseason.test.ts
git commit -m "backend: /api/preseason/* routes + lock helper"
```

---

### Task 8: Admin endpoints + factories + README + final verify

**Files:**
- Modify: `backend/src/api/routes/admin.ts`
- Modify: `backend/test/helpers/factories.ts`
- Modify: `backend/README.md`
- Create: `backend/test/integration/api_admin_subjective_truth.test.ts`

- [ ] **Step 1: Extend admin routes**

In `backend/src/api/routes/admin.ts`, add imports:

```ts
import { z } from 'zod'
import * as truthRepo from '../../repo/subjectiveTruth.js'
import { rescorePreseasonForSeason } from '../../preseason/rescorer.js'
```

Inside `registerAdminRoutes`, after the existing endpoints, add:

```ts
  const truthBody = z.object({
    surpriseDriverCode: z.string().min(1).max(10).nullable(),
    surpriseConstructorId: z.string().min(1).max(50).nullable(),
    disappointmentDriverCode: z.string().min(1).max(10).nullable(),
    disappointmentConstructorId: z.string().min(1).max(50).nullable()
  })

  app.post<{ Params: { year: string } }>('/admin/seasons/:year/subjective-truth', async (req) => {
    const year = Number(req.params.year)
    if (!Number.isFinite(year)) throw new ApiError('BAD_REQUEST', 'year must be a number')
    const parsed = truthBody.safeParse(req.body)
    if (!parsed.success) throw new ApiError('VALIDATION', parsed.error.issues[0]?.message ?? 'Invalid body')
    await truthRepo.upsertTruth(year, parsed.data)
    const summary = await rescorePreseasonForSeason(year)
    return { ok: true, year, ...summary }
  })

  app.post<{ Params: { year: string } }>('/admin/preseason-rescore/:year', async (req) => {
    const year = Number(req.params.year)
    if (!Number.isFinite(year)) throw new ApiError('BAD_REQUEST', 'year must be a number')
    const summary = await rescorePreseasonForSeason(year)
    return { ok: true, year, ...summary }
  })
```

- [ ] **Step 2: Add admin tests**

Create `backend/test/integration/api_admin_subjective_truth.test.ts`:

```ts
import { describe, it, expect } from 'vitest'
import { buildApp } from '../../src/index.js'
import * as seasons from '../../src/repo/seasons.js'
import * as drivers from '../../src/repo/drivers.js'
import * as constructors from '../../src/repo/constructors.js'
import * as users from '../../src/repo/users.js'
import * as picks from '../../src/repo/preseasonPicks.js'
import * as scores from '../../src/repo/scores.js'

const TOKEN = { 'x-admin-token': 'local-dev-token' }

async function seed() {
  await seasons.upsertSeason({ year: 2026, isCurrent: true })
  await constructors.upsertConstructor({ id: 'red_bull', name: 'Red Bull', nationality: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null })
  await drivers.upsertDriver({ code: 'VER', givenName: 'M', familyName: 'V', nationality: null, permanentNumber: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null })
}

describe('POST /admin/seasons/:year/subjective-truth', () => {
  it('requires admin token', async () => {
    await seed()
    const app = await buildApp({ scheduler: null })
    const r = await app.inject({
      method: 'POST', url: '/admin/seasons/2026/subjective-truth',
      payload: { surpriseDriverCode: null, surpriseConstructorId: null, disappointmentDriverCode: null, disappointmentConstructorId: null }
    })
    expect(r.statusCode).toBe(401)
  })

  it('sets truth and triggers rescore (surprise score updates)', async () => {
    await seed()
    const app = await buildApp({ scheduler: null })
    const u = await users.insertUser({ email: 'a@x.com', passwordHash: 'h', displayName: 'A' })
    await picks.upsertPick(u.id, 2026, 'surprise', { driverCode: 'VER', constructorId: 'red_bull' })

    // Before truth: rescore yields 0
    let scoreList = await scores.listPreseasonForUser(u.id, 2026)
    const before = scoreList.find((s) => s.category === 'surprise')
    // (the rescore may not have run yet if no tick happened; we run admin first)

    const r = await app.inject({
      method: 'POST', url: '/admin/seasons/2026/subjective-truth',
      headers: TOKEN,
      payload: {
        surpriseDriverCode: 'VER',
        surpriseConstructorId: 'red_bull',
        disappointmentDriverCode: null,
        disappointmentConstructorId: null
      }
    })
    expect(r.statusCode).toBe(200)
    expect(r.json().ok).toBe(true)

    scoreList = await scores.listPreseasonForUser(u.id, 2026)
    expect(scoreList.find((s) => s.category === 'surprise')!.pointsTotal).toBe(8)
  })
})

describe('POST /admin/preseason-rescore/:year', () => {
  it('forces rescore', async () => {
    await seed()
    const app = await buildApp({ scheduler: null })
    const u = await users.insertUser({ email: 'r@x.com', passwordHash: 'h', displayName: 'R' })
    await picks.upsertPick(u.id, 2026, 'wdc_wcc', { driverCode: 'VER', constructorId: 'red_bull' })
    const r = await app.inject({ method: 'POST', url: '/admin/preseason-rescore/2026', headers: TOKEN })
    expect(r.statusCode).toBe(200)
    expect(r.json().users).toBeGreaterThanOrEqual(0)
  })
})
```

- [ ] **Step 3: Add factories**

Append to `backend/test/helpers/factories.ts`:

```ts
import * as preseasonPicks from '../../src/repo/preseasonPicks.js'
import * as preseasonStandingsRepo from '../../src/repo/preseasonStandings.js'
import * as subjectiveTruthRepo from '../../src/repo/subjectiveTruth.js'
import type { PreseasonCategory } from '../../src/domain/types.js'

export async function makePreseasonPick(
  userId: string,
  seasonYear: number,
  category: PreseasonCategory,
  values: { driverCode?: string | null; constructorId?: string | null } = {}
) {
  return preseasonPicks.upsertPick(userId, seasonYear, category, {
    driverCode: values.driverCode ?? null,
    constructorId: values.constructorId ?? null
  })
}

export async function makePreseasonStandings(
  userId: string,
  seasonYear: number,
  kind: 'driver' | 'constructor',
  orderedIds: string[]
) {
  const picks = orderedIds.map((id, i) => ({ position: i + 1, entityId: id }))
  if (kind === 'driver') return preseasonStandingsRepo.replaceDriverPicks(userId, seasonYear, picks)
  return preseasonStandingsRepo.replaceConstructorPicks(userId, seasonYear, picks)
}

export async function setSubjectiveTruth(
  seasonYear: number,
  fields: Partial<{
    surpriseDriverCode: string
    surpriseConstructorId: string
    disappointmentDriverCode: string
    disappointmentConstructorId: string
  }>
) {
  return subjectiveTruthRepo.upsertTruth(seasonYear, {
    surpriseDriverCode: fields.surpriseDriverCode ?? null,
    surpriseConstructorId: fields.surpriseConstructorId ?? null,
    disappointmentDriverCode: fields.disappointmentDriverCode ?? null,
    disappointmentConstructorId: fields.disappointmentConstructorId ?? null
  })
}
```

- [ ] **Step 4: Update `backend/README.md`**

Read existing README. Then:

**a)** Append to the API table (after the existing rows):

```
| GET  | `/api/preseason/my` | Caller's full questionnaire state (bearer) |
| PUT  | `/api/preseason/:category` | Submit/replace single-pick category (bearer; 409 after lock) |
| DELETE | `/api/preseason/:category` | Remove caller's pick (bearer; 409 after lock) |
| PUT  | `/api/preseason/standings/drivers` | Full driver ordering (bearer; 409 after lock) |
| PUT  | `/api/preseason/standings/constructors` | Full constructor ordering (bearer; 409 after lock) |
| DELETE | `/api/preseason/standings/drivers` | Clear driver ordering (bearer; 409 after lock) |
| DELETE | `/api/preseason/standings/constructors` | Clear constructor ordering (bearer; 409 after lock) |
| GET  | `/api/seasons/:year/preseason-truth` | Observed + subjective truth + everyone's picks (bearer; only after lock) |
| GET  | `/api/users/me/preseason-scores` | Caller's preseason scores for current season (bearer) |
| POST | `/admin/seasons/:year/subjective-truth` | Set 4 subjective picks; triggers rescore (token-gated) |
| POST | `/admin/preseason-rescore/:year` | Force preseason rescore (token-gated) |
```

**b)** After the existing "Scoring" section, append a "Pre-season scoring" section:

```
## Pre-season scoring

Each user submits a pre-season questionnaire that locks at the first session of round 1.
Categories and points:

| Category | Picks | Points | Max |
|---|---|---|---|
| Biggest surprise | 1 driver + 1 team | 4 each match | 8 |
| Biggest disappointment | 1 driver + 1 team | 4 each match | 8 |
| Most DNFs | 1 driver + 1 team | 4 each match | 8 |
| Most poles | 1 driver + 1 team | 4 each match | 8 |
| Most fastest laps | 1 driver + 1 team | 4 each match | 8 |
| WDC + WCC | 1 driver + 1 team | 4 each match | 8 |
| Complete championship | ~20 drivers + ~10 teams ordered | 3 per correct driver + 4 per correct team | 100 |

Surprise + disappointment are subjective — admin sets them at season end via
`POST /admin/seasons/:year/subjective-truth`. All other categories derive from
the crawled F1 data (DNFs from `status`, poles from qualifying, FLs from
`fastest_lap`, WDC/WCC + full standings from the standings tables).

The crawler auto-rescores preseason after every standings refresh.
```

**c)** Update the "What's NOT in this sub-project" section to remove "pre-season questionnaire" — only "Flutter UI changes" remains as deferred (and that's a parallel track, not really a backend deferral).

- [ ] **Step 5: Run the full test suite**

```bash
cd /Users/anton/Dev/Projects/F1predictiongame/backend
set -a && source .env && set +a
npm test
npx tsc --noEmit
```
Expected: all tests pass; tsc clean.

- [ ] **Step 6: Manual smoke test (optional)**

If the dev server is running:

```bash
TOKEN=$(curl -s -X POST http://localhost:3000/api/auth/signup \
  -H 'content-type: application/json' \
  -d '{"email":"sp4@x.com","password":"hunter22","displayName":"SP4"}' | jq -r .token)

curl -s -X PUT http://localhost:3000/api/preseason/wdc_wcc \
  -H "authorization: Bearer $TOKEN" -H 'content-type: application/json' \
  -d '{"driverCode":"VER","constructorId":"red_bull"}' | jq

curl -s -H "authorization: Bearer $TOKEN" http://localhost:3000/api/preseason/my | jq '.wdc_wcc, .isLocked'
```
Expected: 200 responses with reasonable JSON. Skip if dev server isn't running.

- [ ] **Step 7: Commit**

```bash
cd /Users/anton/Dev/Projects/F1predictiongame
git add backend/src/api/routes/admin.ts backend/test/helpers/factories.ts backend/README.md backend/test/integration/api_admin_subjective_truth.test.ts
git commit -m "backend: admin endpoints + factories + README for preseason"
```

---

## Done

All 8 tasks complete means:

- 3 new tables + score-table modifications applied (migration 0004)
- 6 pure scorers consolidated into one shared module + 1 standings scorer + dispatcher
- 5 derive functions for observed truth
- 3 new repos for picks/standings/subjective-truth, plus score-table updates
- Rescorer wired into tick after standings refresh
- 11 new endpoints (7 questionnaire + 1 truth view + 1 score view + 2 admin)
- Full test suite green; tsc clean
- README documents new endpoints + preseason scoring scheme

The backend rebuild (4 sub-projects) is complete. Only the Flutter UI redesign remains as a parallel track.
