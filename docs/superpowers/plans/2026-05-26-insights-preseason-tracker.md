# Insights Pre-Season Bets Tracker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a new "PRE-SEASON BETS · LIVE TRACKING" section to the Flutter `InsightsTab` showing 5 derivable preseason categories (DNFs / poles / fastest laps / WDC+WCC / championship) as live pick-vs-current-leader cards.

**Architecture:** One pure domain module (`preseason_tracker.dart`) that computes statuses from picks + standings + results. One uniform card widget (`PreseasonTrackerCard`) plus a bottom-sheet for the championship drill-down. One stateful section widget (`PreseasonTrackerSection`) that owns the data lifecycle — eager standings call drives WDC/WCC + championship cards, lazy events/results fan-out drives DNFs/poles/FL cards. Inserted into `InsightsTab` between `YOUR SEASON` and `TRAJECTORY`.

**Tech Stack:** Flutter 3.5+, Dart 3.5, existing app primitives (`AppCard`, `AppText`, `Spacing`, `BrandColors`), `mocktail` for widget-test mocks. No new packages.

**Spec:** `docs/superpowers/specs/2026-05-26-insights-preseason-tracker-design.md`

---

## File map

All paths relative to repo root.

| Path | Status | Responsibility |
|---|---|---|
| `lib/domain/preseason_tracker.dart` | Create | Pure compute layer: `DerivedPair`, `CategoryStatus`, `ChampionshipStatus`, derive + score functions |
| `lib/components/preseason_tracker_card.dart` | Create | `PreseasonTrackerCard` widget (uniform layout for 4 single-pick cards + 1 championship card with bottom-sheet) |
| `lib/components/preseason_tracker_section.dart` | Create | Stateful `PreseasonTrackerSection` that owns the fetch lifecycle and renders 5 cards |
| `lib/screens/standings/insights_tab.dart` | Modify | Insert `PreseasonTrackerSection` + footer between `YOUR SEASON` and `TRAJECTORY` |
| `test/domain/preseason_tracker_test.dart` | Create | Pure-function unit tests for the compute layer |
| `test/components/preseason_tracker_card_test.dart` | Create | Widget tests for the card variants (filled / unfilled / loading / error / championship) |
| `test/components/preseason_tracker_section_test.dart` | Create | Widget test of the full section with mocked `ApiClient` + `PreseasonStore` |

---

### Task 1: Pure domain layer + unit tests

**Files:**
- Create: `lib/domain/preseason_tracker.dart`
- Create: `test/domain/preseason_tracker_test.dart`

Pure functions. No Flutter import, no DB, no HTTP. Mirrors the backend's `src/preseason/derive.ts`, `singlePick.ts`, and `standings.ts` scoring exactly.

- [ ] **Step 1: Write the failing unit tests**

