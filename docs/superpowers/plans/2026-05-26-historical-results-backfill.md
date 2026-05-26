# Historical Results Backfill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the crawler eventually fetch results for every past `race` / `qualifying` / `sprint` session, while keeping the existing 7-day cap on `sprint_quali` (its Jolpica endpoint is permanently unavailable). Then run a one-time tick to catch up rounds 1–4 of the current 2026 season.

**Architecture:** Single targeted change to `listCandidates()` in `backend/src/repo/sessions.ts`: the 7-day floor becomes type-conditional, applying only to `sprint_quali`. No schema, no new endpoint, no call-site changes. The existing 15-minute scheduler picks up the wider candidate pool automatically; one manual `make crawl` after deploying the change clears the existing backlog.

**Tech Stack:** Node 22, TypeScript, Drizzle ORM, Postgres 16, Fastify, vitest. Backend lives in `backend/`; tests are vitest with a single-fork Postgres container.

**Spec:** `docs/superpowers/specs/2026-05-26-historical-results-backfill-design.md`

---

## File Structure

- **Modify:** `backend/src/repo/sessions.ts` — change one `where` clause in `listCandidates()`.
- **Modify:** `backend/test/integration/repo_sessions_results.test.ts` — update one existing assertion that pinned the old behavior; add new tests for the type-conditional cap.

That's the entire code surface. Operational tasks (starting the backend, crawling) come after the code change is green.

---

## Task 1: Update tests to pin the new behavior

The existing integration test at `backend/test/integration/repo_sessions_results.test.ts` currently asserts that a `race` session ending 8 days ago is excluded from candidates. Under the new design that's wrong — only `sprint_quali` is capped. We replace that test and add coverage for the new conditional.

**Files:**
- Modify: `backend/test/integration/repo_sessions_results.test.ts` — lines 52–59 (the `'excludes sessions whose end is more than 7 days in the past'` test).

- [ ] **Step 1: Read the existing test block once for context**

Open `backend/test/integration/repo_sessions_results.test.ts`. Note the test on lines 52–59 — it must change because race / qualifying / sprint are no longer capped. Note also the helper `seed()` at the top of the file; it creates a 2024 season + a round-1 event and returns the event row. Each test gets a fresh DB because `test/helpers/setup.ts` truncates in `beforeEach`.

- [ ] **Step 2: Replace the old 7-day-exclusion test and add new conditional-cap tests**

In `backend/test/integration/repo_sessions_results.test.ts`, find this exact block (lines 52–59):

```ts
  it('excludes sessions whose end is more than 7 days in the past', async () => {
    const ev = await seed()
    const longAgo = new Date(Date.now() - 8 * 24 * 60 * 60 * 1000)
    await sessions.upsertSession({
      eventId: ev.id, type: 'race', scheduledStart: longAgo, scheduledEnd: longAgo, status: 'scheduled'
    })
    expect(await sessions.listCandidates()).toEqual([])
  })
```

Replace it with these four tests (paste them as a single block in place of the one above):

```ts
  it('includes race / qualifying / sprint sessions whose end is more than 7 days in the past', async () => {
    const ev = await seed()
    const longAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000)
    await sessions.upsertSession({
      eventId: ev.id, type: 'race', scheduledStart: longAgo, scheduledEnd: longAgo, status: 'scheduled'
    })
    await sessions.upsertSession({
      eventId: ev.id, type: 'qualifying', scheduledStart: longAgo, scheduledEnd: longAgo, status: 'scheduled'
    })
    await sessions.upsertSession({
      eventId: ev.id, type: 'sprint', scheduledStart: longAgo, scheduledEnd: longAgo, status: 'scheduled'
    })
    const types = (await sessions.listCandidates()).map((c) => c.type).sort()
    expect(types).toEqual(['qualifying', 'race', 'sprint'])
  })

  it('excludes sprint_quali sessions whose end is more than 7 days in the past', async () => {
    const ev = await seed()
    const longAgo = new Date(Date.now() - 8 * 24 * 60 * 60 * 1000)
    await sessions.upsertSession({
      eventId: ev.id, type: 'sprint_quali', scheduledStart: longAgo, scheduledEnd: longAgo, status: 'scheduled'
    })
    expect(await sessions.listCandidates()).toEqual([])
  })

  it('includes sprint_quali sessions whose end is within the last 7 days', async () => {
    const ev = await seed()
    const recent = new Date(Date.now() - 2 * 24 * 60 * 60 * 1000)
    await sessions.upsertSession({
      eventId: ev.id, type: 'sprint_quali', scheduledStart: recent, scheduledEnd: recent, status: 'scheduled'
    })
    const candidates = await sessions.listCandidates()
    expect(candidates.map((c) => c.type)).toEqual(['sprint_quali'])
  })

  it('still excludes finished past sessions from candidates', async () => {
    const ev = await seed()
    const longAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000)
    const ses = await sessions.upsertSession({
      eventId: ev.id, type: 'race', scheduledStart: longAgo, scheduledEnd: longAgo, status: 'scheduled'
    })
    await sessions.markFinished(ses.id!)
    expect(await sessions.listCandidates()).toEqual([])
  })
```

