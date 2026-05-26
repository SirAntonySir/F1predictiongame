# OpenF1 Integration — Design

**Date:** 2026-05-26
**Status:** Pending user review

## Context

The crawler today has Jolpica-F1 as its single source. Jolpica covers race, qualifying, sprint, full-season standings, and the schedule cleanly — but its `sprint_quali` endpoint always errors. So sprint qualifying sessions never receive results, and any predictions on them are unscorable. `backend/README.md:177` documents this as a known limitation.

OpenF1 (`api.openf1.org`) is a community F1 data API that **does** publish sprint qualifying classification (verified live for the 2026 China / Miami / Canada sprint weekends), plus richer per-driver metadata (`headshot_url`, `team_colour`) and live-timing data we may want later for detail screens.

This spec adds OpenF1 as a second data source for results, scoped narrowly to what fixes the sprint-quali gap and meaningfully improves the existing UX.

## Goal

- Eliminate the sprint-quali blind spot — fetch results from OpenF1 for that session type.
- Cross-check race / qualifying / sprint against OpenF1; surface discrepancies in logs without changing source-of-truth (Jolpica remains authoritative).
- Enrich driver/constructor records with `headshot_url` and `team_colour` from OpenF1.
- Keep the crawler thin: no new tables, three new columns, one new HTTP client, no cadence change.
- Shape the new client so adding lap-level / pit / weather endpoints later (for data detail screens) is mechanical, not architectural.

## Decisions

| # | Decision | Rationale |
|---|---|---|
| D1 | **Source-of-truth precedence:** Jolpica authoritative for race / qualifying / sprint; OpenF1 only for sprint_quali. | Jolpica is the established source; OpenF1 fills the one gap. Reduces churn. |
| D2 | **Cross-check:** for race / qualifying / sprint, fetch OpenF1 in addition to Jolpica and log structured discrepancies. No DB write. | Builds confidence in data without persistence cost. Easy to upgrade later if needed. |
| D3 | **Fallback:** when Jolpica returns empty and OpenF1 returns rows for race / qualifying / sprint, persist OpenF1. | Helps when Jolpica is slow to publish. `replaceForSession` is idempotent so a later Jolpica fetch can overwrite. |
| D4 | **Session-key resolution:** bootstrap-time join. One `GET /sessions?year=Y` after Jolpica's `runBootstrap` populates the schedule. Persist matched `session_key` on `session.openf1_session_key`. | Single HTTP call per bootstrap. No per-tick lookup. Null when no match. |
| D5 | **Schema:** three nullable columns. No new tables. | Smallest viable addition; YAGNI for the discrepancy log / live data. |
| D6 | **Driver/constructor enrichment:** opportunistic in-tick. Whenever OpenF1 is consulted, call `/drivers?session_key=X` once and fill in null `headshot_url` / `team_colour`. Never overwrite existing values. | Mirrors the existing Wikipedia-image enrichment pattern. Manual overrides keep winning. |
| D7 | **Image precedence at the API:** `imageUrlOverride ?? headshotUrl ?? imageUrl`. | Manual curated assets still win; OpenF1 official headshots beat Wikipedia scrapes. |
| D8 | **Team colour:** new constructor field, exposed at API as `teamColour`. Flutter falls back to it when the hand-curated `team_colors.dart` map has no entry. | Hand-curated still wins for brand accuracy; OpenF1 covers unknown teams automatically. |
| D9 | **Cadence:** unchanged — `*/15 * * * *` tick. | Crawler is already a no-op when there are no candidates; rate limits are not a concern for either source (~3-4 sessions per race weekend). |
| D10 | **Boundary rule:** `crawler/` may import `openf1/`. `openf1/` imports nothing from the rest of the backend. Mirrors the `jolpica/` layering. | Keeps the new client decoupled and testable in isolation. |

## Architecture

New module `backend/src/openf1/`:

```
backend/src/openf1/
  client.ts      — OpenF1Client class:
                     getSessions(year)
                     getDrivers(sessionKey)
                     getSessionResult(sessionKey)
  parsers.ts     — parseSessionResult(raw, drivers): SessionResultRow[]
                   parseDrivers(raw): OpenF1DriverLookup[]
                   formatDuration(seconds: number): string  (e.g. 74.772 → "1:14.772")
                   matchSessionName(sessionType): string    (e.g. 'sprint_quali' → 'Sprint Qualifying')
```