Create `test/domain/preseason_tracker_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/models/session.dart';
import 'package:predictiongame/api/models/session_result.dart';
import 'package:predictiongame/api/models/standing.dart';
import 'package:predictiongame/domain/preseason.dart';
import 'package:predictiongame/domain/preseason_tracker.dart';

Session _s(int id, SessionType type) => Session(
      id: id, type: type,
      scheduledStart: DateTime(2026, 1, 1),
      scheduledEnd: DateTime(2026, 1, 1, 2),
      status: SessionStatus.finished,
    );

SessionResult _r(int pos, String code, String team, {String? status, String? fl}) =>
    SessionResult(
      position: pos, driverCode: code, driverName: code,
      constructorId: team, constructorName: team,
      status: status, fastestLap: fl,
    );

DriverStanding _ds(int pos, String code, String team) =>
    DriverStanding(
      position: pos, driverCode: code, driverName: code,
      constructorId: team, points: 0, wins: 0,
    );

ConstructorStanding _cs(int pos, String team) =>
    ConstructorStanding(
      position: pos, constructorId: team, constructorName: team,
      points: 0, wins: 0,
    );

// session_id -> (sessionId, [results])
Map<int, List<SessionResult>> _byId(List<SessionResult> rows, int sessionId) =>
    {sessionId: rows};

void main() {
  group('deriveMostDnfs', () {
    test('counts DNF statuses across race + sprint, excludes qualifying', () {
      final sessions = [_s(1, SessionType.race), _s(2, SessionType.race), _s(3, SessionType.sprint), _s(4, SessionType.qualifying)];
      final results = <int, List<SessionResult>>{
        1: [_r(20, 'HAM', 'merc', status: 'Retired'), _r(19, 'RUS', 'merc', status: 'Engine')],
        2: [_r(18, 'HAM', 'merc', status: 'Collision')],
        3: [_r(18, 'HAM', 'merc', status: 'Accident')],
        4: [_r(20, 'HAM', 'merc', status: 'Engine')], // qualifying — excluded
      };
      final p = deriveMostDnfs(results, sessions);
      expect(p.driverCode, 'HAM');         // 3 DNFs counted (race + sprint only)
      expect(p.constructorId, 'merc');     // 4 (HAM x3 + RUS x1)
    });

    test('empty inputs yield nulls', () {
      expect(deriveMostDnfs({}, []), const DerivedPair());
    });
  });

  group('derivePolesitter', () {
    test('counts position 1 in qualifying only', () {
      final sessions = [_s(1, SessionType.qualifying), _s(2, SessionType.qualifying), _s(3, SessionType.sprint_quali)];
      final results = <int, List<SessionResult>>{
        1: [_r(1, 'VER', 'red_bull')],
        2: [_r(1, 'VER', 'red_bull')],
        3: [_r(1, 'HAM', 'merc')],  // sprint_quali — excluded
      };
      final p = derivePolesitter(results, sessions);
      expect(p.driverCode, 'VER');
      expect(p.constructorId, 'red_bull');
    });
  });

  group('deriveMostFastestLaps', () {
    test('counts fastestLap == "1" in race only', () {
      final sessions = [_s(1, SessionType.race), _s(2, SessionType.race), _s(3, SessionType.sprint)];
      final results = <int, List<SessionResult>>{
        1: [_r(1, 'VER', 'red_bull', fl: '1'), _r(2, 'HAM', 'merc', fl: '2')],
        2: [_r(5, 'VER', 'red_bull', fl: '1')],
        3: [_r(1, 'HAM', 'merc', fl: '1')],  // sprint — excluded
      };
      final p = deriveMostFastestLaps(results, sessions);
      expect(p.driverCode, 'VER');
    });
  });

  group('deriveWdcWcc', () {
    test('picks position 1 from each standings', () {
      final d = [_ds(1, 'VER', 'red_bull'), _ds(2, 'HAM', 'merc')];
      final c = [_cs(1, 'mclaren'), _cs(2, 'red_bull')];
      expect(deriveWdcWcc(d, c), const DerivedPair(driverCode: 'VER', constructorId: 'mclaren'));
    });

    test('empty standings yield nulls', () {
      expect(deriveWdcWcc(const [], const []), const DerivedPair());
    });
  });

  group('computeSinglePick', () {
    test('both match: 4 + 4 = 8', () {
      final s = computeSinglePick(
        category: PreseasonCategory.dnf,
        pick: const PreseasonPick(driverCode: 'VER', constructorId: 'red_bull'),
        observed: const DerivedPair(driverCode: 'VER', constructorId: 'red_bull'),
      );
      expect(s.driverMatch, true);
      expect(s.teamMatch, true);
      expect(s.pointsSoFar, 8);
    });

    test('only driver matches: 4', () {
      final s = computeSinglePick(
        category: PreseasonCategory.poles,
        pick: const PreseasonPick(driverCode: 'VER', constructorId: 'red_bull'),
        observed: const DerivedPair(driverCode: 'VER', constructorId: 'mercedes'),
      );
      expect(s.pointsSoFar, 4);
    });

    test('null pick → 0', () {
      final s = computeSinglePick(
        category: PreseasonCategory.fastest_lap,
        pick: const PreseasonPick(),
        observed: const DerivedPair(driverCode: 'VER', constructorId: 'red_bull'),
      );
      expect(s.driverMatch, false);
      expect(s.teamMatch, false);
      expect(s.pointsSoFar, 0);
    });

    test('null observed (e.g. no results yet) → 0 + observed remains null', () {
      final s = computeSinglePick(
        category: PreseasonCategory.dnf,
        pick: const PreseasonPick(driverCode: 'VER', constructorId: 'red_bull'),
        observed: const DerivedPair(),
      );
      expect(s.driverMatch, false);
      expect(s.teamMatch, false);
      expect(s.pointsSoFar, 0);
    });

    test('isUnfilled when both pick fields are null', () {
      final s = computeSinglePick(
        category: PreseasonCategory.wdc_wcc,
        pick: const PreseasonPick(),
        observed: const DerivedPair(driverCode: 'VER', constructorId: 'red_bull'),
      );
      expect(s.isUnfilled, true);
    });
  });

  group('computeChampionship', () {
    final truthDrivers = [_ds(1, 'VER', 'red_bull'), _ds(2, 'HAM', 'merc'), _ds(3, 'NOR', 'mclaren')];
    final truthTeams = [_cs(1, 'red_bull'), _cs(2, 'merc'), _cs(3, 'mclaren')];

    test('all correct', () {
      final c = computeChampionship(
        driverPicks: ['VER', 'HAM', 'NOR'],
        constructorPicks: ['red_bull', 'merc', 'mclaren'],
        driverTruth: truthDrivers,
        teamTruth: truthTeams,
      );
      expect(c.driversCorrect, 3);
      expect(c.teamsCorrect, 3);
      expect(c.pointsSoFar, 3 * 3 + 3 * 4);   // 21
    });

    test('partial: 1 driver + 1 team correct', () {
      final c = computeChampionship(
        driverPicks: ['VER', 'NOR', 'HAM'],
        constructorPicks: ['red_bull', 'mclaren', 'merc'],
        driverTruth: truthDrivers,
        teamTruth: truthTeams,
      );
      expect(c.driversCorrect, 1);
      expect(c.teamsCorrect, 1);
      expect(c.pointsSoFar, 3 + 4);
    });

    test('picks shorter than truth: only scored positions count', () {
      final c = computeChampionship(
        driverPicks: ['VER'],
        constructorPicks: ['red_bull'],
        driverTruth: truthDrivers,
        teamTruth: truthTeams,
      );
      expect(c.pointsSoFar, 3 + 4);
    });

    test('empty picks → 0', () {
      final c = computeChampionship(
        driverPicks: const [],
        constructorPicks: const [],
        driverTruth: truthDrivers,
        teamTruth: truthTeams,
      );
      expect(c.pointsSoFar, 0);
      expect(c.driversCorrect, 0);
      expect(c.teamsCorrect, 0);
    });

    test('isUnfilled when both pick lists empty', () {
      final c = computeChampionship(
        driverPicks: const [],
        constructorPicks: const [],
        driverTruth: truthDrivers,
        teamTruth: truthTeams,
      );
      expect(c.isUnfilled, true);
    });

    test('maxPoints reflects field size', () {
      final c = computeChampionship(
        driverPicks: const [],
        constructorPicks: const [],
        driverTruth: truthDrivers,
        teamTruth: truthTeams,
      );
      expect(c.maxPoints, 3 * 3 + 3 * 4);     // 21 with this fixture
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/domain/preseason_tracker_test.dart`
Expected: FAIL with "Target of URI doesn't exist" / unresolved imports.

- [ ] **Step 3: Implement `lib/domain/preseason_tracker.dart`**