Leave every other test in the file untouched (the practice-exclusion test, the 30-minute-floor test, etc. — those still pass under the new behavior).

- [ ] **Step 3: Make sure Postgres is up so integration tests can run**

Run from the repo root:

```bash
docker ps --format '{{.Names}}' | grep -q '^backend-db-1$' && echo "db up" || (cd backend && docker compose up -d db)
```

Expected: prints `db up`, or starts the container and reports `Container backend-db-1 Started`.

- [ ] **Step 4: Run the new tests to verify they fail in the right way**

Run from the repo root:

```bash
cd backend && set -a && source .env && set +a && npx vitest run test/integration/repo_sessions_results.test.ts
```

Expected output: the new test `'includes race / qualifying / sprint sessions whose end is more than 7 days in the past'` FAILS (current `listCandidates` returns `[]` because of the 7-day floor). The other three new tests should PASS already — they happen to be satisfied by the current implementation (sprint_quali 8d ago is excluded by the old blanket cap; sprint_quali 2d ago is included; finished sessions are filtered by `status='scheduled'`). Pre-existing tests in the file should all still PASS.

If the failure mode differs from the above (e.g. compilation errors, multiple failures), stop and re-read Step 2 — the paste likely landed in the wrong spot.

---

## Task 2: Make `listCandidates` type-aware

**Files:**
- Modify: `backend/src/repo/sessions.ts` — `listCandidates()` body (lines 41–57).

- [ ] **Step 1: Replace the body of `listCandidates`**

In `backend/src/repo/sessions.ts`, find the current `listCandidates` function (lines 41–57):

```ts
export async function listCandidates(): Promise<StoredSession[]> {
  const db = getDb()
  // Eligible: status=scheduled AND end + 30 min < now AND end > now - 7 days
  // AND type NOT IN practice
  const rows = await db
    .select()
    .from(session)
    .where(
      and(
        eq(session.status, 'scheduled'),
        sql`${session.type} NOT IN ('fp1','fp2','fp3')`,
        lt(session.scheduledEnd, sql`now() - interval '30 minutes'`),
        gt(session.scheduledEnd, sql`now() - interval '7 days'`)
      )
    )
  return rows as StoredSession[]
}
```

Replace it with:

```ts
export async function listCandidates(): Promise<StoredSession[]> {
  const db = getDb()
  // Eligible: status=scheduled AND end + 30 min < now AND not practice.
  // Only sprint_quali keeps the 7-day floor — its Jolpica endpoint never
  // returns data, and the floor stops us retrying it forever. race /
  // qualifying / sprint stay eligible until they're finished so historical
  // past sessions are picked up after a bootstrap or outage.
  const rows = await db
    .select()
    .from(session)
    .where(
      and(
        eq(session.status, 'scheduled'),
        sql`${session.type} NOT IN ('fp1','fp2','fp3')`,
        lt(session.scheduledEnd, sql`now() - interval '30 minutes'`),
        sql`(${session.type} <> 'sprint_quali' OR ${session.scheduledEnd} > now() - interval '7 days')`
      )
    )
  return rows as StoredSession[]
}
```

The `gt` import on line 1 stays — it's still used by `nextScheduled()`.

- [ ] **Step 2: Re-run the integration tests, expect all green**

```bash
cd backend && set -a && source .env && set +a && npx vitest run test/integration/repo_sessions_results.test.ts
```

Expected: every test in `repo_sessions_results.test.ts` PASSES, including the four new ones from Task 1.

- [ ] **Step 3: Run the full backend test suite to catch any regression**

```bash
cd backend && set -a && source .env && set +a && npm test
```

Expected: every test PASSES. The crawler-integration and admin-rescore tests are the most likely places for a knock-on failure if anything went sideways.

- [ ] **Step 4: Commit code + tests together**

```bash
git add backend/src/repo/sessions.ts backend/test/integration/repo_sessions_results.test.ts
git commit -m "$(cat <<'EOF'
backend: scope the 7-day candidate floor to sprint_quali only

Past race / qualifying / sprint sessions are now picked up by the tick
no matter how long ago they ended, so the backlog after a bootstrap or
an outage drains automatically. The 7-day cap is preserved for
sprint_quali, whose Jolpica endpoint never returns data.

Spec: docs/superpowers/specs/2026-05-26-historical-results-backfill-design.md
EOF
)"
```

