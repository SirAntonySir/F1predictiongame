# UI Follow-ups: Pick/Result Cleanup, Preseason/In-Season Split, Trajectory, Preseason Tab

**Date:** 2026-05-27
**Status:** Pending user review

## Context

Four UI / scoring follow-ups bundled into one spec because they touch overlapping screens and data:

1. The `SessionResultsScreen` has a "PICK VS RESULT" card whose information is already shown inline in the `FULL CLASSIFICATION` rows below it (row tint by outcome, pick-slot chip, outcome glyph). The redundant block clutters the page.
2. The league leaderboard query (`backend/src/repo/scores.ts`, `leagueLeaderboard`) currently `UNION ALL`s in-season session scores with preseason scores into a single `pointsTotal`. The user wants the two halves visible as separate fields so a player's in-season form isn't masked by good preseason picks.
3. The `InsightsTab` trajectory chart plots only the current user. The chart widget already supports multiple series; the data isn't being assembled. The user wants every league member's trajectory overlaid.
4. There is no in-app place to see "how on-track am I with my preseason bets". A prior spec (`2026-05-26-insights-preseason-tracker-design.md`) proposed embedding a local-computation tracker inside `InsightsTab`. That work was deferred while the preseason backend wiring landed. The user now wants the same idea as a fourth top-level sub-tab on `StandingsScreen` (next to LEAGUE / F1 / INSIGHTS), with the projection computed server-side and a per-member preseason leaderboard on the same screen.

## Goal

Ship one PR that:
- Removes the redundant "PICK VS RESULT" card.
- Separates in-season and preseason points everywhere they're surfaced.
- Shows every league member on the trajectory chart.
- Adds a `PRESEASON` sub-tab on `StandingsScreen` that displays a live projection of the caller's preseason bets plus a per-member preseason leaderboard.

## Decisions

| # | Decision | Rationale |
|---|---|---|
| D1 | "PICK VS RESULT" block is deleted, not gated by a flag | The inline FULL CLASSIFICATION conveys the same information; keeping both costs vertical space and adds nothing. No code outside `session_results_screen.dart` references the block. |
| D2 | `leagueLeaderboard` returns `inSeasonPoints` + `preseasonPoints` + `pointsTotal` | A single SQL query with two conditional `SUM`s avoids round-trips. Keeping `pointsTotal` server-side lets the client sort by it without recomputing the sum (and stays the source of truth for podium order). |
| D3 | Leaderboard rows are sorted by `pointsTotal`, not by `inSeasonPoints` | Preseason is still part of the league competition — only the *display* is split. Changing sort order would silently rewrite the ranking the user already sees. |
| D4 | Trajectory uses the existing `/api/leagues/:id/leaderboard/sessions` endpoint (no new endpoint) | It already returns per-session per-member scores chronologically — exactly the shape we need to build cumulative series. |
| D5 | Trajectory shows all league members, not top-N | The user explicitly chose "All league members". The chart widget's `Wrap` legend already handles overflow. For a typical league size (~5 members), legibility is fine; if leagues ever balloon, a follow-up can add a top-N cap. |
| D6 | New preseason tab uses backend-computed projection, not Flutter-side derivation | The backend already has `derive*` helpers used by `rescorer.ts`. Reusing them server-side keeps scoring logic single-sourced (the old local-tracker spec D7 flagged the duplication as a "known coupling" — this avoids it entirely). |
| D7 | Surprise + Disappointment categories are shown as "—" / "Set at season end" | Both are admin-set subjective truths; no observed truth exists mid-season. Projecting them would be misleading. They appear as cards so the user sees the full point distribution, just with no projection. |
| D8 | Other members' preseason **picks** stay private; only their aggregate **score** is exposed | Per user choice ("aggregated scores"). Avoids a UI that would let losers see what winners picked early in the season. |
| D9 | One new endpoint `GET /api/leagues/:id/preseason` returns both halves (my projection + per-member aggregate) | One round-trip; the tab loads in one shot. Splitting into two endpoints would force an awkward two-stage loading UI. |
| D10 | Reverse-compat: the existing `/api/users/me/preseason-scores` endpoint stays unchanged | It returns *settled* scores (computed by `rescorer.ts` end of season). The new endpoint returns *projected* scores. Separate concerns. |

