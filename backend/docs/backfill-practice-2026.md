# Backfilling 2026 practice results — production runbook

`src/scripts/backfillPractice.ts` walks every FP1/FP2/FP3 row for a season,
fetches the classification from OpenF1, and persists it. It is the one-shot
companion to the code change that made FP sessions tick-eligible
(`listCandidates` no longer excludes them). After this script runs, ongoing
ticks pick up new FP results automatically every cycle.

It is **additive and idempotent**:
- `resultsRepo.replaceForSession` overwrites any prior rows for the same
  session_id (no duplicates).
- `sessionsRepo.markFinished` is a status update — re-runs are a no-op.
- Drivers / constructors are upserted only when genuinely new; existing
  image URLs and overrides are preserved.

Practice is **not scored** — `EXPECTED_PICKS` in `src/scoring/index.ts`
omits FP types, so `rescoreSession` short-circuits. No leaderboards or
existing predictions are touched.

## Prerequisites

- The **production** `DATABASE_URL` (Render → `f1pg-db` → connection string).
- `cd backend && npm ci`.
- The 2026 season already bootstrapped (events + sessions present in DB
  with their OpenF1 session keys mapped). The script re-runs
  `mapSessionsToOpenF1(2026)` as its first step in case any FP rows are
  missing a key.

The script talks to the DB directly — it does not need the deployed server.

## Step 1 — dry run (no writes)

The Render `DATABASE_URL` needs `?uselibpqcompat=true&sslmode=require`
appended — bare `sslmode=require` is now treated as `verify-full` by
node-postgres and fails handshake against Render's chain. The backend
config schema also requires `ADMIN_TOKEN` to be set (any non-empty value)
even though this script never calls a protected endpoint.

```bash
cd backend
DATABASE_URL='<PROD_DATABASE_URL>?uselibpqcompat=true&sslmode=require' \
  NODE_ENV=production ADMIN_TOKEN=backfill \
  npx tsx src/scripts/backfillPractice.ts 2026 --dry
```

Expected output:
- one `refreshing OpenF1 session-key mapping…` line,
- one line per FP session in the season, either:
  - `round=N fpX: would persist 20 rows (P1=VER 1:18.234)` for finished sessions, or
  - `round=N fpX: no OpenF1 result (key=…)` for sessions that haven't run yet,
- a final `done. attempted=N wouldPersist=M skipped=K errors=0` summary.

Confirm `errors=0` and `wouldPersist` matches the number of FP sessions you
expect to have completed so far in 2026.

## Step 2 — apply

```bash
cd backend
DATABASE_URL='<PROD_DATABASE_URL>?uselibpqcompat=true&sslmode=require' \
  NODE_ENV=production ADMIN_TOKEN=backfill \
  npx tsx src/scripts/backfillPractice.ts 2026
```

Same output, but `wouldPersist` becomes `persisted`. Expect `errors=0`.

## Step 3 — verify

Spot-check one event in the app: open the prediction screen on an upcoming
race or qualifying session, confirm:
- the driver tiles show times,
- the "TIMES · FP3 (Fri)" chip in the DRIVERS row taps through to the FP3
  classification.

Or via SQL:

```sql
SELECT s.type, count(sr.*) AS rows
FROM session s
JOIN event e ON e.id = s.event_id
JOIN season y ON y.id = e.season_id
LEFT JOIN session_result sr ON sr.session_id = s.id
WHERE y.year = 2026 AND s.type IN ('fp1','fp2','fp3')
GROUP BY s.type
ORDER BY s.type;
```

Each row count should be ~20 × (events with that practice session having
been run). Zero rows for an FP session that has run is a red flag.

## Rollback

The script only inserts/replaces FP session_result rows and marks FP
sessions as `finished`. To undo:

```sql
BEGIN;
DELETE FROM session_result
WHERE session_id IN (
  SELECT s.id FROM session s
  JOIN event e ON e.id = s.event_id
  JOIN season y ON y.id = e.season_id
  WHERE y.year = 2026 AND s.type IN ('fp1','fp2','fp3')
);
UPDATE session s
SET status = 'scheduled'
FROM event e JOIN season y ON y.id = e.season_id
WHERE s.event_id = e.id AND y.year = 2026
  AND s.type IN ('fp1','fp2','fp3');
COMMIT;
```

Predictions, scoring, and non-FP results are untouched by either the
backfill or the rollback.