```dart
import '../api/models/session.dart';
import '../api/models/session_result.dart';
import '../api/models/standing.dart';
import 'preseason.dart';

/// Driver + team observed-truth pair for a single-pick category.
class DerivedPair {
  final String? driverCode;
  final String? constructorId;
  const DerivedPair({this.driverCode, this.constructorId});

  @override
  bool operator ==(Object other) =>
      other is DerivedPair &&
      other.driverCode == driverCode &&
      other.constructorId == constructorId;

  @override
  int get hashCode => Object.hash(driverCode, constructorId);
}

/// Status of one single-pick category for the live tracker.
class CategoryStatus {
  final PreseasonCategory category;
  final PreseasonPick pick;
  final DerivedPair observed;
  final int pointsSoFar;
  final int maxPoints;

  const CategoryStatus({
    required this.category,
    required this.pick,
    required this.observed,
    required this.pointsSoFar,
    required this.maxPoints,
  });

  bool get driverMatch =>
      pick.driverCode != null &&
      observed.driverCode != null &&
      pick.driverCode == observed.driverCode;

  bool get teamMatch =>
      pick.constructorId != null &&
      observed.constructorId != null &&
      pick.constructorId == observed.constructorId;

  bool get isUnfilled => pick.isEmpty;
}

/// Status of the championship-ordering category.
class ChampionshipStatus {
  final List<String> driverPicks;
  final List<String> constructorPicks;
  final List<DriverStanding> driverTruth;
  final List<ConstructorStanding> teamTruth;
  final int driversCorrect;
  final int teamsCorrect;
  final int pointsSoFar;
  final int maxPoints;

  const ChampionshipStatus({
    required this.driverPicks,
    required this.constructorPicks,
    required this.driverTruth,
    required this.teamTruth,
    required this.driversCorrect,
    required this.teamsCorrect,
    required this.pointsSoFar,
    required this.maxPoints,
  });

  bool get isUnfilled => driverPicks.isEmpty && constructorPicks.isEmpty;
}

const _dnfStatuses = {
  'Retired', 'Accident', 'Engine', 'Collision',
  'Mechanical', 'Spun off', 'Withdrew', 'Did not start', 'Disqualified',
};

T? _topCount<T>(Map<T, int> counts) {
  T? best;
  int bestCount = 0;
  counts.forEach((k, v) {
    if (v > bestCount) {
      best = k;
      bestCount = v;
    }
  });
  return best;
}

DerivedPair deriveMostDnfs(
  Map<int, List<SessionResult>> resultsBySession,
  List<Session> sessions,
) {
  final eligible = <int>{
    for (final s in sessions)
      if (s.type == SessionType.race || s.type == SessionType.sprint) s.id,
  };
  final driverCounts = <String, int>{};
  final teamCounts = <String, int>{};
  for (final entry in resultsBySession.entries) {
    if (!eligible.contains(entry.key)) continue;
    for (final r in entry.value) {
      if (r.status == null || !_dnfStatuses.contains(r.status)) continue;
      driverCounts.update(r.driverCode, (n) => n + 1, ifAbsent: () => 1);
      teamCounts.update(r.constructorId, (n) => n + 1, ifAbsent: () => 1);
    }
  }
  return DerivedPair(
    driverCode: _topCount(driverCounts),
    constructorId: _topCount(teamCounts),
  );
}

DerivedPair derivePolesitter(
  Map<int, List<SessionResult>> resultsBySession,
  List<Session> sessions,
) {
  final eligible = <int>{
    for (final s in sessions)
      if (s.type == SessionType.qualifying) s.id,
  };
  final driverCounts = <String, int>{};
  final teamCounts = <String, int>{};
  for (final entry in resultsBySession.entries) {
    if (!eligible.contains(entry.key)) continue;
    for (final r in entry.value) {
      if (r.position != 1) continue;
      driverCounts.update(r.driverCode, (n) => n + 1, ifAbsent: () => 1);
      teamCounts.update(r.constructorId, (n) => n + 1, ifAbsent: () => 1);
    }
  }
  return DerivedPair(
    driverCode: _topCount(driverCounts),
    constructorId: _topCount(teamCounts),
  );
}

DerivedPair deriveMostFastestLaps(
  Map<int, List<SessionResult>> resultsBySession,
  List<Session> sessions,
) {
  final eligible = <int>{
    for (final s in sessions)
      if (s.type == SessionType.race) s.id,
  };
  final driverCounts = <String, int>{};
  final teamCounts = <String, int>{};
  for (final entry in resultsBySession.entries) {
    if (!eligible.contains(entry.key)) continue;
    for (final r in entry.value) {
      if (r.fastestLap != '1') continue;
      driverCounts.update(r.driverCode, (n) => n + 1, ifAbsent: () => 1);
      teamCounts.update(r.constructorId, (n) => n + 1, ifAbsent: () => 1);
    }
  }
  return DerivedPair(
    driverCode: _topCount(driverCounts),
    constructorId: _topCount(teamCounts),
  );
}

DerivedPair deriveWdcWcc(
  List<DriverStanding> drivers,
  List<ConstructorStanding> constructors,
) {
  String? wdc;
  String? wcc;
  for (final d in drivers) {
    if (d.position == 1) { wdc = d.driverCode; break; }
  }
  for (final c in constructors) {
    if (c.position == 1) { wcc = c.constructorId; break; }
  }
  return DerivedPair(driverCode: wdc, constructorId: wcc);
}

CategoryStatus computeSinglePick({
  required PreseasonCategory category,
  required PreseasonPick pick,
  required DerivedPair observed,
}) {
  const pointsPerMatch = 4;
  final maxPoints = preseasonMeta[category]!.max;
  int pts = 0;
  final driverMatch = pick.driverCode != null &&
      observed.driverCode != null &&
      pick.driverCode == observed.driverCode;
  final teamMatch = pick.constructorId != null &&
      observed.constructorId != null &&
      pick.constructorId == observed.constructorId;
  if (driverMatch) pts += pointsPerMatch;
  if (teamMatch) pts += pointsPerMatch;
  return CategoryStatus(
    category: category,
    pick: pick,
    observed: observed,
    pointsSoFar: pts,
    maxPoints: maxPoints,
  );
}

ChampionshipStatus computeChampionship({
  required List<String> driverPicks,
  required List<String> constructorPicks,
  required List<DriverStanding> driverTruth,
  required List<ConstructorStanding> teamTruth,
}) {
  final driverTruthByPos = {for (final d in driverTruth) d.position: d.driverCode};
  final teamTruthByPos = {for (final c in teamTruth) c.position: c.constructorId};

  int driversCorrect = 0;
  for (var i = 0; i < driverPicks.length; i++) {
    final pos = i + 1;
    if (driverTruthByPos[pos] == driverPicks[i]) driversCorrect++;
  }
  int teamsCorrect = 0;
  for (var i = 0; i < constructorPicks.length; i++) {
    final pos = i + 1;
    if (teamTruthByPos[pos] == constructorPicks[i]) teamsCorrect++;
  }
  final pts = driversCorrect * preseasonPointsPerDriverSlot +
      teamsCorrect * preseasonPointsPerConstructorSlot;
  final maxPts = driverTruth.length * preseasonPointsPerDriverSlot +
      teamTruth.length * preseasonPointsPerConstructorSlot;
  return ChampionshipStatus(
    driverPicks: driverPicks,
    constructorPicks: constructorPicks,
    driverTruth: driverTruth,
    teamTruth: teamTruth,
    driversCorrect: driversCorrect,
    teamsCorrect: teamsCorrect,
    pointsSoFar: pts,
    maxPoints: maxPts,
  );
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/domain/preseason_tracker_test.dart`
Expected: all ~15 tests pass.

- [ ] **Step 5: Run the full Flutter test suite + analyzer**

Run: `flutter test && flutter analyze`
Expected: existing tests still pass; analyze reports `No issues found!`.

- [ ] **Step 6: Commit**

```bash
git add lib/domain/preseason_tracker.dart test/domain/preseason_tracker_test.dart
git commit -m "flutter: pure preseason tracker compute layer + tests"
```

---

### Task 2: Card widget + bottom sheet + widget tests

**Files:**
- Create: `lib/components/preseason_tracker_card.dart`
- Create: `test/components/preseason_tracker_card_test.dart`

The card has 4 render variants:
1. **Filled single-pick** — driver row + team row, each with ✓ or ✗, plus a `leader` label
2. **Unfilled single-pick** — "No pick submitted", `– / 8 pts`
3. **Championship** — drivers correct count, teams correct count, "See breakdown ›" tap target opens a bottom sheet
4. **Loading** — `…` in leader slot; same height as filled
5. **Error** — `—` in leader slot + `↻` retry button (passed via `onRetry`)

- [ ] **Step 1: Write the failing widget tests**