## Architecture

### Backend changes

```
backend/src/
  repo/scores.ts
    leagueLeaderboard()                  ← rewrite return shape
  preseason/
    projection.ts                        ← NEW: live projection on current snapshot
  api/routes/
    leaderboard.ts                       ← (no change — return shape just gets richer)
    preseason.ts                         ← add GET /api/leagues/:id/preseason
```

### Flutter changes

```
lib/
  api/models/
    leaderboard_row.dart                 ← add inSeasonPoints, preseasonPoints
    preseason_projection.dart            ← NEW: response model for the new endpoint
  api/
    api_client.dart, http_api_client.dart ← add getLeaguePreseason(leagueId)
  components/
    league_row.dart                      ← layout change: two number columns + total
  screens/
    session_results_screen.dart          ← remove PICK VS RESULT block
    standings/
      standings_screen.dart              ← add 'preseason' sub-tab pill
      league_tab.dart                    ← render new LeaderboardRow shape
      insights_tab.dart                  ← trajectory uses leagueSessionBreakdown
      preseason_tab.dart                 ← NEW: live projection + member leaderboard
```

No state-management library is introduced. Tabs continue to load their own data on `didChangeDependencies` via `FutureBuilder` (matches existing pattern in `LeagueTab` / `InsightsTab`).

## Components

### 1. Remove "PICK VS RESULT" — `lib/screens/session_results_screen.dart`

Delete the `if (payload.picks.isNotEmpty && payload.result.isNotEmpty) { … 'PICK VS RESULT' … }` block (currently lines ~328–394). The block is self-contained (a `Padding` + a `Padding` + an `AppCard`). The surrounding `Column` already handles spacing between siblings via its `if (…) [...]` ordering.

Verify after edit: the `ScoreBanner` (above) and `FULL CLASSIFICATION` card (below) are now adjacent; the `Spacing.lg` top-padding on the FULL CLASSIFICATION header still gives appropriate breathing room.

### 2. Split preseason from in-season points

**`backend/src/repo/scores.ts` — rewrite `leagueLeaderboard`:**

```ts
export type LeaderboardRow = {
  userId: string
  displayName: string
  inSeasonPoints: number
  preseasonPoints: number
  pointsTotal: number
  sessionsScored: number
}

export async function leagueLeaderboard(leagueId: string, seasonYear: number): Promise<LeaderboardRow[]> {
  const db = getDb()
  const rows = await db.execute(sql`
    SELECT
      lm.user_id::text AS "userId",
      u.display_name   AS "displayName",
      COALESCE(SUM(CASE WHEN s.kind='session'  THEN s.points_total ELSE 0 END), 0)::int AS "inSeasonPoints",
      COALESCE(SUM(CASE WHEN s.kind='preseason' THEN s.points_total ELSE 0 END), 0)::int AS "preseasonPoints",
      COALESCE(SUM(s.points_total), 0)::int                                              AS "pointsTotal",
      COUNT(CASE WHEN s.kind='session' THEN 1 END)::int                                  AS "sessionsScored"
    FROM ${leagueMember} lm
    JOIN ${user} u ON u.id = lm.user_id
    LEFT JOIN ${score} s
      ON s.user_id = lm.user_id
     AND (
           (s.kind = 'session'   AND EXISTS (
              SELECT 1 FROM ${session} ses JOIN ${event} ev ON ev.id = ses.event_id
              WHERE ses.id = s.session_id AND ev.season_year = ${seasonYear}))
        OR (s.kind = 'preseason' AND s.season_year = ${seasonYear})
        )
    WHERE lm.league_id = ${leagueId}
    GROUP BY lm.user_id, u.display_name
    ORDER BY "pointsTotal" DESC, "displayName" ASC
  `)
  return (rows as unknown as { rows: LeaderboardRow[] }).rows
}
```

