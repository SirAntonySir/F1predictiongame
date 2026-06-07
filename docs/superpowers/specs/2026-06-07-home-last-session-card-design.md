# Home "Last race" card → last finished session

**Date:** 2026-06-07
**Status:** Approved (Approach A)

## Problem

The home screen's "LAST RACE" card always shows the most recent finished
**race**, deliberately skipping qualifying/sprint sessions. On a race weekend
where qualifying has already run but the race hasn't, the card is "one race
behind" — e.g. on Monaco race day it shows the two-week-stale *Canadian GP*
result instead of yesterday's *Monaco qualifying*.

Current selection ([home_cache_controller.dart:204](../../../lib/state/home_cache_controller.dart)):

```dart
final finishedRace = events.lastWhere(
  (e) => e.sessions.any((s) =>
      s.type == SessionType.race && s.status == SessionStatus.finished),
  ...
);
```

## Goal

The card shows the **last finished _scorable_ session** (race, qualifying,
sprint, sprint-quali — anything with `requiredPicks(type) > 0`; FP1–3 excluded),
with a type-aware label and a correctly-computed score.

Net effect today: "LAST RACE · CANADIAN GRAND PRIX" (Top 5) →
"LAST QUALI · MONACO GRAND PRIX" (Top 2).

## Approach A — generalize in place + share the scorer

### 1. Selection — `home_cache_controller.dart`
Replace "last event with a finished race" with "last finished scorable session",
chosen by **max `scheduledStart`** (do not rely on list order). Extract a pure,
testable helper:

```dart
({Event event, Session session})? selectLastScorableSession(List<Event> events)
```

Returns the event + session of the most recent finished session where
`requiredPicks(session.type) > 0`, or `null` if none has finished. The caller
fetches `api.sessionResults(session.id)` exactly as today, and the existing
null-guard keeps the card hidden when nothing has finished.

### 2. Label — `home_screen.dart:115`
`'Last race · ${d.lastEvent!.name}'` →
`'Last ${_sessionTypeLabel(session.type)} · ${d.lastEvent!.name}'`, reusing the
existing `_sessionTypeLabel` helper (returns `RACE` / `QUALI` / `SPRINT QUALI` /
`SPRINT`). The `_section` renderer already uppercases.

### 3. Type-correct scoring — `lib/domain/scoring.dart` + `_lastCard`
`_lastCard` currently calls `scoreRace(...)` unconditionally
([home_screen.dart:638](../../../lib/screens/home_screen.dart)), which is wrong
once the card can show a non-race session. Add a shared dispatcher:

```dart
int scoreSession(SessionType type, List<String> picks, List<SessionResult> result)
```

containing the switch that currently lives inline in
`session_results_screen.dart:382`. Use it in `_lastCard`, and refactor
`session_results_screen` to call it too (removes the duplicate switch).
`topN = requiredPicks(type)` and `outcomeFor(...)` are already type-generic —
unchanged.

### 4. Naming / scope line
`lastRaceSession` / `lastRaceHeader` now hold any scorable session — add a
clarifying comment but keep the names. Keep the `/race/{round}/{sessionId}`
route (already session-based). Renaming the field and route is **out of scope**
(that was Approach C).

## Testing (test-first)

Pure Dart unit tests:

- **`scoreSession`** dispatches per type: qualifying→`scoreQualifying`,
  sprint_quali→`scoreSprintQualifying`, sprint→`scoreSprint`, race→`scoreRace`.
- **`selectLastScorableSession`**:
  - latest finished session is a *qualifying* (Monaco scenario) with an earlier
    finished *race* → picks the qualifying session + its event.
  - only races have finished → picks the last race (regression guard).
  - nothing finished → returns `null` (card hidden).
  - FP-only finished sessions are ignored.

## Out of scope

- Renaming `lastRaceSession`/`lastRaceHeader`/the `/race/...` route (Approach C).
- The separate empty-picks data-loss bug found earlier (tracked separately).
- Any backend change.