Create `test/components/preseason_tracker_card_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/models/standing.dart';
import 'package:predictiongame/components/preseason_tracker_card.dart';
import 'package:predictiongame/domain/preseason.dart';
import 'package:predictiongame/domain/preseason_tracker.dart';
import 'package:predictiongame/theme/app_theme.dart';

Widget _frame(Widget c) => MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: SizedBox(width: 360, child: c)),
    );

void main() {
  testWidgets('filled single-pick: shows pick + leader + check marks + points', (tester) async {
    final status = CategoryStatus(
      category: PreseasonCategory.poles,
      pick: const PreseasonPick(driverCode: 'VER', constructorId: 'red_bull'),
      observed: const DerivedPair(driverCode: 'VER', constructorId: 'red_bull'),
      pointsSoFar: 8,
      maxPoints: 8,
    );
    await tester.pumpWidget(_frame(PreseasonTrackerCard.single(status: status)));
    expect(find.text('MOST POLES'), findsOneWidget);
    expect(find.text('8 / 8 pts'), findsOneWidget);
    expect(find.text('VER'), findsWidgets);              // pick and leader
    expect(find.text('red_bull'), findsWidgets);
    // tick markers (✓) for both rows
    expect(find.byIcon(Icons.check), findsNWidgets(2));
  });

  testWidgets('partial match: one ✓ and one ✗', (tester) async {
    final status = CategoryStatus(
      category: PreseasonCategory.dnf,
      pick: const PreseasonPick(driverCode: 'PER', constructorId: 'red_bull'),
      observed: const DerivedPair(driverCode: 'HAM', constructorId: 'red_bull'),
      pointsSoFar: 4,
      maxPoints: 8,
    );
    await tester.pumpWidget(_frame(PreseasonTrackerCard.single(status: status)));
    expect(find.text('4 / 8 pts'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);    // team matches
    expect(find.byIcon(Icons.close), findsOneWidget);    // driver doesn't
  });

  testWidgets('unfilled: shows "No pick submitted" and dash points', (tester) async {
    final status = CategoryStatus(
      category: PreseasonCategory.poles,
      pick: const PreseasonPick(),
      observed: const DerivedPair(driverCode: 'VER', constructorId: 'red_bull'),
      pointsSoFar: 0,
      maxPoints: 8,
    );
    await tester.pumpWidget(_frame(PreseasonTrackerCard.single(status: status)));
    expect(find.text('No pick submitted'), findsOneWidget);
    expect(find.text('– / 8 pts'), findsOneWidget);
  });

  testWidgets('loading: shows … in leader slot', (tester) async {
    final status = CategoryStatus(
      category: PreseasonCategory.dnf,
      pick: const PreseasonPick(driverCode: 'PER', constructorId: 'red_bull'),
      observed: const DerivedPair(),  // not yet known
      pointsSoFar: 0,
      maxPoints: 8,
    );
    await tester.pumpWidget(_frame(PreseasonTrackerCard.single(status: status, isLoading: true)));
    expect(find.text('…'), findsNWidgets(2));     // driver leader + team leader
  });

  testWidgets('error: shows — and retry button that fires callback', (tester) async {
    int retried = 0;
    final status = CategoryStatus(
      category: PreseasonCategory.dnf,
      pick: const PreseasonPick(driverCode: 'PER', constructorId: 'red_bull'),
      observed: const DerivedPair(),
      pointsSoFar: 0,
      maxPoints: 8,
    );
    await tester.pumpWidget(_frame(PreseasonTrackerCard.single(
      status: status,
      hasError: true,
      onRetry: () => retried++,
    )));
    expect(find.byIcon(Icons.refresh), findsOneWidget);
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump();
    expect(retried, 1);
  });

  testWidgets('championship: shows correct counts + breakdown affordance', (tester) async {
    final status = ChampionshipStatus(
      driverPicks: const ['VER', 'HAM'],
      constructorPicks: const ['red_bull'],
      driverTruth: const [
        DriverStanding(position: 1, driverCode: 'VER', driverName: 'V', constructorId: 'red_bull', points: 0, wins: 0),
        DriverStanding(position: 2, driverCode: 'NOR', driverName: 'N', constructorId: 'mclaren', points: 0, wins: 0),
      ],
      teamTruth: const [
        ConstructorStanding(position: 1, constructorId: 'red_bull', constructorName: 'rb', points: 0, wins: 0),
      ],
      driversCorrect: 1,
      teamsCorrect: 1,
      pointsSoFar: 3 + 4,
      maxPoints: 2 * 3 + 1 * 4,
    );
    await tester.pumpWidget(_frame(PreseasonTrackerCard.championship(status: status)));
    expect(find.text('COMPLETE CHAMPIONSHIP'), findsOneWidget);
    expect(find.text('7 / 10 pts'), findsOneWidget);
    expect(find.text('See breakdown'), findsOneWidget);
  });

  testWidgets('championship bottom-sheet opens on tap and lists positions', (tester) async {
    final status = ChampionshipStatus(
      driverPicks: const ['VER'],
      constructorPicks: const ['red_bull'],
      driverTruth: const [
        DriverStanding(position: 1, driverCode: 'VER', driverName: 'V', constructorId: 'red_bull', points: 0, wins: 0),
      ],
      teamTruth: const [
        ConstructorStanding(position: 1, constructorId: 'red_bull', constructorName: 'rb', points: 0, wins: 0),
      ],
      driversCorrect: 1,
      teamsCorrect: 1,
      pointsSoFar: 7,
      maxPoints: 7,
    );
    await tester.pumpWidget(_frame(PreseasonTrackerCard.championship(status: status)));
    await tester.tap(find.text('See breakdown'));
    await tester.pumpAndSettle();
    expect(find.text('DRIVERS'), findsOneWidget);
    expect(find.text('CONSTRUCTORS'), findsOneWidget);
    expect(find.text('VER'), findsWidgets);
    expect(find.text('red_bull'), findsWidgets);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/components/preseason_tracker_card_test.dart`
Expected: FAIL — `preseason_tracker_card.dart` not found.

- [ ] **Step 3: Implement `lib/components/preseason_tracker_card.dart`**