The `EXISTS` keeps the session-year filter without an `INNER JOIN` (which would drop members who have only preseason scores — they'd disappear from the leaderboard entirely). `sessionsScored` only counts session-kind scores so it stays semantically "rounds scored", not "rounds + preseason categories".

**`lib/api/models/leaderboard_row.dart`** — add two `int` fields. Update `fromJson`. `pointsTotal` already exists.

**`lib/components/league_row.dart`** — extend the row layout to show three numbers (in-season, preseason, total). The component currently takes `points: int`; widen to `inSeasonPoints`, `preseasonPoints`, `pointsTotal` and render as three right-aligned cells. The "me" highlight and trend badge stay where they are.

**`lib/screens/standings/league_tab.dart`** — adjust the `LeagueRow` constructor call to pass the new fields. The `_Podium` keeps using `pointsTotal` for the visual ordering.

### 3. Trajectory: all league members — `lib/screens/standings/insights_tab.dart`

The backend endpoint `GET /api/leagues/:id/leaderboard/sessions` already exists (returns `SessionLeaderboardRow[]` — see `backend/src/repo/scores.ts:113`). The Flutter side has **no** model or client method for it yet; both need to be added as part of this work:

- New model `lib/api/models/session_leaderboard_row.dart` with fields `sessionId`, `sessionType`, `eventRound`, `eventName`, `scheduledStart`, and `members: List<MemberScore>` (where `MemberScore` is `{userId, displayName, pointsTotal}` — the existing `ScoreBreakdown` field on the wire isn't needed for the chart, so the Flutter model omits it to keep parsing cheap).
- `ApiClient.leagueSessionBreakdown(String leagueId) → Future<List<SessionLeaderboardRow>>` plus its `HttpApiClient` implementation.

Replace the `_load` body so `_InsightsData` carries an additional `List<SessionLeaderboardRow> sessions` alongside the existing `scores` and `leaderboard` fields. `scores` and `leaderboard` are still needed for the "YOUR SEASON" stat cards and "LEAGUE GOSSIP" facts; only the trajectory consumes `sessions`.

`_buildTrajectory` becomes (sketch — final names may differ):

```dart
List<ChartSeries> _buildTrajectorySeries(_InsightsData d) {
  // Backend returns desc by scheduledStart; flip to ascending for chronological plotting.
  final sessions = [...d.sessions]..sort((a, b) => a.scheduledStart.compareTo(b.scheduledStart));
  if (sessions.isEmpty) return const [];

  // Per-session points-by-userId for O(1) lookups while building cumulative series.
  final pointsByMemberPerSession = [
    for (final s in sessions) { for (final m in s.members) m.userId: m.pointsTotal },
  ];
  // displayName by userId — pulled from whatever session first mentions them.
  final names = <String, String>{};
  for (final s in sessions) {
    for (final m in s.members) names.putIfAbsent(m.userId, () => m.displayName);
  }
  // Stable plot order: caller first, then alphabetical by displayName.
  final allIds = names.keys.toList();
  final ordered = [
    if (d.myUserId != null && names.containsKey(d.myUserId)) d.myUserId!,
    ...(allIds.where((id) => id != d.myUserId).toList()
      ..sort((a, b) => names[a]!.compareTo(names[b]!))),
  ];
  const palette = [
    BrandColors.accent,        // index 0 — always "you"
    Color(0xFF6B6F76),
    Color(0xFFB58A3A),
    Color(0xFF4A7B8C),
    Color(0xFF8E5A7B),
    Color(0xFF5C8C4A),
    Color(0xFF8C5A4A),
  ];
  return [
    for (var i = 0; i < ordered.length; i++)
      ChartSeries(
        label: ordered[i] == d.myUserId ? 'You' : names[ordered[i]]!,
        color: palette[i % palette.length],
        points: _cumulativePoints(pointsByMemberPerSession, ordered[i]),
      ),
  ];
}

List<double> _cumulativePoints(List<Map<String, int>> perSession, String userId) {
  var cum = 0.0;
  return [
    for (final m in perSession) cum += (m[userId] ?? 0).toDouble(),
  ];
}
```

x-labels still come from `sessions` (e.g. `'R${eventRound}·${sessionType[0]}'`, abbreviated to one label per session — current chart uses `'R$round'` for cumulative rounds, but with per-session granularity we need a session-level label). The `TrajectoryChart` painter already finds `maxV` across all series, so multi-line auto-scales correctly.

If `d.sessions` is empty (no league member has any scored session yet), fall back to the existing "No scored rounds yet." card.

### 4. New `PRESEASON` sub-tab

**Backend — `backend/src/preseason/projection.ts` (new):**

```ts
export type CategoryProjection = {
  category: PreseasonCategory
  myPick: { driverCode: string | null; constructorId: string | null }
  projectedTruth: { driverCode: string | null; constructorId: string | null } | null  // null for surprise/disappointment
  projectedPoints: number
  max: number
}

export type StandingsProjection = {
  myDriverPicks: PreseasonStandingsDriverPick[]
  myConstructorPicks: PreseasonStandingsConstructorPick[]
  projectedDriverOrder: string[]      // current standings, descending by points
  projectedConstructorOrder: string[]
  projectedPoints: number
  max: number
}

export type LeaguePreseasonView = {
  seasonYear: number
  isLocked: boolean
  me: {
    categories: CategoryProjection[]
    standings: StandingsProjection
    projectedPointsTotal: number      // sum across all 7 above
  }
  leaderboard: { userId: string; displayName: string; preseasonPointsProjected: number }[]
}

export async function buildLeaguePreseasonView(leagueId: string, userId: string, seasonYear: number): Promise<LeaguePreseasonView>
```

Implementation:
- Fetch events + sessions + results for the season once (same approach as `rescorer.ts`).
- Run `deriveMostDnfs`, `derivePolesitter`, `deriveMostFastestLaps`, `deriveWdcWcc`, `deriveFinalStandings` against the *current* snapshot. These functions are already pure in their inputs — they don't know whether the season is over.
- Surprise + Disappointment: `projectedTruth = null`, `projectedPoints = 0`. The Flutter side renders them as "Set at season end".
- For the caller, compute `projectedPoints` per category via the existing `scorePreseasonCategory` and `scoreStandings`.
- For the leaderboard: iterate league members, fetch each one's picks, run the same scoring against the same projected truth, sum to `preseasonPointsProjected`. Picks themselves are not returned. (This is O(members × categories) queries — for typical league sizes (≤10) this is fine; if it becomes hot, cache per (leagueId, seasonYear) for a few seconds.)

**Backend — route `backend/src/api/routes/preseason.ts`:** add

```ts
app.get<{ Params: { id: string } }>('/api/leagues/:id/preseason', async (req) => {
  const u = getCurrentUser(req)
  await requireLeagueMember(req, req.params.id)
  const year = await getCurrentSeasonYear()
  return await buildLeaguePreseasonView(req.params.id, u.id, year)
})
```

**Flutter — model `lib/api/models/preseason_projection.dart` (new):** mirrors `LeaguePreseasonView` 1:1 with `fromJson` factories. No further models needed; reuses existing `PreseasonCategory` enum.

**Flutter — API client:** add `Future<LeaguePreseasonView> leaguePreseason(String leagueId)` to `ApiClient` + `HttpApiClient`.

**Flutter — new screen `lib/screens/standings/preseason_tab.dart`:**

```
PreseasonTab (StatefulWidget)
├── FutureBuilder<LeaguePreseasonView>
│   ├── Header strip — "PROJECTED · LIVE" + total pts banner
│   ├── _LeaderboardBlock — list of members sorted by preseasonPointsProjected
│   │   (renders: rank · displayName · "+X pts")
│   └── _CategoryGrid — 6 single-pick cards + 1 standings card
│       Card layout (uniform):
│         ┌─────────────────────────────────┐
│         │ ★ MOST POLES               16 pts │
│         │ Your pick: HAM · Mercedes          │
│         │ On track : VER · Red Bull          │
│         │ Projected: +8                       │
│         └─────────────────────────────────┘
│       For surprise/disappointment: "On track: Set at season end" and "Projected: —".
│       Standings card: "8 / 20 driver slots · 4 / 10 team slots · +52 pts"
```

Card styling reuses `AppCard` and the typography helpers — visually matches the existing preseason picker cards in `screens/preseason_screen.dart` so the user recognizes the categories.

**Flutter — `lib/screens/standings/standings_screen.dart`:** add `Expanded(child: _tab('preseason', 'PRESEASON'))` (sized down to 9pt font label if the four-pill row gets cramped on small screens — single-line check during implementation). Add `'preseason' => const PreseasonTab(),` to the body switch.

## Data Flow

```
StandingsScreen [PRESEASON tab tapped]
        │
        ▼
PreseasonTab.didChangeDependencies → ApiClient.leaguePreseason(leagueId)
        │
        ▼ HTTP GET /api/leagues/:id/preseason
        │
        ▼ buildLeaguePreseasonView(leagueId, userId, year)
        │     ├── load events+sessions+results (1× per call; cached intra-request)
        │     ├── derive* against current snapshot → projectedTruth per category
        │     ├── scoreCaller → me.categories + me.standings + me.projectedPointsTotal
        │     └── for each league member: load picks, score against same truth → leaderboard
        │
        ▼ JSON
        │
        ▼ FutureBuilder renders header + leaderboard list + category grid
```

## Error Handling

- All four screens reuse the existing `ErrorView` pattern with retry callback.
- New endpoint: if league is empty or has no scored data, `me.projectedPointsTotal = 0` and `leaderboard = [member with 0 pts each]`. No 404; the UI shows zeros with empty-state copy under the leaderboard ("No picks scored yet — bets settle as the season unfolds.").
- If the caller has no picks at all, the category grid still renders 7 cards with `myPick = (null, null)` shown as "—". Projection is computed (just always 0).

## Testing

**Backend (vitest, run via `make backend-test`):**
- `repo/scores.test.ts`: `leagueLeaderboard` returns separate `inSeasonPoints` / `preseasonPoints`; sum equals `pointsTotal`; members with only preseason scores still appear; members with no scores appear with all zeros.
- `preseason/projection.test.ts`: with a fixture mid-season snapshot, `buildLeaguePreseasonView` returns the right projected truth per category; surprise/disappointment have `projectedTruth = null`; the leaderboard aggregates correctly and does not leak picks.

**Flutter (widget tests):**
- `session_results_screen` regression: with picks + results, the FULL CLASSIFICATION rows still tint correctly and the page no longer contains a "PICK VS RESULT" heading (negative assertion).
- `league_tab`: row renders three numbers; total = in-season + preseason.
- `insights_tab` trajectory: with a fixture of 3 members across 3 sessions, three `ChartSeries` are passed to `TrajectoryChart`; "You" gets `BrandColors.accent`.
- `preseason_tab`: renders 7 category cards + 1 standings card; surprise/disappointment show "Set at season end"; member leaderboard sorts by projected points descending.

## Out of Scope

- Restoring or replacing the prior `2026-05-26-insights-preseason-tracker-design.md` (local-computation tracker inside `InsightsTab`). The new tab supersedes it. The old spec stays in the docs folder as history.
- Exposing other members' individual preseason picks. Privacy choice — revisit when/if a "post-mortem" view is wanted at season end.
- Sorting by something other than `pointsTotal` on the league tab. The split is purely visual.
- Pagination on the league preseason endpoint (typical league sizes don't need it).
