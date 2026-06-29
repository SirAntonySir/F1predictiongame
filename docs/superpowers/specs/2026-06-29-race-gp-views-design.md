# App Score Views — Design Spec

**Date:** 2026-06-29
**Status:** Approved (design)

## Purpose

Four UI changes to the Flutter app's score-presentation screens, plus one shared component extraction. No backend changes — all reuse existing endpoints.

1. Race detail: cap the session classification to top 5 with a "see full" expander.
2. Race detail: an Events / Full-GP toggle above the session chips.
3. Full-GP view: your weekend recap + the league's cumulative weekend leaderboard.
4. Player detail: group the pick-log by Grand Prix (latest expanded, rest collapsed).

## A. Shared component — `StandingsList`

Extract the home screen's `_leagueCard` rendering (`lib/screens/home_screen.dart:819-941`) into `lib/components/standings_list.dart`.

- Widget `StandingsList` renders a single bordered container of rows: rank · display name (`isMe` accented + `LeagueRowYouBadge`) · optional `TrendBadge` · points (right-aligned).
- Inputs: `rows` (a small row view-model list, already sorted, already capped by the caller), `meId`, and per-row `points` int + optional `trend` (`PositionTrend`), plus an `onTapRow(userId)` callback (null disables tap).
- Row view-model: `StandingsEntry { String userId; String displayName; int points; PositionTrend? trend; }`.
- `home_screen.dart` refactors its two `_leagueCard` call sites (in-season / total) to build `StandingsEntry` lists (computing trend via the existing `computeLeaderboardTrend`) and render `StandingsList`. Visual output unchanged.
- The Full-GP view (C) reuses `StandingsList`.

## B. Race detail — classification top 5 + see-full

In `lib/screens/session_results_screen.dart`, `_Body` (currently `StatelessWidget` at line 414) becomes `StatefulWidget` with a `bool _showFull = false`.

- The classification `List.generate(payload.result.length, …)` (lines 506-590) renders the first **5** rows when `!_showFull && result.length > 5`, otherwise all rows. Row widget (pick-slot highlight, exact/miss tick, lap time) is unchanged.
- When `result.length > 5`, append a final tappable row inside the same bordered container: "See full classification ▾" (collapsed) / "Show top 5 ▴" (expanded), toggling `_showFull`. Styled with `AppText.label`, muted onSurface.
- `result.length <= 5` → no expander, all rows shown.

## C. Race detail — Events / Full-GP toggle + Full-GP view

Add a toggle row directly above the session-chip `Wrap` (`session_results_screen.dart:207`). Two pills using the calendar tab-pill style (`calendar_screen.dart:352` `_tabPill`): **EVENTS** (default) and **FULL GP**. Filled when active.

- Screen state gains `String _mode = 'events'`.
- The toggle row renders only when the user is in a league (`scope.auth.leagues.isNotEmpty`); otherwise the screen is unchanged (Events-only).
- `_mode == 'events'` → existing screen (session chips + classification + your pick + league picks).
- `_mode == 'gp'` → hide the session chips and classification; render the Full-GP view:
  1. **Your weekend recap** card: your cumulative weekend points (sum of `MyScore.pointsTotal` for `eventRound == this event's round`, from the already-loaded `predictions` controller) and a per-session breakdown chip row (e.g. `QUALI 8 · SPRINT 5 · RACE 15`), one chip per scored session this weekend. Empty/`+0` styling when nothing scored yet.
  2. **League weekend leaderboard**: fetched once via `api.leagueSessionBreakdown(leagueId, season)` → `List<SessionLeaderboardRow>`, filtered to this event's `eventRound`, summed per member (`userId`/`displayName` → Σ `pointsTotal`). Sorted desc, rendered with `StandingsList` (no trend for v1), your row accented, `onTapRow` → `/league/:leagueId/player/:userId`. Members with 0 weekend points are hidden (matching home behaviour). Loading/empty/error states handled (a `FutureBuilder` keyed by round).

The event/round for the screen comes from the existing event lookup in the screen (the round is already known from the route / loaded event).

## D. Player detail — pick-log grouped by GP

In `lib/screens/player_screen.dart`, the LOCKED PICKS section (lines 154-175) currently maps `p.pickLog` (`List<PlayerPickLogItem>`, each with `round`, `eventName`, `sessionType`, `scheduledStart`, `score`) to `_PickLogCard`s.

- Group `pickLog` by `round`. For each group compute the **weekend total** = Σ of each item's `score?.pointsTotal` (0 when null).
- Order groups by the group's latest `scheduledStart` descending (newest GP first).
- Render each group as a collapsible tile (Flutter `ExpansionTile`, or a custom expand to match app styling) whose header shows `R{round} · {eventName}` and the weekend total (right-aligned, accent). The body holds that group's existing `_PickLogCard`s (unchanged), ordered by `scheduledStart` (session order within the weekend).
- The **first group (latest GP)** is expanded by default; the rest start collapsed.
- Empty `pickLog` keeps the existing empty-state container.

## Constraints / non-goals
- No backend or API-model changes.
- Keep the app's theme tokens + existing widgets (`AppCard`, `SessionChip`/tab pills, `TrendBadge`, `SouvenirTicket` not required here, `LeagueRowYouBadge`).
- The Full-GP weekend leaderboard has no position-trend in v1 (trend needs a "previous" baseline that isn't readily available per-weekend).

## Testing
- `flutter analyze` clean; existing tests stay green.
- Widget tests: `StandingsList` renders rows + accents `isMe`; the classification expander shows 5 then all on tap; the toggle swaps Events↔Full-GP; the player pick-log groups by GP with the latest expanded.