```dart
// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import '../api/models/standing.dart';
import '../domain/preseason.dart';
import '../domain/preseason_tracker.dart';
import '../theme/colors.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'app_card.dart';

class PreseasonTrackerCard extends StatelessWidget {
  final CategoryStatus? singleStatus;
  final ChampionshipStatus? championshipStatus;
  final bool isLoading;
  final bool hasError;
  final VoidCallback? onRetry;

  const PreseasonTrackerCard._({
    this.singleStatus,
    this.championshipStatus,
    this.isLoading = false,
    this.hasError = false,
    this.onRetry,
  });

  factory PreseasonTrackerCard.single({
    required CategoryStatus status,
    bool isLoading = false,
    bool hasError = false,
    VoidCallback? onRetry,
  }) =>
      PreseasonTrackerCard._(
        singleStatus: status,
        isLoading: isLoading,
        hasError: hasError,
        onRetry: onRetry,
      );

  factory PreseasonTrackerCard.championship({
    required ChampionshipStatus status,
    bool isLoading = false,
    bool hasError = false,
    VoidCallback? onRetry,
  }) =>
      PreseasonTrackerCard._(
        championshipStatus: status,
        isLoading: isLoading,
        hasError: hasError,
        onRetry: onRetry,
      );

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.md, Spacing.lg, Spacing.md),
      child: championshipStatus != null
          ? _Championship(
              status: championshipStatus!,
              isLoading: isLoading,
              hasError: hasError,
              onRetry: onRetry,
            )
          : _Single(
              status: singleStatus!,
              isLoading: isLoading,
              hasError: hasError,
              onRetry: onRetry,
            ),
    );
  }
}

class _Single extends StatelessWidget {
  final CategoryStatus status;
  final bool isLoading;
  final bool hasError;
  final VoidCallback? onRetry;
  const _Single({
    required this.status,
    required this.isLoading,
    required this.hasError,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final meta = preseasonMeta[status.category]!;
    final title = meta.title.toUpperCase();
    final pointsLabel = status.isUnfilled
        ? '– / ${status.maxPoints} pts'
        : '${status.pointsSoFar} / ${status.maxPoints} pts';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(title: title, points: pointsLabel, hasError: hasError, onRetry: onRetry),
        const SizedBox(height: Spacing.sm),
        const Divider(height: 1),
        const SizedBox(height: Spacing.sm),
        if (status.isUnfilled)
          Text('No pick submitted',
              style: AppText.body(13, color: t.colorScheme.onSurface.withOpacity(0.6)))
        else ...[
          _MatchRow(
            label: 'Driver',
            picked: status.pick.driverCode ?? '—',
            leader: hasError ? '—' : isLoading ? '…' : (status.observed.driverCode ?? '—'),
            matches: status.driverMatch,
            isLoading: isLoading,
            hasError: hasError,
          ),
          const SizedBox(height: Spacing.xs),
          _MatchRow(
            label: 'Team',
            picked: status.pick.constructorId ?? '—',
            leader: hasError ? '—' : isLoading ? '…' : (status.observed.constructorId ?? '—'),
            matches: status.teamMatch,
            isLoading: isLoading,
            hasError: hasError,
          ),
        ],
      ],
    );
  }
}

class _Championship extends StatelessWidget {
  final ChampionshipStatus status;
  final bool isLoading;
  final bool hasError;
  final VoidCallback? onRetry;
  const _Championship({
    required this.status,
    required this.isLoading,
    required this.hasError,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final pointsLabel = status.isUnfilled
        ? '– / ${status.maxPoints} pts'
        : '${status.pointsSoFar} / ${status.maxPoints} pts';
    final totalDrivers = status.driverTruth.length;
    final totalTeams = status.teamTruth.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(title: 'COMPLETE CHAMPIONSHIP', points: pointsLabel, hasError: hasError, onRetry: onRetry),
        const SizedBox(height: Spacing.sm),
        const Divider(height: 1),
        const SizedBox(height: Spacing.sm),
        if (status.isUnfilled)
          Text('No ordering submitted',
              style: AppText.body(13, color: t.colorScheme.onSurface.withOpacity(0.6)))
        else ...[
          Text(
            'Drivers   ${status.driversCorrect} / $totalDrivers in correct slot',
            style: AppText.body(12),
          ),
          const SizedBox(height: Spacing.xxs),
          Text(
            'Teams     ${status.teamsCorrect} / $totalTeams in correct slot',
            style: AppText.body(12),
          ),
          const SizedBox(height: Spacing.sm),
          InkWell(
            onTap: isLoading || hasError ? null : () => _openSheet(context),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  'See breakdown',
                  style: AppText.label(10, color: BrandColors.accent),
                ),
                const Icon(Icons.chevron_right, size: 16, color: BrandColors.accent),
              ],
            ),
          ),
        ],
      ],
    );
  }

  void _openSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ChampionshipSheet(status: status),
    );
  }
}

class _ChampionshipSheet extends StatelessWidget {
  final ChampionshipStatus status;
  const _ChampionshipSheet({required this.status});

  @override
  Widget build(BuildContext context) {
    final driverTruthByPos = {for (final d in status.driverTruth) d.position: d.driverCode};
    final teamTruthByPos = {for (final c in status.teamTruth) c.position: c.constructorId};

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('DRIVERS', style: AppText.label(10)),
              const SizedBox(height: Spacing.sm),
              ..._buildRows(status.driverPicks, driverTruthByPos),
              const SizedBox(height: Spacing.xl),
              Text('CONSTRUCTORS', style: AppText.label(10)),
              const SizedBox(height: Spacing.sm),
              ..._buildRows(status.constructorPicks, teamTruthByPos),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildRows(List<String> picks, Map<int, String> truthByPos) {
    return [
      for (var i = 0; i < picks.length; i++)
        _SheetRow(
          position: i + 1,
          picked: picks[i],
          truth: truthByPos[i + 1] ?? '—',
          matches: truthByPos[i + 1] == picks[i],
        ),
    ];
  }
}

class _SheetRow extends StatelessWidget {
  final int position;
  final String picked;
  final String truth;
  final bool matches;
  const _SheetRow({
    required this.position,
    required this.picked,
    required this.truth,
    required this.matches,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 24, child: Text('$position', style: AppText.label(11))),
          const SizedBox(width: Spacing.sm),
          Expanded(child: Text(picked, style: AppText.body(12))),
          const SizedBox(width: Spacing.sm),
          Expanded(child: Text(truth, style: AppText.body(12))),
          const SizedBox(width: Spacing.sm),
          Icon(
            matches ? Icons.check : Icons.close,
            size: 16,
            color: matches ? Colors.green : Colors.red,
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String title;
  final String points;
  final bool hasError;
  final VoidCallback? onRetry;
  const _Header({
    required this.title,
    required this.points,
    required this.hasError,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(title, style: AppText.label(11))),
        if (hasError && onRetry != null)
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.refresh, size: 18),
            onPressed: onRetry,
            tooltip: 'Retry',
          ),
        Text(points, style: AppText.label(11)),
      ],
    );
  }
}

class _MatchRow extends StatelessWidget {
  final String label;
  final String picked;
  final String leader;
  final bool matches;
  final bool isLoading;
  final bool hasError;
  const _MatchRow({
    required this.label,
    required this.picked,
    required this.leader,
    required this.matches,
    required this.isLoading,
    required this.hasError,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final showCheck = !isLoading && !hasError;
    return Row(
      children: [
        SizedBox(
          width: 48,
          child: Text(label, style: AppText.label(9,
              color: t.colorScheme.onSurface.withOpacity(0.55))),
        ),
        const SizedBox(width: Spacing.sm),
        Text(picked, style: AppText.body(12)),
        const SizedBox(width: 4),
        if (showCheck)
          Icon(
            matches ? Icons.check : Icons.close,
            size: 14,
            color: matches ? Colors.green : Colors.red,
          ),
        const Spacer(),
        Text('leader',
            style: AppText.label(9,
                color: t.colorScheme.onSurface.withOpacity(0.5))),
        const SizedBox(width: 4),
        Text(leader,
            style: AppText.body(12,
                color: t.colorScheme.onSurface.withOpacity(0.85))),
      ],
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/components/preseason_tracker_card_test.dart`
Expected: 7 tests pass.