Boundary (matches `backend/README.md`):

- `crawler/` → `jolpica/`, `wikipedia/`, **`openf1/`**, `repo/`
- `openf1/` → nothing (pure HTTP + parsing; no repo / db imports)

## Data flow

### Bootstrap-time mapping

After `runBootstrap` populates the schedule from Jolpica, a new step in the bootstrap call:

1. `GET https://api.openf1.org/v1/sessions?year=YEAR` — one call, returns ~100 rows for a full season.
2. For each session row in our DB for that year, match on `(UTC date of date_start, session_name)` where session_name is derived from our `SessionType` via the mapping table:
   ```
   race          ↔ "Race"
   qualifying    ↔ "Qualifying"
   sprint        ↔ "Sprint"
   sprint_quali  ↔ "Sprint Qualifying"
   fp1 / fp2 / fp3 ↔ "Practice 1" / "Practice 2" / "Practice 3"
   ```
3. Write the matched `session_key` to `session.openf1_session_key`. Sessions with no match keep `null`.
4. Log one info line per session that didn't match.

Runs from both `POST /admin/bootstrap` and the weekly Monday 03:00 UTC schedule refresh (so newly-published OpenF1 sessions get joined automatically).

### Tick (per-session behaviour)

`fetchByType` in `backend/src/crawler/tick.ts` becomes type-aware:

| Type | Fetch | Persist | Cross-check |
|---|---|---|---|
| `race` / `qualifying` / `sprint` | Jolpica + (if `openf1_session_key` set) OpenF1 | Jolpica's rows; if Jolpica empty and OpenF1 has rows, persist OpenF1 as fallback | Compare `[(position, driverCode)]`; log WARN on length or per-position mismatch |
| `sprint_quali` | OpenF1 only (if `openf1_session_key` set) | OpenF1's rows | n/a |
| `fp1` / `fp2` / `fp3` | neither | n/a | n/a |

Enrichment happens whenever OpenF1 was consulted in the iteration:

- For each driver in the OpenF1 `/drivers` response, if `driver.headshot_url IS NULL`, write `headshot_url`.
- For each constructor referenced, if `constructor.team_colour IS NULL`, write the OpenF1 `team_colour` hex.
- Never overwrite non-null values.

If an OpenF1 result row references a driver acronym not in our `driver` table:

- For `sprint_quali` (OpenF1 is the only source): skip the **entire session** this tick — partial classification is not useful for scoring. Counts toward `sessionsSkipped`. Most commonly resolves on the next tick once Jolpica's matching qualifying/race fetch has inserted the driver.
- For the cross-check (race / qualifying / sprint): exclude the unknown driver from the position comparison; do not skip persistence of Jolpica's rows.
- Log one WARN line per occurrence (not one per row).

## Schema changes

Single migration, all additive, all nullable. Safe on existing DB.

| Table | Column | Type | Default | Notes |
|---|---|---|---|---|
| `session` | `openf1_session_key` | `integer` | null | Cached join key. |
| `driver` | `headshot_url` | `text` | null | Official Formula1.com headshot URL. |
| `constructor` | `team_colour` | `text` | null | Hex without `#`, OpenF1 casing preserved verbatim (e.g. `"F47600"`). |

No indexes added. (The columns are read by id; existing PKs cover lookups.)

## API surface

- `GET /api/drivers/:code` — response gains `headshotUrl`; resolved `image` field becomes `imageUrlOverride ?? headshotUrl ?? imageUrl`.
- `GET /api/standings/drivers` — same per-driver enrichment.
- `GET /api/constructors/:id` — response gains `teamColour`. `image` unchanged.
- `GET /api/standings/constructors` — same.
- Session results endpoints unchanged.
- `POST /admin/refresh-openf1-metadata` — token-gated. Iterates drivers with `headshot_url IS NULL` and constructors with `team_colour IS NULL`, fetches OpenF1 `/drivers?session_key=...` for the most-recent finished session that includes each missing entity, fills in.

## Flutter changes

- `lib/api/models/driver.dart` — add `headshotUrl: String?`. The resolved `image` field continues to work (server-resolved).
- `lib/api/models/constructor.dart` — add `teamColour: String?`.
- `lib/theme/team_colors.dart` — when the hand-curated map has no entry for a constructor ID, fall back to the constructor's `teamColour` as `Color(int.parse(teamColour, radix: 16) | 0xFF000000)`. Curated map still wins where present.
- No new screens, no new widgets in this spec.

