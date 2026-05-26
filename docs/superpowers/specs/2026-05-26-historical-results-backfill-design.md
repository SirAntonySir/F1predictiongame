# Historical Results Backfill — Design

**Date:** 2026-05-26
**Status:** Pending user review

## Context

The backend's crawler (`backend/src/crawler/tick.ts` → `repo/sessions.listCandidates`) only considers sessions whose `scheduled_end` falls in the **last 7 days**. The cap was added to stop the tick hammering Jolpica forever for `sprint_quali`, which has no working endpoint.

Side effect: any past session more than 7 days old that isn't already `finished` is silently skipped forever. This bites in two situations:

1. The schedule is bootstrapped mid-season (the current local state — round 5 is `finished`, rounds 1–4 are still `scheduled`).
2. The crawler is offline for more than a week.

Symptom in the app: only the most recent race shows results / scored points; older rounds are blank.

## Goal

The crawler should eventually fetch results for every past scorable session (`race`, `qualifying`, `sprint`), regardless of how long ago it ended, without resurrecting the unbounded-retry problem the cap was designed to prevent.

## Decision

Make the 7-day floor in `listCandidates()` **type-aware**: apply it only to `sprint_quali` (the only type known to be unfetchable). All other scorable types (`race`, `qualifying`, `sprint`) remain candidates as long as their `scheduled_end` is in the past and they're still `scheduled`.

### Rationale vs. alternatives

| Option | Why not |
|---|---|
| One-shot `/admin/backfill-season/:year` endpoint | Papers over the bug — same trap re-opens on next outage / fresh DB / mid-season deploy. Manual operator step. |
| Remove cap entirely | Resurrects unbounded retries against the dead `sprint_quali` endpoint. |
| Auto-backfill inside `runBootstrap` | Couples schedule-seeding with fetching; makes bootstrap slow and harder to reason about. |

The type-aware fix removes the trap entirely, self-heals from outages on the next tick, and keeps the existing protection for `sprint_quali`.

## Change

**File:** `backend/src/repo/sessions.ts` — `listCandidates()`

Today (paraphrased):

```ts
where(
  status='scheduled'
  AND type NOT IN ('fp1','fp2','fp3')
  AND scheduled_end < now() - 30 min
  AND scheduled_end > now() - 7 days   // ← applies to all types
)
```

After:

```ts
where(
  status='scheduled'
  AND type NOT IN ('fp1','fp2','fp3')
  AND scheduled_end < now() - 30 min
  AND (type <> 'sprint_quali' OR scheduled_end > now() - 7 days)
)
```

No schema change. No new endpoint. No call-site changes.

## Tests

Add a unit test in `backend/test/` for `listCandidates`:

- A `race` session 30 days in the past, `status='scheduled'` → **is** a candidate.
- A `qualifying` session 30 days in the past, `status='scheduled'` → **is** a candidate.
- A `sprint` session 30 days in the past, `status='scheduled'` → **is** a candidate.
- A `sprint_quali` session 30 days in the past → **not** a candidate.
- A `sprint_quali` session 2 days in the past → **is** a candidate.
- A `fp1` session 1 hour in the past → **not** a candidate (unchanged).
- A `race` session 5 min in the past (end not yet 30 min ago) → **not** a candidate (unchanged).
- A finished `race` session 30 days in the past → **not** a candidate (unchanged).

## Operational rollout

1. Start backend (`make backend`).
2. Apply the patch + test.
3. `make crawl` once. Expected: rounds 1–4 transition from `scheduled` to `finished`; standings refresh; preseason rescore runs.
4. Confirm via DB and via the app's Calendar screen that all past rounds show results and per-round points.

## Blast radius

- One additional cold-start tick fetches ~12 extra sessions (4 rounds × 3 scorable types) once. Bounded; sessions become `finished` after success and drop out of candidacy.
- Steady-state behaviour unchanged: in normal operation no session sits `scheduled` past its end for more than ~15 minutes anyway.
- `sprint_quali` behaviour unchanged.

## Out of scope

- Per-session attempt counters / exponential backoff.
- Backfilling prior seasons (D3 in the data-foundation spec — current season only).
- Any frontend change. The Calendar / session-results screens already render whatever the backend serves.
