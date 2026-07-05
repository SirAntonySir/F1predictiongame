# Results Podium — Design

**Date:** 2026-07-05
**Status:** Approved for planning

## Summary

When a league session gets newly scored, celebrate it: on Home load / refresh, pop
a temporary bottom-sheet modal showing a **podium of the three league members who
scored the most points in that session**, rendered as their avatars — winner in the
victory pose front-and-center, 2nd and 3rd in the crossed-arms pose flanking and
slightly behind at reduced scale (3rd mirrored). A bottom gradient scrim carries each
member's position, name, and points.

## Goals / Non-goals

**Goals**
- Detect a newly-scored session on Home entry and Home pull-to-refresh, and show the
  podium exactly once per session.
- Render top-3 members with their real liveries/poses using the existing avatar engine.
- Provide a debug-only way to preview the sheet on demand (no waiting for real results).

**Non-goals**
- No push notifications, no background detection (Home-tab trigger only).
- No navigation from the sheet (tapping a bust does nothing in v1).
- No aggregation across a race weekend — each **session** is celebrated independently.
- No change to the existing season-leaderboard podium in `league_tab.dart`.

## Behavior decisions (locked)

| Decision | Choice |
|---|---|
| Trigger scope | **Newly-scored session** (each session celebrated once when it first appears scored) |
| Backlog (multiple unseen) | **Most recent only** — show newest unseen scored session; mark the rest seen silently |
| Trigger point | **Home tab only** — hooks `HomeCacheController.refresh()` (app open + pull-to-refresh) |
| Member count | **Require ≥3 scorers**, else skip (no partial podium) |
| Ranking | Points desc, then `displayName` asc for ties |
| Dismiss | Drag-down, an **X** top-right, and a "Nice" button — all pop the sheet |
| Dev preview | `kDebugMode`-only Settings row; real newest scored session if any (bypasses seen-set), else synthetic sample data |

## Data flow

1. `HomeCacheController._fetch()` additionally calls
   `api.leagueSessionBreakdown(leagueId)` (best-effort; failure leaves the feature
   inert, never blocks Home).
2. From the returned `List<SessionLeaderboardRow>`, select the **newest by
   `scheduledStart`** whose members list is non-empty (a scored session).
3. If that session's `sessionId` is **not** in the persisted seen-set **and** it has
   **≥3 members**: build `PodiumData` and publish it via a dedicated
   `ValueNotifier<PodiumData?> podiumPending` on `HomeCacheController` (kept off
   `HomeData` so a stale-while-revalidate rebuild doesn't re-arm it).
4. Regardless of whether it qualified, **add every currently-scored `sessionId` to the
   seen-set** so older/skipped sessions never fire later ("most recent only").
5. `HomeScreen` observes `podiumPending`; after first paint (post-frame callback) it
   calls `showResultsPodium(context, data)` once, then clears the pending flag so a
   subsequent rebuild/refresh doesn't re-show it.

### Assembling `PodiumData`
- Take the session row's members, sort by (points desc, name asc), take top 3.
- For each, look up `avatarConfig` by `userId` from `HomeData.leaderboard`
  (`List<LeaderboardRow>`, already fetched). Missing config → render the default
  (Undercut) avatar, same as `HelmetIcon`'s null handling.
- Labels: session/event come from the row (`eventName`, `sessionType`, `eventRound`).

## Components (new)

```
lib/state/seen_results_store.dart
  SeenResultsStore — SharedPreferences-backed Set<int> of celebrated sessionIds.
    Future<Set<int>> load();  Future<void> markSeen(Iterable<int>);  bool-less API.
  Key: 'seen_scored_sessions' (JSON list of ints).

lib/components/podium/podium_data.dart
  PodiumData { String eventName; String sessionLabel; int round;
               List<PodiumEntry> entries; }   // entries length 1..3, ranked
  PodiumEntry { int rank; String displayName; int points; String? avatarConfig; }
  Factory: PodiumData.fromSession(SessionLeaderboardRow, List<LeaderboardRow>).
  Static PodiumData.sample() for dev preview / tests.

lib/components/podium/results_podium.dart
  ResultsPodium — the pure 3-bust stage widget. Given PodiumData, lays out the
    stack: 1st AvatarBust(forcePose: pose1, crop: bustTall, resolution ~176),
    2nd AvatarBust(forcePose: pose2, ~132) left-behind,
    3rd AvatarBust(forcePose: pose2, mirror: true, ~132) right-behind.
    Bottom gradient scrim + per-figure medal/name/points labels.

lib/components/podium/results_podium_sheet.dart
  Future<void> showResultsPodium(BuildContext, PodiumData) — wraps
    showModalBottomSheet with the house sheet chrome (reuse showBrandedSheet
    styling where it fits), handle + X + "Nice" dismiss, hosts ResultsPodium.
```

## Wiring (edits)

- `lib/state/home_cache_controller.dart` — fetch breakdown, run detection, expose
  `podiumPending` (one-shot). Inject `SeenResultsStore` (default real, overridable for
  tests).
- `lib/screens/home_screen.dart` — post-frame observer that presents the sheet once.
- `lib/screens/settings_screen.dart` — `if (kDebugMode)` row "Preview results podium"
  → builds `PodiumData` from newest real scored session or `PodiumData.sample()`, calls
  `showResultsPodium`.

## Visual reference

`docs/mockups/podium-modal.html` (stylized busts; the app uses real `AvatarBust`
liveries). Winner: gold spotlight + medal, larger name/points. 2nd/3rd darkened and
scaled to ~75%, sitting lower and behind. Bottom scrim fades the busts into the sheet.

## Error handling / edge cases

- No league / breakdown request fails / <3 scorers / no unseen session → no sheet,
  no error surfaced (best-effort, Home renders normally).
- Missing `avatarConfig` for a member → default avatar.
- Sheet shows once per app session even if Home rebuilds — guarded by clearing the
  pending flag on present.
- Dev preview never mutates the real seen-set.

## Testing

- `seen_results_store_test.dart` — round-trips the Set<int> via mocked
  SharedPreferences; markSeen is additive.
- `podium_detection_test.dart` — pure logic over fixture `SessionLeaderboardRow`
  lists: newest-unseen selection, ≥3 gate, tie-break ordering, avatar join, and the
  "mark all scored seen" backlog rule.
- `results_podium_smoke_test.dart` — pumps `ResultsPodium` with
  `PodiumData.sample()` (and a 3-entry fixture) and asserts no exception, mirroring
  the dark-ticket smoke test.

## Rollout

Single change set; feature is inert unless the user is in a league with ≥3 scored
members on the newest session. Dev-preview row lets us validate visuals immediately.