## Error handling

| Failure | Behaviour |
|---|---|
| Bootstrap `GET /sessions?year=Y` errors | Log; sessions keep `openf1_session_key = null`. Weekly refresh retries automatically. |
| A Jolpica session has no OpenF1 match | One info log per bootstrap. Column stays null. |
| Tick cross-check call errors | WARN log; persist Jolpica anyway. Tick succeeds. |
| Tick cross-check returns empty | Silent — OpenF1 hasn't published yet. |
| OpenF1 has rows, Jolpica returns empty | Persist OpenF1 as fallback. Next tick may overwrite when Jolpica catches up. |
| Sprint quali fetch errors | `sessionsSkipped`; existing 7-day cap is the circuit breaker. |
| OpenF1 references unknown driver | Skip that row this tick; one WARN log; retry next tick. |
| Headshot / team_colour enrichment errors | Log, continue. Never blocks results being persisted. |

## Testing

**Unit** (`backend/test/unit/`)

- `openf1_parsers.test.ts`:
  - `parseSessionResult` formats durations correctly (e.g. `74.772` → `"1:14.772"`, `64.0` → `"1:04.000"`).
  - Sparse `duration` arrays (driver eliminated in SQ2) map to `q1`/`q2` only.
  - `dnf` / `dns` / `dsq` true → row's `status` set accordingly.
  - `parseDrivers` preserves OpenF1's `team_colour` case verbatim (pinned by test).
  - `matchSessionName` covers all `SessionType` enum members.
- `openf1_client.test.ts`:
  - URL shape for each method (`/sessions?year=Y`, `/drivers?session_key=K`, `/session_result?session_key=K`).
  - Returns `null` on non-200 (matches `JolpicaClient` convention).

**Integration** (`backend/test/integration/`)

- `crawler_openf1_sprintquali.test.ts` — mock OpenF1 + bootstrap, run tick, assert sprint_quali session has rows with q1/q2/q3 and `status='finished'`.
- `crawler_openf1_crosscheck.test.ts` — matching classifications → no warning; one-position swap → exactly one WARN; Jolpica empty + OpenF1 populated → OpenF1 rows persisted.
- `crawler_openf1_enrichment.test.ts` — new driver gains `headshot_url`; existing non-null `headshot_url` is preserved; new constructor gains `team_colour`.
- `bootstrap_openf1_mapping.test.ts` — `session.openf1_session_key` populated for known race/qualifying/sprint/sprint_quali sessions; null for unmatched practice or sessions OpenF1 doesn't yet publish.
- `api_drivers_headshot.test.ts` — image precedence is `override ?? headshot ?? wikiImage` across `/api/drivers/:code` and `/api/standings/drivers`.

**Flutter** (`test/`)

- `theme/team_colors_test.dart` — curated map wins; falls back to constructor `teamColour`; falls back to neutral when both are null.

## Operational notes

- After deploy, run once: `POST /admin/bootstrap` (rebuilds mapping for the current season), then `POST /admin/crawl` (drains any past sprint_quali sessions now-fetchable), then `POST /admin/refresh-openf1-metadata` (backfills headshots/colours for existing drivers/constructors).
- Steady state: nothing changes operationally. The 15-min tick handles everything.

## Out of scope (deferred)

- Lap-level data, pit stops, stints, weather, race control, telemetry, team radio (the client is shaped so adding these later is one new method + one new parser).
- Replacing Jolpica anywhere it currently works.
- A persisted discrepancy log table (start with console WARN; promote later if needed).
- Backfill of pre-2025 seasons.
- New UI: lap-time chart, pit-stop table, etc. Deferred to a later "data detail screens" spec.

## Risks & mitigations

- **OpenF1 API instability.** No SLA. Mitigated by Jolpica remaining authoritative; cross-check failures degrade gracefully; sprint_quali is the only fully-OpenF1-dependent type, and it's currently broken anyway.
- **Driver acronym drift.** OpenF1's `name_acronym` is the de-facto FIA 3-letter code, but if it ever disagrees with Jolpica we skip the row and log. No silent corruption.
- **Team-colour mismatch with curated palette.** Hand-curated map wins where present; OpenF1 only fills gaps. Curators can still override anything that looks wrong.