- [ ] **Step 5: Run full suite + analyzer**

Run: `flutter test && flutter analyze`
Expected: green; analyze clean.

- [ ] **Step 6: Commit**

```bash
git add lib/components/preseason_tracker_card.dart test/components/preseason_tracker_card_test.dart
git commit -m "flutter: PreseasonTrackerCard widget + championship bottom sheet"
```

---

### Task 3: Section widget + InsightsTab integration + section tests

**Files:**
- Create: `lib/components/preseason_tracker_section.dart`
- Modify: `lib/screens/standings/insights_tab.dart`
- Create: `test/components/preseason_tracker_section_test.dart`

The section owns the data lifecycle: eager standings fetch (drives WDC/WCC + championship), lazy events-then-results fetch (drives DNF / poles / FL).

- [ ] **Step 1: Write failing section widget tests**

Create `test/components/preseason_tracker_section_test.dart`:

```dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:predictiongame/api/api_client.dart';
import 'package:predictiongame/api/models/constructor.dart';
import 'package:predictiongame/api/models/driver.dart';
import 'package:predictiongame/api/models/event.dart';
import 'package:predictiongame/api/models/season.dart';
import 'package:predictiongame/api/models/session.dart';
import 'package:predictiongame/api/models/session_result.dart';
import 'package:predictiongame/api/models/standing.dart';
import 'package:predictiongame/components/preseason_tracker_section.dart';
import 'package:predictiongame/domain/preseason.dart';
import 'package:predictiongame/state/preseason_store.dart';
import 'package:predictiongame/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockApi extends Mock implements ApiClient {}

/// Seeds a real PreseasonStore via SharedPreferences mock initial values.
/// Avoids fire-and-forget async calls that would trip `discarded_futures` lints.
Future<PreseasonStore> _seedStore({
  required String userId,
  required int seasonYear,
  Map<PreseasonCategory, PreseasonPick> picks = const {},
  List<String> drivers = const [],
  List<String> constructors = const [],
}) async {
  final entry = {
    'picks': picks.map((k, v) => MapEntry(k.name, {
          'driverCode': v.driverCode,
          'constructorId': v.constructorId,
        })),
    'drivers': drivers,
    'constructors': constructors,
  };
  SharedPreferences.setMockInitialValues({
    'preseason_v1': jsonEncode({'$userId:$seasonYear': entry}),
  });
  return PreseasonStore.load();
}

Event _ev(int round, List<Session> sessions) => Event(
      round: round, name: 'R$round', country: 'X', circuitName: 'C',
      hasSprint: false, sessions: sessions,
    );

Session _ses(int id, SessionType type, SessionStatus status) => Session(
      id: id, type: type,
      scheduledStart: DateTime(2026, 1, 1),
      scheduledEnd: DateTime(2026, 1, 1, 2),
      status: status,
    );

SessionResult _sr(int pos, String code, String team, {String? status, String? fl}) =>
    SessionResult(
      position: pos, driverCode: code, driverName: code,
      constructorId: team, constructorName: team,
      status: status, fastestLap: fl,
    );

Widget _frame(Widget c) => MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: SizedBox(width: 360, child: c)),
    );

void main() {
  late _MockApi api;

  setUp(() {
    api = _MockApi();
  });

  testWidgets('empty state when caller has no picks at all', (tester) async {
    final store = await _seedStore(userId: 'u1', seasonYear: 2026);
    when(() => api.driverStandings()).thenAnswer((_) async => const []);
    when(() => api.constructorStandings()).thenAnswer((_) async => const []);
    when(() => api.events()).thenAnswer((_) async => const []);

    await tester.pumpWidget(_frame(PreseasonTrackerSection(
      api: api, store: store, userId: 'u1', seasonYear: 2026,
    )));
    await tester.pumpAndSettle();
    expect(find.text('NO PRE-SEASON BETS'), findsOneWidget);
  });

  testWidgets('WDC/WCC + championship render from standings; DNFs upgrade after results', (tester) async {
    final store = await _seedStore(
      userId: 'u2',
      seasonYear: 2026,
      picks: {
        PreseasonCategory.wdc_wcc: const PreseasonPick(driverCode: 'VER', constructorId: 'red_bull'),
        PreseasonCategory.dnf: const PreseasonPick(driverCode: 'HAM', constructorId: 'merc'),
      },
      drivers: const ['VER'],
      constructors: const ['red_bull'],
    );

    when(() => api.driverStandings()).thenAnswer((_) async => [
          const DriverStanding(position: 1, driverCode: 'VER', driverName: 'V', constructorId: 'red_bull', points: 0, wins: 0),
        ]);
    when(() => api.constructorStandings()).thenAnswer((_) async => [
          const ConstructorStanding(position: 1, constructorId: 'red_bull', constructorName: 'rb', points: 0, wins: 0),
        ]);
    when(() => api.events()).thenAnswer((_) async => [
          _ev(1, [_ses(10, SessionType.race, SessionStatus.finished)]),
        ]);
    when(() => api.sessionResults(10)).thenAnswer((_) async => [
          _sr(20, 'HAM', 'merc', status: 'Retired'),
        ]);

    await tester.pumpWidget(_frame(PreseasonTrackerSection(
      api: api, store: store, userId: 'u2', seasonYear: 2026,
    )));
    await tester.pumpAndSettle();

    // WDC/WCC card resolved: 8/8 (both VER + red_bull correct)
    expect(find.text('WDC + WCC'), findsOneWidget);
    expect(find.text('8 / 8 pts'), findsOneWidget);
    // DNF card resolved: HAM has 1 retirement → driver match
    expect(find.text('MOST DNFS'), findsOneWidget);
    // championship: 1/1 drivers, 1/1 teams = 3+4 = 7
    expect(find.text('7 / 7 pts'), findsOneWidget);
  });

  testWidgets('section renders 5 cards when caller has at least one pick', (tester) async {
    final store = await _seedStore(
      userId: 'u3',
      seasonYear: 2026,
      picks: {PreseasonCategory.wdc_wcc: const PreseasonPick(driverCode: 'VER')},
    );
    when(() => api.driverStandings()).thenAnswer((_) async => const []);
    when(() => api.constructorStandings()).thenAnswer((_) async => const []);
    when(() => api.events()).thenAnswer((_) async => const []);

    await tester.pumpWidget(_frame(PreseasonTrackerSection(
      api: api, store: store, userId: 'u3', seasonYear: 2026,
    )));
    await tester.pumpAndSettle();
    // 5 cards: MOST DNFS, MOST POLES, MOST FASTEST LAPS, WDC + WCC, COMPLETE CHAMPIONSHIP
    expect(find.text('MOST DNFS'), findsOneWidget);
    expect(find.text('MOST POLES'), findsOneWidget);
    expect(find.text('MOST FASTEST LAPS'), findsOneWidget);
    expect(find.text('WDC + WCC'), findsOneWidget);
    expect(find.text('COMPLETE CHAMPIONSHIP'), findsOneWidget);
  });
}
```

