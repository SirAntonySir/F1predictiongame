# Insights — Pre-Season Bets Tracker

**Date:** 2026-05-26
**Status:** Approved (pending user review of this document)
**Sub-project:** Flutter UI addition (parallel to backend rebuild)

## Context

The Flutter app's `InsightsTab` (`lib/screens/standings/insights_tab.dart`) is currently fully mocked — hardcoded "YOUR SEASON" stats, hardcoded trajectory chart, hardcoded league gossip cards.

The user has just shipped a pre-season questionnaire on the backend (sub-project 4): six categories + a full championship ordering, scored automatically as the season progresses. But the Flutter app has no backend wiring for auth or pre-season — picks live in `SharedPreferences` via `PreseasonStore`, and `ApiClient` exposes only the read-only F1 endpoints (events / sessions / results / standings / drivers / constructors).

This sub-project adds a new "PRE-SEASON BETS · LIVE TRACKING" section to `InsightsTab` that shows, for each derivable pre-season category, how the caller's local pick compares against the current F1 reality.

## Goal

Let the user open the Insights tab and immediately see "for the 132 trackable points of my pre-season questionnaire, where am I right now?" — with per-category cards showing pick vs current leader, ✓/✗ for each half (driver, team), and points-so-far / max.

Surprise + disappointment (16 pts) are deliberately excluded — they're admin-set at season end and there's nothing to "track" mid-season.

## Decisions

| # | Decision | Rationale |
|---|---|---|
| D1 | **Local-only computation** | Picks live in `PreseasonStore` (SharedPreferences); standings + results come from the existing `ApiClient`. No backend pre-season wiring needed yet. Ships in one PR. |
| D2 | **Exclude surprise + disappointment from the tracker** | Both are admin-set at season end. Nothing to compare against mid-season. Surface them on a future "results screen" instead. |
| D3 | **Five cards, all same layout** | DNFs, poles, fastest laps, WDC+WCC, championship. Uniform `PreseasonTrackerCard` widget. |
| D4 | **Championship card is a collapsed summary + tap-to-expand** | 20 drivers + 10 teams won't fit inline. Card shows "8 / 20 drivers correct, 4 / 10 teams correct", tap opens a bottom sheet with the full per-position breakdown. |
| D5 | **Lazy fetch for results-dependent cards** | WDC/WCC + championship render from standings (~1 RTT). DNFs / poles / FLs need iterating session results (~22 events × ~3 sessions = up to 66 calls). Standings cards paint immediately; results cards upgrade in place. |
| D6 | **No edit affordance — section is read-only** | Picks are locked once the season starts; this section displays them, doesn't mutate. |
| D7 | **Mirror the backend's scoring math exactly** | DNF status set, fastest-lap detection, position-1 tallies, tie-breaking, championship per-position +3/+4. If backend rules change, this client code is the second place to update — documented as a known coupling. |

## Architecture

```
InsightsTab
  └── PreseasonTrackerSection                 (NEW — owns data lifecycle)
        ├── PreseasonTrackerCard × 5          (NEW — uniform card widget)
        └── championship bottom sheet         (NEW — drill-down)

PreseasonTrackerSection
  reads ← AuthController (currentUserId), Season (current year)
  reads ← PreseasonStore (picks for the user/season)
  reads ← ApiClient.driverStandings(), .constructorStandings()    (eager)
  reads ← ApiClient.events() then per-session .sessionResults()    (lazy)
        ↓
PreseasonTrackerComputer.compute(picks, standings, results)        (pure)
        ↓
TrackerState { cards: [DnfStatus, PolesStatus, FlStatus, WdcWccStatus, ChampStatus] }
```

`PreseasonTrackerComputer` lives in `lib/domain/preseason_tracker.dart` — pure Dart, no Flutter, no SharedPreferences, no HTTP. Inputs are plain types, outputs are plain types. Testable in isolation.

## Components

### `lib/domain/preseason_tracker.dart` (new)