---

## Task 3: Bring up the backend and drain the backlog

This is the operational half of the task. The code change is committed; now we start the backend and let one tick fetch the past rounds.

**Files:** none.

- [ ] **Step 1: Confirm the Postgres container is up**

```bash
docker ps --format '{{.Names}}\t{{.Status}}' | grep backend-db-1
```

Expected: a line like `backend-db-1    Up <duration>`. If missing, run `make db-up` from the repo root.

- [ ] **Step 2: Start the backend dev server in the background**

Use the Bash tool's `run_in_background` parameter for this command:

```bash
make backend
```

Expected: server starts and begins logging. The first useful log line to look for is `Listening at http://0.0.0.0:3000` (Fastify default). The scheduler will also log `Tick complete { ... }` whenever a tick runs.

- [ ] **Step 3: Wait for the server to be ready, then check health**

Poll until healthy (this is bounded — `make backend` is fast):

```bash
until curl -fsS http://localhost:3000/api/health >/dev/null 2>&1; do sleep 1; done && curl -fsS http://localhost:3000/api/health | python3 -m json.tool
```

Expected JSON contains `"db": "up"` and a `lastTick` object (may be null on cold start).

- [ ] **Step 4: Force a crawler tick to drain the backlog**

```bash
make crawl
```

Expected JSON shape:

```json
{
  "ok": true,
  "summary": {
    "sessionsFinished": 9,
    "sessionsSkipped": 3,
    "errors": 0
  }
}
```

Exact counts depend on what Jolpica returns, but `sessionsFinished` should be **at least 9** (3 scorable types × rounds 1–4 minus any missing sessions; round 5 was already finished before this change). `sessionsSkipped` should equal the count of past `sprint_quali` sessions still within the 7-day window or any other empty-result responses; **must not** be 12.

If `errors > 0`, check the background `make backend` log (the tick logs `Tick error for session <id> <err>` for each one).

- [ ] **Step 5: Verify in the DB that rounds 1–4 are now finished**

```bash
docker exec -e PGPASSWORD=f1pg_dev backend-db-1 psql -U f1pg -d f1pg -c \
  "SELECT e.round, e.name, s.type, s.status FROM event e JOIN session s ON s.event_id=e.id WHERE s.type IN ('race','qualifying','sprint') AND s.scheduled_start < now() ORDER BY e.round, s.type;"
```

Expected: every row in the output has `status = finished` for rounds 1 through 5 (the rounds whose scheduled sessions are in the past as of 2026-05-26). If any past `race`/`qualifying`/`sprint` row is still `scheduled`, that's a regression — re-run `make crawl` once; if it persists, inspect the backend log for the per-session error.

- [ ] **Step 6: Verify via the public API that past events carry session results**

```bash
curl -fsS http://localhost:3000/api/events/1 | python3 -m json.tool | head -40
```

Expected: round 1 (Australian GP) is returned with its sessions, and `race` / `qualifying` carry `status: "finished"`.

```bash
RACE_SID=$(curl -fsS http://localhost:3000/api/events/1 | python3 -c "import json,sys; e=json.load(sys.stdin); print(next(s['id'] for s in e['sessions'] if s['type']=='race'))")
curl -fsS "http://localhost:3000/api/sessions/$RACE_SID/results" | python3 -m json.tool | head -20
```

Expected: a non-empty ordered classification (around 20 driver rows) for the round 1 race.

- [ ] **Step 7: Stop the background backend**

Stop the background `make backend` process you started in Step 2 (kill the background Bash task). Postgres can stay up.

- [ ] **Step 8: Final commit gate**

No code changes happen in Task 3 — it's pure operational verification. If everything passed, the work is done. If anything failed, do not push or close out: re-open the failing step, capture the actual output, and decide whether it's a data issue (re-run the tick) or a logic issue (back to Task 2).

---

## Self-Review Summary

- **Spec coverage:** Decision (type-conditional cap) → Task 2. Test list in the spec → Task 1's four tests cover race/qualifying/sprint inclusion, sprint_quali 30d exclusion, sprint_quali 2d inclusion, finished-exclusion regression. Practice exclusion + 30-min lower bound → already covered by pre-existing tests we leave untouched. Operational rollout (start backend → crawl → confirm rounds 1–4 finished) → Task 3, steps 2–6.
- **Placeholders:** none.
- **Type consistency:** `listCandidates`, `markFinished`, `upsertSession`, `StoredSession` all match the existing repo signatures verbatim.
- **One nuance the engineer might miss:** test order matters less here because `truncateAll` runs in `beforeEach` (see `backend/test/helpers/setup.ts`), so every test starts with an empty DB.