Note: the section's "Surprise & disappointment scored at season end" footer is rendered by `InsightsTab` (the parent), not by `PreseasonTrackerSection` itself, so the footer text isn't part of these section-level tests.

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/components/preseason_tracker_section_test.dart`
Expected: FAIL — `preseason_tracker_section.dart` not found.

- [ ] **Step 3: Implement `lib/components/preseason_tracker_section.dart`**

```dart
// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../api/models/event.dart';
import '../api/models/session.dart';
import '../api/models/session_result.dart';
import '../api/models/standing.dart';
import '../domain/preseason.dart';
import '../domain/preseason_tracker.dart';
import '../state/preseason_store.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'app_card.dart';
import 'preseason_tracker_card.dart';

class PreseasonTrackerSection extends StatefulWidget {
  final ApiClient api;
  final PreseasonStore store;
  final String userId;
  final int seasonYear;

  const PreseasonTrackerSection({
    super.key,
    required this.api,
    required this.store,
    required this.userId,
    required this.seasonYear,
  });

  @override
  State<PreseasonTrackerSection> createState() => _PreseasonTrackerSectionState();
}

class _PreseasonTrackerSectionState extends State<PreseasonTrackerSection> {
  late Future<_StandingsBundle> _standingsFuture;
  late Future<_ResultsBundle> _resultsFuture;

  @override
  void initState() {
    super.initState();
    _standingsFuture = _loadStandings();
    _resultsFuture = _loadResults();
  }

  Future<_StandingsBundle> _loadStandings() async {
    final d = await widget.api.driverStandings();
    final c = await widget.api.constructorStandings();
    return _StandingsBundle(d, c);
  }

  Future<_ResultsBundle> _loadResults() async {
    final events = await widget.api.events();
    final sessions = <Session>[];
    final eligibleSessionIds = <int>[];
    for (final ev in events) {
      for (final s in ev.sessions) {
        sessions.add(s);
        if (s.status == SessionStatus.finished &&
            (s.type == SessionType.race ||
             s.type == SessionType.qualifying ||
             s.type == SessionType.sprint)) {
          eligibleSessionIds.add(s.id);
        }
      }
    }
    final results = await Future.wait(
      eligibleSessionIds.map((id) async => MapEntry(id, await widget.api.sessionResults(id))),
    );
    final byId = <int, List<SessionResult>>{};
    for (final entry in results) {
      byId[entry.key] = entry.value;
    }
    return _ResultsBundle(sessions, byId);
  }

  void _retryStandings() {
    setState(() => _standingsFuture = _loadStandings());
  }

  void _retryResults() {
    setState(() => _resultsFuture = _loadResults());
  }

  bool _isAllEmpty() {
    final hasAnyPick = PreseasonCategory.values.any((c) =>
        !widget.store.pickFor(userId: widget.userId, seasonYear: widget.seasonYear, category: c).isEmpty);
    final hasOrdering = widget.store
            .driverOrdering(userId: widget.userId, seasonYear: widget.seasonYear)
            .isNotEmpty ||
        widget.store
            .constructorOrdering(userId: widget.userId, seasonYear: widget.seasonYear)
            .isNotEmpty;
    return !hasAnyPick && !hasOrdering;
  }

  @override
  Widget build(BuildContext context) {
    if (_isAllEmpty()) {
      return AppCard(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('NO PRE-SEASON BETS', style: AppText.label(11)),
            const SizedBox(height: Spacing.sm),
            Text(
              "You didn't submit a questionnaire for this season.",
              style: AppText.body(12),
            ),
          ],
        ),
      );
    }

    return FutureBuilder<_StandingsBundle>(
      future: _standingsFuture,
      builder: (context, standingsSnap) {
        final standings = standingsSnap.data;
        final standingsLoading = standingsSnap.connectionState == ConnectionState.waiting;
        final standingsError = standingsSnap.hasError;

        return FutureBuilder<_ResultsBundle>(
          future: _resultsFuture,
          builder: (context, resultsSnap) {
            final results = resultsSnap.data;
            final resultsLoading = resultsSnap.connectionState == ConnectionState.waiting;
            final resultsError = resultsSnap.hasError;

            return Column(
              children: [
                _dnfCard(results, isLoading: resultsLoading, hasError: resultsError),
                const SizedBox(height: Spacing.xs),
                _polesCard(results, isLoading: resultsLoading, hasError: resultsError),
                const SizedBox(height: Spacing.xs),
                _flCard(results, isLoading: resultsLoading, hasError: resultsError),
                const SizedBox(height: Spacing.xs),
                _wdcWccCard(standings, isLoading: standingsLoading, hasError: standingsError),
                const SizedBox(height: Spacing.xs),
                _championshipCard(standings, isLoading: standingsLoading, hasError: standingsError),
              ],
            );
          },
        );
      },
    );
  }

  Widget _dnfCard(_ResultsBundle? data, {required bool isLoading, required bool hasError}) {
    final pick = widget.store.pickFor(
        userId: widget.userId, seasonYear: widget.seasonYear, category: PreseasonCategory.dnf);
    final observed = data == null
        ? const DerivedPair()
        : deriveMostDnfs(data.resultsBySession, data.sessions);
    final status = computeSinglePick(
      category: PreseasonCategory.dnf,
      pick: pick,
      observed: observed,
    );
    return PreseasonTrackerCard.single(
      status: status,
      isLoading: isLoading,
      hasError: hasError,
      onRetry: hasError ? _retryResults : null,
    );
  }

  Widget _polesCard(_ResultsBundle? data, {required bool isLoading, required bool hasError}) {
    final pick = widget.store.pickFor(
        userId: widget.userId, seasonYear: widget.seasonYear, category: PreseasonCategory.poles);
    final observed = data == null
        ? const DerivedPair()
        : derivePolesitter(data.resultsBySession, data.sessions);
    final status = computeSinglePick(
      category: PreseasonCategory.poles,
      pick: pick,
      observed: observed,
    );
    return PreseasonTrackerCard.single(
      status: status,
      isLoading: isLoading,
      hasError: hasError,
      onRetry: hasError ? _retryResults : null,
    );
  }

  Widget _flCard(_ResultsBundle? data, {required bool isLoading, required bool hasError}) {
    final pick = widget.store.pickFor(
        userId: widget.userId, seasonYear: widget.seasonYear, category: PreseasonCategory.fastest_lap);
    final observed = data == null
        ? const DerivedPair()
        : deriveMostFastestLaps(data.resultsBySession, data.sessions);
    final status = computeSinglePick(
      category: PreseasonCategory.fastest_lap,
      pick: pick,
      observed: observed,
    );
    return PreseasonTrackerCard.single(
      status: status,
      isLoading: isLoading,
      hasError: hasError,
      onRetry: hasError ? _retryResults : null,
    );
  }

  Widget _wdcWccCard(_StandingsBundle? data, {required bool isLoading, required bool hasError}) {
    final pick = widget.store.pickFor(
        userId: widget.userId, seasonYear: widget.seasonYear, category: PreseasonCategory.wdc_wcc);
    final observed = data == null
        ? const DerivedPair()
        : deriveWdcWcc(data.drivers, data.constructors);
    final status = computeSinglePick(
      category: PreseasonCategory.wdc_wcc,
      pick: pick,
      observed: observed,
    );
    return PreseasonTrackerCard.single(
      status: status,
      isLoading: isLoading,
      hasError: hasError,
      onRetry: hasError ? _retryStandings : null,
    );
  }

  Widget _championshipCard(_StandingsBundle? data, {required bool isLoading, required bool hasError}) {
    final driverPicks = widget.store
        .driverOrdering(userId: widget.userId, seasonYear: widget.seasonYear);
    final constructorPicks = widget.store
        .constructorOrdering(userId: widget.userId, seasonYear: widget.seasonYear);
    final status = computeChampionship(
      driverPicks: driverPicks.toList(),
      constructorPicks: constructorPicks.toList(),
      driverTruth: data?.drivers ?? const [],
      teamTruth: data?.constructors ?? const [],
    );
    return PreseasonTrackerCard.championship(
      status: status,
      isLoading: isLoading,
      hasError: hasError,
      onRetry: hasError ? _retryStandings : null,
    );
  }
}