Pure functions matching the backend's `src/preseason/derive.ts` and the scorers in `src/preseason/singlePick.ts` + `standings.ts`.

```dart
class DerivedPair {
  final String? driverCode;
  final String? constructorId;
  const DerivedPair({this.driverCode, this.constructorId});
}

class CategoryStatus {
  final PreseasonCategory category;
  final PreseasonPick pick;                  // user's picks (from PreseasonStore)
  final DerivedPair? observed;               // null if data not loaded yet
  final int? pointsSoFar;                    // null while loading
  final int maxPoints;
  const CategoryStatus({...});

  bool get isLoading => observed == null;
  bool get driverMatch => pick.driverCode == observed?.driverCode && pick.driverCode != null;
  bool get teamMatch   => pick.constructorId == observed?.constructorId && pick.constructorId != null;
}

class ChampionshipStatus {
  final List<String> driverPicks;            // ordered
  final List<String> constructorPicks;       // ordered
  final List<DriverStanding>? driverTruth;   // null while loading
  final List<ConstructorStanding>? teamTruth;
  final int driversCorrect;
  final int teamsCorrect;
  final int pointsSoFar;
  final int maxPoints;                       // always 100
}

// Pure functions
DerivedPair deriveMostDnfs(List<SessionResult> results, List<Session> sessions);
DerivedPair derivePolesitter(List<SessionResult> results, List<Session> sessions);
DerivedPair deriveMostFastestLaps(List<SessionResult> results, List<Session> sessions);
DerivedPair deriveWdcWcc(List<DriverStanding> ds, List<ConstructorStanding> cs);

CategoryStatus computeSinglePick({
  required PreseasonCategory category,
  required PreseasonPick pick,
  required DerivedPair observed,
  required int pointsPerMatch,
});

ChampionshipStatus computeChampionship({
  required List<String> driverPicks,
  required List<String> constructorPicks,
  required List<DriverStanding> driverTruth,
  required List<ConstructorStanding> teamTruth,
});
```

DNF status set (must match backend `derive.ts`):
```dart
const _dnfStatuses = {
  'Retired', 'Accident', 'Engine', 'Collision',
  'Mechanical', 'Spun off', 'Withdrew', 'Did not start', 'Disqualified',
};
```

### `lib/components/preseason_tracker_card.dart` (new)

Stateless. Renders one `CategoryStatus` or `ChampionshipStatus`. Shape:

```
┌─────────────────────────────────────────────┐
│ MOST POLES                          4 / 8 pts│
│ ─────────────────────────────────────────── │
│  Driver   VER ✓     leader  VER             │
│  Team     red_bull ✓ leader  red_bull       │
└─────────────────────────────────────────────┘
```

- Border + corner radius from existing `AppCard` style.
- Title in `AppText.label(11)` like the existing `_h` helper in `insights_tab.dart`.
- Points-so-far rendered in `AppText.display(...)` style on the right.
- Driver/team rows with ✓ (green) or ✗ (red) inline next to the pick value.
- "leader" label uses `AppText.label(9)` muted color, leader value in `AppText.body(12)`.

Variant states:

- **Unfilled** (`pick.driverCode == null && pick.constructorId == null`): single line "No pick submitted", points show `– / 8 pts`.
- **Loading** (`observed == null`): leader values show `…`. Same height (no jump).
- **Error** (parent passes `error: true` + `onRetry`): leader values show `—`, retry icon `↻` in top-right corner.

Championship card has slightly different body:

```
┌─────────────────────────────────────────────┐
│ COMPLETE CHAMPIONSHIP            35 / 100 pts│
│ ─────────────────────────────────────────── │
│  Drivers   8 / 20 in correct slot           │
│  Teams     4 / 10 in correct slot           │
│                            See breakdown  › │
└─────────────────────────────────────────────┘
```

Tap → `showModalBottomSheet` with the per-position breakdown table:

```
P  | YOUR PICK    | CURRENTLY   |
1  | VER          | VER         | ✓
2  | HAM          | NOR         | ✗
...
```

Two sections in the sheet: Drivers (20 rows), Constructors (10 rows). Both scrollable.

### `lib/components/preseason_tracker_section.dart` (new)

Stateful — owns the data lifecycle.

```dart
class PreseasonTrackerSection extends StatefulWidget {
  final ApiClient api;
  final PreseasonStore store;
  final AuthController auth;
  final int seasonYear;
  ...
}

class _State extends State<PreseasonTrackerSection> {
  Future<List<DriverStanding>>? _driverStandingsFuture;
  Future<List<ConstructorStanding>>? _ctorStandingsFuture;
  Future<_ResultsBundle>? _resultsFuture;

  @override initState() {
    _driverStandingsFuture = widget.api.driverStandings();
    _ctorStandingsFuture   = widget.api.constructorStandings();
    _resultsFuture = _loadResults();    // events() + per-session sessionResults()
  }

  Future<_ResultsBundle> _loadResults() async {
    final events = await widget.api.events();
    final sessionsPerEvent = await Future.wait(events.map((e) => e.sessions));
    final finished = sessionsPerEvent.expand((s) => s).where((s) => s.status == 'finished').toList();
    final results = await Future.wait(finished.map((s) => widget.api.sessionResults(s.id)));
    return _ResultsBundle(finished, results.expand((r) => r).toList());
  }

  @override Widget build(ctx) {
    return FutureBuilder3<List<DriverStanding>, List<ConstructorStanding>, _ResultsBundle?>(
      // standings drive WDC/WCC + championship cards (eager)
      // results drive DNFs / poles / FL cards (lazy)
      ...
    );
  }
}
```

(`FutureBuilder3` is conceptual — the real implementation uses two nested `FutureBuilder`s or `Future.wait` + a single builder. Either pattern works.)

Empty-state guard: if `picks for all 5 trackable categories are null` AND `championship orderings are both empty`, render a single placeholder card.

### `lib/screens/standings/insights_tab.dart` (modify)

Add the section between `YOUR SEASON` and `TRAJECTORY`. ScopedRead pattern (already used elsewhere in the screen) to grab `api`, `store`, `auth`, season year.

```dart
_h('PRE-SEASON BETS · LIVE TRACKING'),
Padding(
  padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
  child: PreseasonTrackerSection(
    api: scope.api, store: scope.preseason, auth: scope.auth,
    seasonYear: currentSeason.year,
  ),
),
Padding(
  padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xs, Spacing.lg, 0),
  child: Text(
    'Surprise & disappointment (16 pts) scored at season end.',
    style: AppText.body(10, color: t.colorScheme.onSurface.withOpacity(0.55)),
  ),
),
```

## Data dependencies

Five cards × what each needs:

| Card | Needs | Source |
|---|---|---|
| DNFs | All session results for the season, filtered to race + sprint | `events()` + per-session `sessionResults()` |
| Poles | All qualifying session results | same fetch |
| Fastest laps | All race session results | same fetch |
| WDC + WCC | First row of each standings | `driverStandings()` + `constructorStandings()` |
| Championship | Full standings ordering | same as above |

Shared fetch: one batch of `events()` → fan out to `sessionResults()`. Cached for the section's lifetime — refetch only on `setState` from a retry tap.

## Empty / loading / error states

**Empty (no picks at all):** placeholder card replacing the 5 cards.

```
┌─────────────────────────────────────────────┐
│ NO PRE-SEASON BETS                          │
│ You didn't submit a questionnaire           │
│ for this season.                            │
└─────────────────────────────────────────────┘
```

**Partial empty:** filled cards render normally; unfilled cards show `– / N pts` and "No pick submitted".

**Loading:**
- Standings cards (WDC/WCC + championship) render with `…` placeholders until ~1 RTT.
- Results-dependent cards (DNFs / poles / FLs) show `…` in the leader slot until the lazy fan-out completes. Same height; no layout jump.

**Error:**
- Standings fetch fails → WDC/WCC + championship cards show `—` + retry. Other cards unaffected.
- Results fetch fails → DNFs / poles / FLs cards show `—` + retry. Standings cards unaffected.
- `PreseasonStore` load failure (rare, SharedPreferences exception): whole section degrades to the empty-state card. Acceptable.

**Lock state:**
Section is read-only — picks are already locked once the season has started. No "locked" badge, no edit affordance.

## Performance

- ~22 events × ~3 scorable sessions = up to ~66 `sessionResults()` calls. Run in parallel via `Future.wait`. Backend handles this in ~200ms total.
- Cards render their static portion (title, pick value, max points) on first frame. Leader values and points-so-far populate as data lands.
- No state retained across screen mounts. If the user navigates away and back, the section refetches. Acceptable given the data size.

## Testing

**Unit tests** (`test/preseason_tracker_test.dart`):

- `deriveMostDnfs`: tally across race + sprint, exclude qualifying. Driver and team match independently. Tie-breaking matches backend (`topCount` — first wins).
- `derivePolesitter`: `position == 1` across qualifying sessions only.
- `deriveMostFastestLaps`: `fastestLap == '1'` across race sessions only.
- `deriveWdcWcc`: position-1 of each standings.
- `computeSinglePick`: 4 cases — both match, driver only, team only, neither.
- `computeChampionship`: all correct, none correct, partial, picks shorter than truth, picks longer than truth.
- Empty pick → status with `pointsSoFar = 0`, no match indicators.
- All-null inputs → tracker computer returns "no picks" sentinel; caller renders empty-state.

**Widget tests:**

- `test/preseason_tracker_card_test.dart` — renders pick + leader + ✓/✗; renders `–` for unfilled; renders `…` while loading; renders `—` + retry on error.
- `test/preseason_tracker_section_test.dart` — mocks `ApiClient` + `PreseasonStore`. Verifies:
  - 5 cards render immediately with placeholders.
  - WDC/WCC + championship resolve from standings.
  - DNFs / poles / FLs resolve after lazy fetch.
  - Empty-state card renders when no picks at all.
  - Footer text "Surprise & disappointment scored at season end" present.

**Out of scope:** golden tests, network integration tests against the dev backend.

## Code layout

```
lib/
  domain/
    preseason_tracker.dart                 NEW
  components/
    preseason_tracker_card.dart            NEW
    preseason_tracker_section.dart         NEW
  screens/
    standings/
      insights_tab.dart                    MODIFY — insert section + footer
test/
  preseason_tracker_test.dart              NEW
  preseason_tracker_card_test.dart         NEW
  preseason_tracker_section_test.dart      NEW
```

## What's explicitly NOT in this sub-project

- Backend wiring (no `POST /api/auth/login`, no `GET /api/preseason/my`, no `GET /api/users/me/preseason-scores` calls). The tracker is purely local computation.
- Surprise/disappointment display — those have no live "track" semantics; they're admin-set at season end. A future "season-end results" surface can render them.
- Edit affordance — picks are locked once the season starts.
- Push notifications when a leader changes.
- Golden / visual regression tests.
- Refactoring the existing "YOUR SEASON" / "TRAJECTORY" / "LEAGUE GOSSIP" sections off their mock data — only adding the new tracker section here.

## Coupling note

The DNF status set, fastest-lap detection (`fastestLap == '1'`), pole detection (`position == 1` in `qualifying` sessions, NOT `sprint_quali`), and championship scoring constants (`+3` per driver, `+4` per team) MUST stay in sync with `backend/src/preseason/derive.ts`, `singlePick.ts`, and `standings.ts`. If the backend's scoring rules ever bump (e.g. `qualifying-v1` → `qualifying-v2`), this Dart code is the second place to update — there's no shared schema between client and server for these constants.