class _StandingsBundle {
  final List<DriverStanding> drivers;
  final List<ConstructorStanding> constructors;
  _StandingsBundle(this.drivers, this.constructors);
}

class _ResultsBundle {
  final List<Session> sessions;
  final Map<int, List<SessionResult>> resultsBySession;
  _ResultsBundle(this.sessions, this.resultsBySession);
}
```

- [ ] **Step 4: Modify `lib/screens/standings/insights_tab.dart`**

Add the imports at the top of the file (after the existing imports):

```dart
import '../../components/preseason_tracker_section.dart';
import '../../state/app_state.dart';
```

Replace the existing `build` method's section list to insert the tracker between `YOUR SEASON` and `TRAJECTORY`. The full new `build`:

```dart
@override
Widget build(BuildContext context) {
  final t = Theme.of(context);
  final scope = AppState.of(context);
  final userId = scope.auth.currentUserId;
  final seasonYear = DateTime.now().year;

  return ListView(
    padding: const EdgeInsets.only(bottom: Spacing.xxl),
    children: [
      _h('YOUR SEASON'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: _stat(t, 'TOTAL POINTS', '148', '3rd of 5', accent: true)),
                const SizedBox(width: 6),
                Expanded(child: _stat(t, 'AVERAGE / ROUND', '21.1', 'league avg 19.6')),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(child: _stat(t, 'HIT RATE', '62%', '22 of 35 picks')),
                const SizedBox(width: 6),
                Expanded(child: _stat(t, 'BEST ROUND', '+24', 'Imola · R7')),
              ],
            ),
          ],
        ),
      ),
      _h('PRE-SEASON BETS · LIVE TRACKING'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
        child: userId == null
            ? Text(
                'Sign in to see your pre-season tracker.',
                style: AppText.body(12, color: t.colorScheme.onSurface.withOpacity(0.6)),
              )
            : PreseasonTrackerSection(
                api: scope.api,
                store: scope.preseason,
                userId: userId,
                seasonYear: seasonYear,
              ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xs, Spacing.lg, 0),
        child: Text(
          'Surprise & disappointment (16 pts) scored at season end.',
          style: AppText.body(10, color: t.colorScheme.onSurface.withOpacity(0.55)),
        ),
      ),
      _h('TRAJECTORY'),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: Spacing.lg),
        child: AppCard(
          child: TrajectoryChart(
            series: [
              ChartSeries(
                label: 'Lukas',
                color: Colors.black,
                points: [0, 25, 50, 75, 100, 125, 150, 167],
              ),
              ChartSeries(
                label: 'You',
                color: BrandColors.accent,
                points: [0, 18, 40, 56, 72, 90, 114, 148],
              ),
              ChartSeries(
                label: 'Avg',
                color: Color(0xFFBBBBBB),
                points: [0, 12, 25, 40, 55, 75, 100, 120],
              ),
            ],
            xLabels: ['R1', 'R2', 'R3', 'R4', 'R5', 'R6', 'R7', 'R8'],
          ),
        ),
      ),
      _h('LEAGUE GOSSIP'),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: Spacing.lg),
        child: Column(children: [
          FactCard(emblem: '★', text: 'Lukas has won 4 of 7 rounds — runaway form.'),
          SizedBox(height: 6),
          FactCard(emblem: '!?', text: "Paul missed last week's pick — first zero of the season."),
          SizedBox(height: 6),
          FactCard(emblem: '≈', text: 'Imola was the closest round: 4-point spread between top 4.'),
        ]),
      ),
    ],
  );
}
```

(Leave `_h(...)` and `_stat(...)` helper methods unchanged at the bottom of the file.)

- [ ] **Step 5: Run section widget tests**

Run: `flutter test test/components/preseason_tracker_section_test.dart`
Expected: 3 tests pass.

- [ ] **Step 6: Run full Flutter suite + analyzer + build sanity**

Run: `flutter test && flutter analyze`
Expected: all tests pass; analyze reports `No issues found!`.

- [ ] **Step 7: Visual smoke test on the simulator**

The dev backend + Flutter simulator should still be running from the prior session. Hot-reload picks up the changes automatically. Open the standings tab → swipe to Insights. Expect:

- 5 cards under "PRE-SEASON BETS · LIVE TRACKING"
- "Surprise & disappointment (16 pts) scored at season end." footer
- If the current user has no picks: a single "NO PRE-SEASON BETS" card

If the simulator isn't running, skip and rely on the widget tests.

- [ ] **Step 8: Commit**

```bash
git add lib/components/preseason_tracker_section.dart lib/screens/standings/insights_tab.dart test/components/preseason_tracker_section_test.dart
git commit -m "flutter: PreseasonTrackerSection + InsightsTab integration"
```

---

## Done

All 3 tasks complete means:

- `domain/preseason_tracker.dart` with 5 pure derive/compute functions and ~15 passing unit tests
- `PreseasonTrackerCard` widget with 5 variants and 7 passing widget tests
- `PreseasonTrackerSection` widget owning eager + lazy fetches with 3 passing integration-style widget tests
- `InsightsTab` rendering the new section between `YOUR SEASON` and `TRAJECTORY`, with the footer noting that surprise + disappointment are scored at season end
- `flutter test` + `flutter analyze` both clean
