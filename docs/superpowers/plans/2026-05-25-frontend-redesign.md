# Frontend Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the Flutter app as 6 themed screens on a "Pop / Apparel" design system, wired to a typed `ApiClient` interface with mock + http implementations.

**Architecture:** `ApiClient` abstraction (mock today, HTTP later) → typed models. Three root `ChangeNotifier`s (Auth, League, Theme) + `PredictionsStore` exposed via `InheritedNotifier`. `go_router` with `ShellRoute` hosts the 4-tab bottom nav over an `IndexedStack`. Screen-local state stays `setState`. Component primitives live in `lib/components/`.

**Tech Stack:** Flutter ^3.5 / Dart ^3.5. Adds: `go_router`, `google_fonts`, `shared_preferences`, `intl`. Dev adds: `mocktail`.

**Spec:** `docs/superpowers/specs/2026-05-25-frontend-redesign-design.md`

---

## File map

| Path | Responsibility |
|---|---|
| `pubspec.yaml` | Add deps, register Anton/Inter fonts, register fixtures as assets |
| `lib/main.dart` | Bootstrap: build controllers, ApiClient factory, runApp |
| `lib/app.dart` | `MaterialApp.router`, theme wiring via `ListenableBuilder` |
| `lib/theme/tokens.dart` | Spacing, radii, strokes, durations |
| `lib/theme/colors.dart` | Brand + state + neutral palettes (light/dark) |
| `lib/theme/team_colors.dart` | Canonical team-colour map + aliases |
| `lib/theme/typography.dart` | Anton + Inter `TextStyle`s |
| `lib/theme/app_theme.dart` | `ThemeData.light()` + `.dark()` |
| `lib/api/api_client.dart` | Abstract interface |
| `lib/api/http_api_client.dart` | Real backend transport |
| `lib/api/mock_api_client.dart` | Fixture-backed |
| `lib/api/models/season.dart` | Season model |
| `lib/api/models/event.dart` | Event model |
| `lib/api/models/session.dart` | Session + SessionType enum |
| `lib/api/models/session_result.dart` | Result row model |
| `lib/api/models/driver.dart` | Driver model |
| `lib/api/models/constructor.dart` | Constructor model |
| `lib/api/models/standing.dart` | Driver + constructor standing models |
| `lib/mock/fixtures/*.json` | Bundled API fixtures |
| `lib/domain/prediction.dart` | `Pick`, `PredictionEntry` |
| `lib/domain/league.dart` | `League`, `Player` |
| `lib/domain/scoring.dart` | Pure scoring functions + `PickOutcome` |
| `lib/state/auth_controller.dart` | Current user + login stub |
| `lib/state/league_controller.dart` | Current league + members |
| `lib/state/theme_controller.dart` | Light/Dark/System + persistence |
| `lib/state/predictions_store.dart` | Local picks + persistence |
| `lib/state/app_state.dart` | `InheritedNotifier` wrapper |
| `lib/nav/router.dart` | `GoRouter` config |
| `lib/nav/app_shell.dart` | Shell + `IndexedStack` |
| `lib/components/app_card.dart` | Foundation card |
| `lib/components/trend_badge.dart` | ▲/▼/━ pill |
| `lib/components/session_chip.dart` | FP/Q/R chips |
| `lib/components/countdown.dart` | D/H/M ticker |
| `lib/components/race_tile.dart` | Calendar row tile |
| `lib/components/pod_tile.dart` | Podium block |
| `lib/components/driver_tile.dart` | 4-col driver grid tile |
| `lib/components/slot.dart` | Numbered pick slot |
| `lib/components/league_row.dart` | Leaderboard row |
| `lib/components/score_banner.dart` | Red score hero |
| `lib/components/fact_card.dart` | Gossip card |
| `lib/components/trajectory_chart.dart` | Custom-painted line chart |
| `lib/components/bottom_nav.dart` | 4-tab nav bar |
| `lib/screens/login_screen.dart` | Pick-a-user stub |
| `lib/screens/home_screen.dart` | Home tab |
| `lib/screens/calendar_screen.dart` | Calendar tab |
| `lib/screens/predict_screen.dart` | Predict tab |
| `lib/screens/session_results_screen.dart` | Race drill-down |
| `lib/screens/standings/standings_screen.dart` | Standings tab shell |
| `lib/screens/standings/league_tab.dart` | League sub-tab |
| `lib/screens/standings/f1_tab.dart` | F1 sub-tab |
| `lib/screens/standings/insights_tab.dart` | Insights sub-tab |
| `lib/screens/settings_screen.dart` | Theme toggle, sign out, about |
| `test/**/` | Mirrors `lib/` layout |
| `test/goldens/*.png` | Snapshot baselines |

---

### Task 1: Clean slate + dependencies

**Files:**
- Modify: `pubspec.yaml`
- Delete: `lib/Screens/live_data_screen.dart`, `lib/Screens/live_table_screen.dart`, `lib/Screens/prediction_input_screen.dart`
- Delete: `lib/Components/countdown_widget.dart`, `lib/Components/prediction_input_widget.dart`
- Delete: `lib/Screens/`, `lib/Components/` (empty directories after file removal)
- Modify: `lib/main.dart` (placeholder app that compiles)
- Modify: `test/widget_test.dart` (replace stale boilerplate)

- [ ] **Step 1: Replace `pubspec.yaml`**

```yaml
name: predictiongame
description: "F1 prediction game."
publish_to: "none"
version: 1.0.0+1

environment:
  sdk: ^3.5.4

dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8
  http: ^0.13.3
  go_router: ^14.6.1
  google_fonts: ^6.2.1
  shared_preferences: ^2.3.3
  intl: ^0.19.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^4.0.0
  mocktail: ^1.0.4

flutter:
  uses-material-design: true
  assets:
    - lib/mock/fixtures/
```

- [ ] **Step 2: Delete old screens & components**

Run:
```bash
rm -rf lib/Screens lib/Components
```

- [ ] **Step 3: Replace `lib/main.dart` with a minimal placeholder**

```dart
import 'package:flutter/material.dart';

void main() {
  runApp(const F1PgApp());
}

class F1PgApp extends StatelessWidget {
  const F1PgApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'F1PG',
      home: Scaffold(body: Center(child: Text('F1PG'))),
    );
  }
}
```

- [ ] **Step 4: Replace `test/widget_test.dart` with a passing smoke test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/main.dart';

void main() {
  testWidgets('App boots and shows brand placeholder', (tester) async {
    await tester.pumpWidget(const F1PgApp());
    expect(find.text('F1PG'), findsOneWidget);
  });
}
```

- [ ] **Step 5: Install deps and verify**

Run:
```bash
flutter pub get
flutter analyze
flutter test
```
Expected: `flutter analyze` clean (0 issues), `flutter test` PASS (1 test).

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/ test/
git commit -m "chore: clean slate + add redesign deps (go_router, fonts, prefs, intl)"
```

---

### Task 2: Theme tokens, colours, team colours, typography

**Files:**
- Create: `lib/theme/tokens.dart`
- Create: `lib/theme/colors.dart`
- Create: `lib/theme/team_colors.dart`
- Create: `lib/theme/typography.dart`
- Create: `test/theme/team_colors_test.dart`

- [ ] **Step 1: Write failing team-colours test**

`test/theme/team_colors_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/theme/team_colors.dart';

void main() {
  test('resolves canonical constructor ids', () {
    expect(teamColor('red_bull'), const Color(0xFF1E41FF));
    expect(teamColor('ferrari'), const Color(0xFFE8002D));
    expect(teamColor('mclaren'), const Color(0xFFFF8000));
    expect(teamColor('mercedes'), const Color(0xFF27F4D2));
  });

  test('resolves renamed/aliased constructor ids', () {
    expect(teamColor('alphatauri'), teamColor('rb'));
    expect(teamColor('alfa'), teamColor('kick_sauber'));
    expect(teamColor('sauber'), teamColor('kick_sauber'));
  });

  test('falls back to a neutral colour for unknown ids', () {
    expect(teamColor('not_a_team'), const Color(0xFF707070));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/theme/team_colors_test.dart`
Expected: FAIL — `team_colors.dart` does not exist.

- [ ] **Step 3: Create `lib/theme/tokens.dart`**

```dart
import 'package:flutter/material.dart';

class Spacing {
  static const double xxs = 4;
  static const double xs = 6;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 14;
  static const double xl = 18;
  static const double xxl = 24;
}

class Radii {
  static const Radius sm = Radius.circular(8);
  static const Radius md = Radius.circular(12);
  static const Radius lg = Radius.circular(14);
  static const Radius xl = Radius.circular(18);
  static const Radius pill = Radius.circular(999);

  static const BorderRadius rSm = BorderRadius.all(sm);
  static const BorderRadius rMd = BorderRadius.all(md);
  static const BorderRadius rLg = BorderRadius.all(lg);
  static const BorderRadius rXl = BorderRadius.all(xl);
  static const BorderRadius rPill = BorderRadius.all(pill);
}

class Strokes {
  static const double subtle = 1.5;
  static const double card = 2;
}

class Durations {
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration tick = Duration(seconds: 1);
}
```

- [ ] **Step 4: Create `lib/theme/colors.dart`**

```dart
import 'package:flutter/material.dart';

class BrandColors {
  static const Color accent = Color(0xFFE10600);
  static const Color ok = Color(0xFF19D36B);
  static const Color near = Color(0xFFFFD233);
  static const Color miss = Color(0xFF000000);
  static const Color live = Color(0xFFE10600);
}

class LightPalette {
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFFAFAFA);
  static const Color stroke = Color(0xFF000000);
  static const Color onSurface = Color(0xFF111111);
  static const Color onSurfaceMuted = Color(0xFF707070);
  static const Color highlight = Color(0xFFFFF7D1);
}

class DarkPalette {
  static const Color surface = Color(0xFF0E0E10);
  static const Color surfaceMuted = Color(0xFF16161A);
  static const Color stroke = Color(0xFF2A2A2E);
  static const Color onSurface = Color(0xFFF2F2F2);
  static const Color onSurfaceMuted = Color(0xFF9A9A9E);
  static const Color highlight = Color(0xFF2B2B0E);
}
```

- [ ] **Step 5: Create `lib/theme/team_colors.dart`**

```dart
import 'package:flutter/material.dart';

const Map<String, Color> _teamColors = {
  'red_bull': Color(0xFF1E41FF),
  'ferrari': Color(0xFFE8002D),
  'mclaren': Color(0xFFFF8000),
  'mercedes': Color(0xFF27F4D2),
  'aston_martin': Color(0xFF229971),
  'alpine': Color(0xFF0093CC),
  'kick_sauber': Color(0xFF52E252),
  'rb': Color(0xFF6692FF),
  'haas': Color(0xFFB6BABD),
  'williams': Color(0xFF64C4FF),
};

const Map<String, String> _aliases = {
  'alphatauri': 'rb',
  'alpha_tauri': 'rb',
  'alfa': 'kick_sauber',
  'alfa_romeo': 'kick_sauber',
  'sauber': 'kick_sauber',
};

const Color _fallback = Color(0xFF707070);

Color teamColor(String constructorId) {
  final id = _aliases[constructorId] ?? constructorId;
  return _teamColors[id] ?? _fallback;
}
```

- [ ] **Step 6: Create `lib/theme/typography.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppText {
  static TextStyle display(double size, {Color? color}) =>
      GoogleFonts.anton(
        fontSize: size,
        height: 1.0,
        letterSpacing: -size * 0.03,
        color: color,
      );

  static TextStyle body(double size, {FontWeight? weight, Color? color}) =>
      GoogleFonts.inter(
        fontSize: size,
        height: 1.4,
        fontWeight: weight ?? FontWeight.w500,
        color: color,
      );

  static TextStyle label(double size, {Color? color}) => GoogleFonts.inter(
        fontSize: size,
        height: 1.0,
        fontWeight: FontWeight.w800,
        letterSpacing: size <= 9 ? 2.0 : 1.5,
        color: color,
      );
}
```

- [ ] **Step 7: Run team-colours test**

Run: `flutter test test/theme/team_colors_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 8: Commit**

```bash
git add lib/theme/ test/theme/
git commit -m "feat(theme): tokens, palettes, team colours, typography"
```

---

### Task 3: App theme + wire to main

**Files:**
- Create: `lib/theme/app_theme.dart`
- Modify: `lib/main.dart`
- Modify: `test/widget_test.dart`

- [ ] **Step 1: Write failing test for theme application**

Replace `test/widget_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/main.dart';
import 'package:predictiongame/theme/colors.dart';

void main() {
  testWidgets('Light theme uses the brand surface', (tester) async {
    await tester.pumpWidget(const F1PgApp());
    final BuildContext ctx = tester.element(find.byType(Scaffold));
    expect(Theme.of(ctx).scaffoldBackgroundColor, LightPalette.surface);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget_test.dart`
Expected: FAIL (theme is default Material).

- [ ] **Step 3: Create `lib/theme/app_theme.dart`**

```dart
import 'package:flutter/material.dart';
import 'colors.dart';
import 'tokens.dart';
import 'typography.dart';

class AppTheme {
  static ThemeData light() => _build(
        brightness: Brightness.light,
        surface: LightPalette.surface,
        surfaceMuted: LightPalette.surfaceMuted,
        stroke: LightPalette.stroke,
        onSurface: LightPalette.onSurface,
      );

  static ThemeData dark() => _build(
        brightness: Brightness.dark,
        surface: DarkPalette.surface,
        surfaceMuted: DarkPalette.surfaceMuted,
        stroke: DarkPalette.stroke,
        onSurface: DarkPalette.onSurface,
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color surface,
    required Color surfaceMuted,
    required Color stroke,
    required Color onSurface,
  }) {
    final base = brightness == Brightness.light
        ? ThemeData.light(useMaterial3: true)
        : ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: surface,
      colorScheme: base.colorScheme.copyWith(
        primary: BrandColors.accent,
        surface: surface,
        onSurface: onSurface,
        outline: stroke,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: onSurface,
        displayColor: onSurface,
        fontFamily: AppText.body(14).fontFamily,
      ),
      extensions: <ThemeExtension<dynamic>>[
        _AppSurfaces(muted: surfaceMuted, stroke: stroke),
      ],
    );
  }
}

class _AppSurfaces extends ThemeExtension<_AppSurfaces> {
  final Color muted;
  final Color stroke;
  const _AppSurfaces({required this.muted, required this.stroke});

  @override
  _AppSurfaces copyWith({Color? muted, Color? stroke}) => _AppSurfaces(
        muted: muted ?? this.muted,
        stroke: stroke ?? this.stroke,
      );

  @override
  _AppSurfaces lerp(ThemeExtension<_AppSurfaces>? other, double t) {
    if (other is! _AppSurfaces) return this;
    return _AppSurfaces(
      muted: Color.lerp(muted, other.muted, t)!,
      stroke: Color.lerp(stroke, other.stroke, t)!,
    );
  }
}

extension AppSurfacesX on ThemeData {
  Color get mutedSurface => extension<_AppSurfaces>()?.muted ?? LightPalette.surfaceMuted;
  Color get strokeColor => extension<_AppSurfaces>()?.stroke ?? LightPalette.stroke;
}
```

- [ ] **Step 4: Update `lib/main.dart`**

```dart
import 'package:flutter/material.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const F1PgApp());
}

class F1PgApp extends StatelessWidget {
  const F1PgApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'F1PG',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: const Scaffold(body: Center(child: Text('F1PG'))),
    );
  }
}
```

- [ ] **Step 5: Run tests + analyze**

Run: `flutter analyze && flutter test`
Expected: analyze clean; test PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/theme/app_theme.dart lib/main.dart test/widget_test.dart
git commit -m "feat(theme): light + dark ThemeData wired to MaterialApp"
```

---

### Task 4: API models with fromJson

**Files:**
- Create: `lib/api/models/season.dart`
- Create: `lib/api/models/event.dart`
- Create: `lib/api/models/session.dart`
- Create: `lib/api/models/session_result.dart`
- Create: `lib/api/models/driver.dart`
- Create: `lib/api/models/constructor.dart`
- Create: `lib/api/models/standing.dart`
- Create: `test/api/models/models_test.dart`

- [ ] **Step 1: Write failing model tests**

`test/api/models/models_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/models/season.dart';
import 'package:predictiongame/api/models/event.dart';
import 'package:predictiongame/api/models/session.dart';
import 'package:predictiongame/api/models/session_result.dart';
import 'package:predictiongame/api/models/driver.dart';
import 'package:predictiongame/api/models/constructor.dart';
import 'package:predictiongame/api/models/standing.dart';

void main() {
  test('Season.fromJson', () {
    final s = Season.fromJson({'year': 2026, 'isCurrent': true});
    expect(s.year, 2026);
    expect(s.isCurrent, true);
  });

  test('Event.fromJson with sessions', () {
    final e = Event.fromJson({
      'round': 8,
      'name': 'Monaco Grand Prix',
      'country': 'Monaco',
      'circuitName': 'Circuit de Monaco',
      'hasSprint': false,
      'sessions': [
        {
          'id': 42,
          'type': 'race',
          'scheduledStart': '2026-05-26T13:00:00Z',
          'scheduledEnd': '2026-05-26T15:00:00Z',
          'status': 'scheduled',
        }
      ],
    });
    expect(e.round, 8);
    expect(e.name, 'Monaco Grand Prix');
    expect(e.hasSprint, false);
    expect(e.sessions.first.type, SessionType.race);
  });

  test('SessionType parses all enum values', () {
    for (final s in const [
      'fp1', 'fp2', 'fp3', 'qualifying', 'sprint_quali', 'sprint', 'race'
    ]) {
      expect(SessionType.values.byName(s).name, s);
    }
  });

  test('SessionResult.fromJson handles nullable fields', () {
    final r = SessionResult.fromJson({
      'position': 1,
      'driverCode': 'VER',
      'driverName': 'Max Verstappen',
      'constructorId': 'red_bull',
      'constructorName': 'Red Bull',
      'raceTime': '1:33:15',
      'status': 'Finished',
      'points': 25,
      'fastestLap': null,
    });
    expect(r.position, 1);
    expect(r.driverCode, 'VER');
    expect(r.points, 25);
    expect(r.fastestLap, isNull);
  });

  test('Driver.fromJson with image fallback', () {
    final d = Driver.fromJson({
      'code': 'VER',
      'givenName': 'Max',
      'familyName': 'Verstappen',
      'nationality': 'Dutch',
      'permanentNumber': 1,
      'image': null,
    });
    expect(d.code, 'VER');
    expect(d.image, isNull);
  });

  test('Constructor.fromJson', () {
    final c = Constructor.fromJson({
      'id': 'red_bull',
      'name': 'Red Bull',
      'nationality': 'Austrian',
      'image': 'https://example.com/rb.png',
    });
    expect(c.id, 'red_bull');
    expect(c.image, 'https://example.com/rb.png');
  });

  test('DriverStanding.fromJson', () {
    final s = DriverStanding.fromJson({
      'position': 1,
      'driverCode': 'VER',
      'driverName': 'Max Verstappen',
      'constructorId': 'red_bull',
      'points': 200,
      'wins': 6,
      'image': null,
    });
    expect(s.position, 1);
    expect(s.points, 200);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/api/models/models_test.dart`
Expected: FAIL — model files missing.

- [ ] **Step 3: Create `lib/api/models/season.dart`**

```dart
class Season {
  final int year;
  final bool isCurrent;
  const Season({required this.year, required this.isCurrent});
  factory Season.fromJson(Map<String, dynamic> j) =>
      Season(year: j['year'] as int, isCurrent: j['isCurrent'] as bool);
}
```

- [ ] **Step 4: Create `lib/api/models/session.dart`**

```dart
enum SessionType { fp1, fp2, fp3, qualifying, sprint_quali, sprint, race }

enum SessionStatus { scheduled, finished }

class Session {
  final int id;
  final SessionType type;
  final DateTime scheduledStart;
  final DateTime scheduledEnd;
  final SessionStatus status;

  const Session({
    required this.id,
    required this.type,
    required this.scheduledStart,
    required this.scheduledEnd,
    required this.status,
  });

  factory Session.fromJson(Map<String, dynamic> j) => Session(
        id: j['id'] as int,
        type: SessionType.values.byName(j['type'] as String),
        scheduledStart: DateTime.parse(j['scheduledStart'] as String).toLocal(),
        scheduledEnd: DateTime.parse(j['scheduledEnd'] as String).toLocal(),
        status: SessionStatus.values.byName(j['status'] as String),
      );
}
```

- [ ] **Step 5: Create `lib/api/models/event.dart`**

```dart
import 'session.dart';

class Event {
  final int round;
  final String name;
  final String country;
  final String circuitName;
  final bool hasSprint;
  final List<Session> sessions;

  const Event({
    required this.round,
    required this.name,
    required this.country,
    required this.circuitName,
    required this.hasSprint,
    required this.sessions,
  });

  factory Event.fromJson(Map<String, dynamic> j) => Event(
        round: j['round'] as int,
        name: j['name'] as String,
        country: j['country'] as String,
        circuitName: j['circuitName'] as String,
        hasSprint: j['hasSprint'] as bool,
        sessions: ((j['sessions'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(Session.fromJson)
            .toList(),
      );
}
```

- [ ] **Step 6: Create `lib/api/models/session_result.dart`**

```dart
class SessionResult {
  final int position;
  final String driverCode;
  final String driverName;
  final String constructorId;
  final String constructorName;
  final String? raceTime;
  final String? status;
  final int? points;
  final String? fastestLap;
  final String? fastestLapTime;
  final String? fastestLapSpeed;
  final String? q1;
  final String? q2;
  final String? q3;

  const SessionResult({
    required this.position,
    required this.driverCode,
    required this.driverName,
    required this.constructorId,
    required this.constructorName,
    this.raceTime,
    this.status,
    this.points,
    this.fastestLap,
    this.fastestLapTime,
    this.fastestLapSpeed,
    this.q1,
    this.q2,
    this.q3,
  });

  factory SessionResult.fromJson(Map<String, dynamic> j) => SessionResult(
        position: j['position'] as int,
        driverCode: j['driverCode'] as String,
        driverName: j['driverName'] as String,
        constructorId: j['constructorId'] as String,
        constructorName: j['constructorName'] as String,
        raceTime: j['raceTime'] as String?,
        status: j['status'] as String?,
        points: j['points'] as int?,
        fastestLap: j['fastestLap'] as String?,
        fastestLapTime: j['fastestLapTime'] as String?,
        fastestLapSpeed: j['fastestLapSpeed'] as String?,
        q1: j['q1'] as String?,
        q2: j['q2'] as String?,
        q3: j['q3'] as String?,
      );
}
```

- [ ] **Step 7: Create `lib/api/models/driver.dart`**

```dart
class Driver {
  final String code;
  final String givenName;
  final String familyName;
  final String nationality;
  final int? permanentNumber;
  final String? image;

  const Driver({
    required this.code,
    required this.givenName,
    required this.familyName,
    required this.nationality,
    this.permanentNumber,
    this.image,
  });

  factory Driver.fromJson(Map<String, dynamic> j) => Driver(
        code: j['code'] as String,
        givenName: j['givenName'] as String,
        familyName: j['familyName'] as String,
        nationality: j['nationality'] as String,
        permanentNumber: j['permanentNumber'] as int?,
        image: j['image'] as String?,
      );
}
```

- [ ] **Step 8: Create `lib/api/models/constructor.dart`**

```dart
class Constructor {
  final String id;
  final String name;
  final String nationality;
  final String? image;

  const Constructor({
    required this.id,
    required this.name,
    required this.nationality,
    this.image,
  });

  factory Constructor.fromJson(Map<String, dynamic> j) => Constructor(
        id: j['id'] as String,
        name: j['name'] as String,
        nationality: j['nationality'] as String,
        image: j['image'] as String?,
      );
}
```

- [ ] **Step 9: Create `lib/api/models/standing.dart`**

```dart
class DriverStanding {
  final int position;
  final String driverCode;
  final String driverName;
  final String constructorId;
  final int points;
  final int wins;
  final String? image;

  const DriverStanding({
    required this.position,
    required this.driverCode,
    required this.driverName,
    required this.constructorId,
    required this.points,
    required this.wins,
    this.image,
  });

  factory DriverStanding.fromJson(Map<String, dynamic> j) => DriverStanding(
        position: j['position'] as int,
        driverCode: j['driverCode'] as String,
        driverName: j['driverName'] as String,
        constructorId: j['constructorId'] as String,
        points: j['points'] as int,
        wins: j['wins'] as int,
        image: j['image'] as String?,
      );
}

class ConstructorStanding {
  final int position;
  final String constructorId;
  final String constructorName;
  final int points;
  final int wins;
  final String? image;

  const ConstructorStanding({
    required this.position,
    required this.constructorId,
    required this.constructorName,
    required this.points,
    required this.wins,
    this.image,
  });

  factory ConstructorStanding.fromJson(Map<String, dynamic> j) =>
      ConstructorStanding(
        position: j['position'] as int,
        constructorId: j['constructorId'] as String,
        constructorName: j['constructorName'] as String,
        points: j['points'] as int,
        wins: j['wins'] as int,
        image: j['image'] as String?,
      );
}
```

- [ ] **Step 10: Run tests + analyze**

Run: `flutter analyze && flutter test test/api/models/models_test.dart`
Expected: analyze clean; 7 tests PASS.

- [ ] **Step 11: Commit**

```bash
git add lib/api/models/ test/api/models/
git commit -m "feat(api): typed models with fromJson for all backend entities"
```

---

### Task 5: ApiClient interface + fixtures + MockApiClient

**Files:**
- Create: `lib/api/api_client.dart`
- Create: `lib/api/mock_api_client.dart`
- Create: `lib/mock/fixtures/current_season.json`
- Create: `lib/mock/fixtures/events.json`
- Create: `lib/mock/fixtures/next_session.json`
- Create: `lib/mock/fixtures/session_42_results.json` (Imola race)
- Create: `lib/mock/fixtures/driver_standings.json`
- Create: `lib/mock/fixtures/constructor_standings.json`
- Create: `test/api/mock_api_client_test.dart`

- [ ] **Step 1: Write failing test**

`test/api/mock_api_client_test.dart`:
```dart
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/mock_api_client.dart';
import 'package:predictiongame/api/models/session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final client = MockApiClient(bundle: rootBundle);

  test('currentSeason returns the year', () async {
    final s = await client.currentSeason();
    expect(s.year, greaterThan(2020));
    expect(s.isCurrent, true);
  });

  test('events returns the calendar', () async {
    final events = await client.events();
    expect(events, isNotEmpty);
    expect(events.first.round, 1);
  });

  test('nextSession returns one Session', () async {
    final s = await client.nextSession();
    expect(s.id, isPositive);
  });

  test('sessionResults returns ordered results', () async {
    final r = await client.sessionResults(42);
    expect(r, isNotEmpty);
    expect(r.first.position, 1);
  });

  test('driverStandings returns ordered standings', () async {
    final ds = await client.driverStandings();
    expect(ds, isNotEmpty);
    expect(ds.first.position, 1);
  });

  test('sessionResults throws NotFoundException for unknown session', () async {
    expect(() => client.sessionResults(99999), throwsA(isA<NotFoundException>()));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/api/mock_api_client_test.dart`
Expected: FAIL — files missing.

- [ ] **Step 3: Create `lib/api/api_client.dart`**

```dart
import 'models/constructor.dart';
import 'models/driver.dart';
import 'models/event.dart';
import 'models/season.dart';
import 'models/session.dart';
import 'models/session_result.dart';
import 'models/standing.dart';

abstract class ApiClient {
  Future<Season> currentSeason();
  Future<List<Event>> events();
  Future<Event> event(int round);
  Future<Session> session(int id);
  Future<List<SessionResult>> sessionResults(int id);
  Future<Session> nextSession();
  Future<List<DriverStanding>> driverStandings();
  Future<List<ConstructorStanding>> constructorStandings();
  Future<Driver> driver(String code);
  Future<Constructor> constructor(String id);
}

class NotFoundException implements Exception {
  final String resource;
  const NotFoundException(this.resource);
  @override
  String toString() => 'NotFoundException: $resource';
}

class UpstreamException implements Exception {
  final String message;
  const UpstreamException(this.message);
  @override
  String toString() => 'UpstreamException: $message';
}
```

- [ ] **Step 4: Create fixtures**

`lib/mock/fixtures/current_season.json`:
```json
{ "year": 2026, "isCurrent": true }
```

`lib/mock/fixtures/events.json` — 8 rounds covering past + current + future. Trimmed example (full file has 8 entries; copy the pattern):
```json
[
  {
    "round": 7,
    "name": "Emilia Romagna Grand Prix",
    "country": "Italy",
    "circuitName": "Imola",
    "hasSprint": false,
    "sessions": [
      { "id": 41, "type": "qualifying", "scheduledStart": "2026-05-17T14:00:00Z", "scheduledEnd": "2026-05-17T15:00:00Z", "status": "finished" },
      { "id": 42, "type": "race", "scheduledStart": "2026-05-18T13:00:00Z", "scheduledEnd": "2026-05-18T15:00:00Z", "status": "finished" }
    ]
  },
  {
    "round": 8,
    "name": "Monaco Grand Prix",
    "country": "Monaco",
    "circuitName": "Circuit de Monaco",
    "hasSprint": false,
    "sessions": [
      { "id": 51, "type": "qualifying", "scheduledStart": "2026-05-24T14:00:00Z", "scheduledEnd": "2026-05-24T15:00:00Z", "status": "finished" },
      { "id": 52, "type": "race", "scheduledStart": "2026-05-26T13:00:00Z", "scheduledEnd": "2026-05-26T15:00:00Z", "status": "scheduled" }
    ]
  },
  {
    "round": 9,
    "name": "Canadian Grand Prix",
    "country": "Canada",
    "circuitName": "Circuit Gilles Villeneuve",
    "hasSprint": false,
    "sessions": [
      { "id": 61, "type": "qualifying", "scheduledStart": "2026-06-06T18:00:00Z", "scheduledEnd": "2026-06-06T19:00:00Z", "status": "scheduled" },
      { "id": 62, "type": "race", "scheduledStart": "2026-06-07T18:00:00Z", "scheduledEnd": "2026-06-07T20:00:00Z", "status": "scheduled" }
    ]
  }
]
```

Add 4 more events (rounds 1–6 with status `finished`) following the same shape — keep the file under ~300 lines.

`lib/mock/fixtures/next_session.json` — Monaco race:
```json
{ "id": 52, "type": "race", "scheduledStart": "2026-05-26T13:00:00Z", "scheduledEnd": "2026-05-26T15:00:00Z", "status": "scheduled" }
```

`lib/mock/fixtures/session_42_results.json` — Imola race result, top 8 minimum:
```json
[
  { "position": 1, "driverCode": "NOR", "driverName": "Lando Norris", "constructorId": "mclaren", "constructorName": "McLaren", "raceTime": "1:33:15", "status": "Finished", "points": 25 },
  { "position": 2, "driverCode": "PIA", "driverName": "Oscar Piastri", "constructorId": "mclaren", "constructorName": "McLaren", "raceTime": "+6.221", "status": "Finished", "points": 18 },
  { "position": 3, "driverCode": "LEC", "driverName": "Charles Leclerc", "constructorId": "ferrari", "constructorName": "Ferrari", "raceTime": "+12.804", "status": "Finished", "points": 15 },
  { "position": 4, "driverCode": "TSU", "driverName": "Yuki Tsunoda", "constructorId": "red_bull", "constructorName": "Red Bull", "raceTime": "+18.111", "status": "Finished", "points": 12 },
  { "position": 5, "driverCode": "RUS", "driverName": "George Russell", "constructorId": "mercedes", "constructorName": "Mercedes", "raceTime": "+22.450", "status": "Finished", "points": 10 },
  { "position": 6, "driverCode": "VER", "driverName": "Max Verstappen", "constructorId": "red_bull", "constructorName": "Red Bull", "raceTime": "+28.917", "status": "Finished", "points": 8 },
  { "position": 7, "driverCode": "ALO", "driverName": "Fernando Alonso", "constructorId": "aston_martin", "constructorName": "Aston Martin", "raceTime": "+33.012", "status": "Finished", "points": 6 },
  { "position": 8, "driverCode": "SAI", "driverName": "Carlos Sainz", "constructorId": "ferrari", "constructorName": "Ferrari", "raceTime": "+38.115", "status": "Finished", "points": 4 }
]
```

`lib/mock/fixtures/driver_standings.json`:
```json
[
  { "position": 1, "driverCode": "NOR", "driverName": "Lando Norris", "constructorId": "mclaren", "points": 165, "wins": 4, "image": null },
  { "position": 2, "driverCode": "PIA", "driverName": "Oscar Piastri", "constructorId": "mclaren", "points": 142, "wins": 2, "image": null },
  { "position": 3, "driverCode": "VER", "driverName": "Max Verstappen", "constructorId": "red_bull", "points": 120, "wins": 1, "image": null },
  { "position": 4, "driverCode": "LEC", "driverName": "Charles Leclerc", "constructorId": "ferrari", "points": 110, "wins": 0, "image": null },
  { "position": 5, "driverCode": "RUS", "driverName": "George Russell", "constructorId": "mercedes", "points": 88, "wins": 0, "image": null }
]
```

`lib/mock/fixtures/constructor_standings.json`:
```json
[
  { "position": 1, "constructorId": "mclaren", "constructorName": "McLaren", "points": 307, "wins": 6, "image": null },
  { "position": 2, "constructorId": "red_bull", "constructorName": "Red Bull", "points": 175, "wins": 1, "image": null },
  { "position": 3, "constructorId": "ferrari", "constructorName": "Ferrari", "points": 155, "wins": 0, "image": null },
  { "position": 4, "constructorId": "mercedes", "constructorName": "Mercedes", "points": 110, "wins": 0, "image": null }
]
```

- [ ] **Step 5: Create `lib/api/mock_api_client.dart`**

```dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart' show AssetBundle;
import 'api_client.dart';
import 'models/constructor.dart';
import 'models/driver.dart';
import 'models/event.dart';
import 'models/season.dart';
import 'models/session.dart';
import 'models/session_result.dart';
import 'models/standing.dart';

class MockApiClient implements ApiClient {
  final AssetBundle bundle;
  MockApiClient({required this.bundle});

  Future<dynamic> _read(String name) async {
    final s = await bundle.loadString('lib/mock/fixtures/$name');
    return jsonDecode(s);
  }

  @override
  Future<Season> currentSeason() async =>
      Season.fromJson(await _read('current_season.json') as Map<String, dynamic>);

  @override
  Future<List<Event>> events() async => ((await _read('events.json')) as List)
      .cast<Map<String, dynamic>>()
      .map(Event.fromJson)
      .toList();

  @override
  Future<Event> event(int round) async {
    final all = await events();
    return all.firstWhere(
      (e) => e.round == round,
      orElse: () => throw NotFoundException('event $round'),
    );
  }

  @override
  Future<Session> session(int id) async {
    final all = await events();
    for (final e in all) {
      for (final s in e.sessions) {
        if (s.id == id) return s;
      }
    }
    throw NotFoundException('session $id');
  }

  @override
  Future<List<SessionResult>> sessionResults(int id) async {
    try {
      final raw = await _read('session_${id}_results.json');
      return (raw as List)
          .cast<Map<String, dynamic>>()
          .map(SessionResult.fromJson)
          .toList();
    } catch (_) {
      throw NotFoundException('session $id results');
    }
  }

  @override
  Future<Session> nextSession() async =>
      Session.fromJson(await _read('next_session.json') as Map<String, dynamic>);

  @override
  Future<List<DriverStanding>> driverStandings() async =>
      ((await _read('driver_standings.json')) as List)
          .cast<Map<String, dynamic>>()
          .map(DriverStanding.fromJson)
          .toList();

  @override
  Future<List<ConstructorStanding>> constructorStandings() async =>
      ((await _read('constructor_standings.json')) as List)
          .cast<Map<String, dynamic>>()
          .map(ConstructorStanding.fromJson)
          .toList();

  @override
  Future<Driver> driver(String code) async {
    final results = await sessionResults(42);
    final r = results.firstWhere(
      (r) => r.driverCode == code,
      orElse: () => throw NotFoundException('driver $code'),
    );
    return Driver(
      code: r.driverCode,
      givenName: r.driverName.split(' ').first,
      familyName: r.driverName.split(' ').skip(1).join(' '),
      nationality: 'Unknown',
    );
  }

  @override
  Future<Constructor> constructor(String id) async {
    final standings = await constructorStandings();
    final c = standings.firstWhere(
      (s) => s.constructorId == id,
      orElse: () => throw NotFoundException('constructor $id'),
    );
    return Constructor(id: c.constructorId, name: c.constructorName, nationality: 'Unknown');
  }
}
```

- [ ] **Step 6: Run tests + analyze**

Run: `flutter analyze && flutter test test/api/mock_api_client_test.dart`
Expected: analyze clean; 6 tests PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/api/ lib/mock/ test/api/
git commit -m "feat(api): ApiClient interface + MockApiClient with fixtures"
```

---

### Task 6: HttpApiClient

**Files:**
- Create: `lib/api/http_api_client.dart`
- Create: `test/api/http_api_client_test.dart`

- [ ] **Step 1: Write failing test using mocktail HTTP client**

`test/api/http_api_client_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:predictiongame/api/api_client.dart';
import 'package:predictiongame/api/http_api_client.dart';

class _MockHttp extends Mock implements http.Client {}

void main() {
  late _MockHttp http_;
  late HttpApiClient client;

  setUpAll(() {
    registerFallbackValue(Uri());
  });

  setUp(() {
    http_ = _MockHttp();
    client = HttpApiClient(baseUrl: 'https://api.example.com', client: http_);
  });

  test('currentSeason maps a 200 response', () async {
    when(() => http_.get(any())).thenAnswer(
      (_) async => http.Response('{"year": 2026, "isCurrent": true}', 200),
    );
    final s = await client.currentSeason();
    expect(s.year, 2026);
  });

  test('throws NotFoundException on 404', () async {
    when(() => http_.get(any())).thenAnswer(
      (_) async => http.Response('{"error":{"code":"NOT_FOUND"}}', 404),
    );
    expect(client.session(99), throwsA(isA<NotFoundException>()));
  });

  test('throws UpstreamException on 500', () async {
    when(() => http_.get(any())).thenAnswer(
      (_) async => http.Response('boom', 500),
    );
    expect(client.events(), throwsA(isA<UpstreamException>()));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/api/http_api_client_test.dart`
Expected: FAIL — `HttpApiClient` missing.

- [ ] **Step 3: Create `lib/api/http_api_client.dart`**

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_client.dart';
import 'models/constructor.dart';
import 'models/driver.dart';
import 'models/event.dart';
import 'models/season.dart';
import 'models/session.dart';
import 'models/session_result.dart';
import 'models/standing.dart';

class HttpApiClient implements ApiClient {
  final String baseUrl;
  final http.Client client;
  HttpApiClient({required this.baseUrl, http.Client? client})
      : client = client ?? http.Client();

  Future<dynamic> _get(String path) async {
    final res = await client.get(Uri.parse('$baseUrl$path'));
    if (res.statusCode == 404) throw NotFoundException(path);
    if (res.statusCode >= 500) throw UpstreamException('HTTP ${res.statusCode}');
    if (res.statusCode >= 400) throw UpstreamException('HTTP ${res.statusCode}: ${res.body}');
    return jsonDecode(res.body);
  }

  @override
  Future<Season> currentSeason() async =>
      Season.fromJson(await _get('/api/seasons/current') as Map<String, dynamic>);

  @override
  Future<List<Event>> events() async => ((await _get('/api/events')) as List)
      .cast<Map<String, dynamic>>()
      .map(Event.fromJson)
      .toList();

  @override
  Future<Event> event(int round) async =>
      Event.fromJson(await _get('/api/events/$round') as Map<String, dynamic>);

  @override
  Future<Session> session(int id) async =>
      Session.fromJson(await _get('/api/sessions/$id') as Map<String, dynamic>);

  @override
  Future<List<SessionResult>> sessionResults(int id) async =>
      ((await _get('/api/sessions/$id/results')) as List)
          .cast<Map<String, dynamic>>()
          .map(SessionResult.fromJson)
          .toList();

  @override
  Future<Session> nextSession() async =>
      Session.fromJson(await _get('/api/next-session') as Map<String, dynamic>);

  @override
  Future<List<DriverStanding>> driverStandings() async =>
      ((await _get('/api/standings/drivers')) as List)
          .cast<Map<String, dynamic>>()
          .map(DriverStanding.fromJson)
          .toList();

  @override
  Future<List<ConstructorStanding>> constructorStandings() async =>
      ((await _get('/api/standings/constructors')) as List)
          .cast<Map<String, dynamic>>()
          .map(ConstructorStanding.fromJson)
          .toList();

  @override
  Future<Driver> driver(String code) async =>
      Driver.fromJson(await _get('/api/drivers/$code') as Map<String, dynamic>);

  @override
  Future<Constructor> constructor(String id) async => Constructor.fromJson(
      await _get('/api/constructors/$id') as Map<String, dynamic>);
}
```

- [ ] **Step 4: Run tests + analyze**

Run: `flutter analyze && flutter test test/api/http_api_client_test.dart`
Expected: 3 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/api/http_api_client.dart test/api/http_api_client_test.dart
git commit -m "feat(api): HttpApiClient transport with error mapping"
```

---

### Task 7: Domain types — Prediction & League

**Files:**
- Create: `lib/domain/prediction.dart`
- Create: `lib/domain/league.dart`
- Create: `test/domain/prediction_test.dart`

- [ ] **Step 1: Write failing test**

`test/domain/prediction_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/models/session.dart';
import 'package:predictiongame/domain/prediction.dart';
import 'package:predictiongame/domain/league.dart';

void main() {
  test('PredictionEntry equality by sessionId + userId', () {
    final a = PredictionEntry(
      sessionId: 52,
      userId: 'anton',
      picks: const ['VER', 'LEC'],
      lockedAt: DateTime.utc(2026, 5, 24, 14),
    );
    final b = PredictionEntry(
      sessionId: 52,
      userId: 'anton',
      picks: const ['NOR'],
      lockedAt: null,
    );
    expect(a.key, b.key);
  });

  test('requiredPicks per session type', () {
    expect(requiredPicks(SessionType.qualifying), 2);
    expect(requiredPicks(SessionType.race), 5);
    expect(requiredPicks(SessionType.sprint_quali), 1);
    expect(requiredPicks(SessionType.sprint), 3);
    expect(requiredPicks(SessionType.fp1), 0);
  });

  test('League contains players', () {
    final l = League(
      id: 'the_box',
      name: 'The Box',
      players: const [
        Player(id: 'anton', displayName: 'Anton'),
        Player(id: 'lukas', displayName: 'Lukas'),
      ],
    );
    expect(l.players.length, 2);
    expect(l.players.first.displayName, 'Anton');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/domain/prediction_test.dart`
Expected: FAIL — files missing.

- [ ] **Step 3: Create `lib/domain/league.dart`**

```dart
class Player {
  final String id;
  final String displayName;
  const Player({required this.id, required this.displayName});
  String get initials {
    final parts = displayName.trim().split(' ');
    final letters = parts.map((p) => p.isEmpty ? '' : p[0]).take(2).join();
    return letters.toUpperCase();
  }
}

class League {
  final String id;
  final String name;
  final List<Player> players;
  const League({required this.id, required this.name, required this.players});
}
```

- [ ] **Step 4: Create `lib/domain/prediction.dart`**

```dart
import '../api/models/session.dart';

class PredictionEntry {
  final int sessionId;
  final String userId;
  final List<String> picks;
  final DateTime? lockedAt;

  const PredictionEntry({
    required this.sessionId,
    required this.userId,
    required this.picks,
    this.lockedAt,
  });

  String get key => '$userId:$sessionId';
  bool get isLocked => lockedAt != null;

  PredictionEntry copyWith({List<String>? picks, DateTime? lockedAt}) =>
      PredictionEntry(
        sessionId: sessionId,
        userId: userId,
        picks: picks ?? this.picks,
        lockedAt: lockedAt ?? this.lockedAt,
      );

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'userId': userId,
        'picks': picks,
        'lockedAt': lockedAt?.toIso8601String(),
      };

  factory PredictionEntry.fromJson(Map<String, dynamic> j) => PredictionEntry(
        sessionId: j['sessionId'] as int,
        userId: j['userId'] as String,
        picks: (j['picks'] as List).cast<String>(),
        lockedAt: j['lockedAt'] == null
            ? null
            : DateTime.parse(j['lockedAt'] as String),
      );
}

int requiredPicks(SessionType t) {
  switch (t) {
    case SessionType.qualifying:
      return 2;
    case SessionType.race:
      return 5;
    case SessionType.sprint_quali:
      return 1;
    case SessionType.sprint:
      return 3;
    case SessionType.fp1:
    case SessionType.fp2:
    case SessionType.fp3:
      return 0;
  }
}
```

- [ ] **Step 5: Run tests + analyze**

Run: `flutter analyze && flutter test test/domain/prediction_test.dart`
Expected: 3 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/domain/ test/domain/
git commit -m "feat(domain): Prediction + League types, requiredPicks rule"
```

---

### Task 8: Scoring functions

**Files:**
- Create: `lib/domain/scoring.dart`
- Create: `test/domain/scoring_test.dart`

- [ ] **Step 1: Write failing table-driven tests**

`test/domain/scoring_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/models/session_result.dart';
import 'package:predictiongame/domain/scoring.dart';

SessionResult _row(int pos, String code) => SessionResult(
      position: pos,
      driverCode: code,
      driverName: code,
      constructorId: 'x',
      constructorName: 'X',
    );

void main() {
  final result = [
    _row(1, 'NOR'),
    _row(2, 'PIA'),
    _row(3, 'LEC'),
    _row(4, 'TSU'),
    _row(5, 'RUS'),
    _row(6, 'VER'),
  ];

  group('scoreRace (Top-5, ordered)', () {
    test('all five exact = 40 points', () {
      expect(scoreRace(['NOR', 'PIA', 'LEC', 'TSU', 'RUS'], result), 40);
    });

    test('right drivers wrong slots = 5 × NEAR = 20', () {
      expect(scoreRace(['RUS', 'TSU', 'LEC', 'PIA', 'NOR'], result), 20);
    });

    test('mixed: 2 exact + 1 near + 2 miss = 8+8+4+0+0 = 20', () {
      expect(scoreRace(['NOR', 'LEC', 'PIA', 'XXX', 'YYY'], result), 20);
    });

    test('all miss = 0', () {
      expect(scoreRace(['AAA', 'BBB', 'CCC', 'DDD', 'EEE'], result), 0);
    });
  });

  group('scoreQualifying (Top-2)', () {
    test('both exact = 16', () {
      expect(scoreQualifying(['NOR', 'PIA'], result), 16);
    });
    test('swap = 8', () {
      expect(scoreQualifying(['PIA', 'NOR'], result), 8);
    });
  });

  group('scoreSprintQualifying (Top-1)', () {
    test('pole exact = 8', () {
      expect(scoreSprintQualifying(['NOR'], result), 8);
    });
    test('miss = 0', () {
      expect(scoreSprintQualifying(['VER'], result), 0);
    });
  });

  group('scoreSprint (Top-3)', () {
    test('all exact = 24', () {
      expect(scoreSprint(['NOR', 'PIA', 'LEC'], result), 24);
    });
    test('one near = 12 (1 exact + 1 near + 1 miss)', () {
      expect(scoreSprint(['NOR', 'LEC', 'TSU'], result), 12);
    });
  });

  group('outcomeFor', () {
    test('exact slot match', () {
      expect(outcomeFor('NOR', 1, result, 5), PickOutcome.exact);
    });
    test('in top-N but wrong slot', () {
      expect(outcomeFor('NOR', 3, result, 5), PickOutcome.inTopN);
    });
    test('not in top-N', () {
      expect(outcomeFor('VER', 1, result, 5), PickOutcome.miss);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/domain/scoring_test.dart`
Expected: FAIL — `scoring.dart` missing.

- [ ] **Step 3: Create `lib/domain/scoring.dart`**

```dart
import '../api/models/session_result.dart';

class ScoringRules {
  static const int exact = 8;
  static const int inTopN = 4;
  static const int miss = 0;
}

enum PickOutcome { exact, inTopN, miss }

PickOutcome outcomeFor(
  String pick,
  int slot,
  List<SessionResult> result,
  int topN,
) {
  final top = result.where((r) => r.position <= topN).toList();
  for (final r in top) {
    if (r.driverCode == pick) {
      return r.position == slot ? PickOutcome.exact : PickOutcome.inTopN;
    }
  }
  return PickOutcome.miss;
}

int _scoreOrdered(List<String> picks, List<SessionResult> result, int topN) {
  var total = 0;
  for (var i = 0; i < picks.length; i++) {
    final slot = i + 1;
    switch (outcomeFor(picks[i], slot, result, topN)) {
      case PickOutcome.exact:
        total += ScoringRules.exact;
      case PickOutcome.inTopN:
        total += ScoringRules.inTopN;
      case PickOutcome.miss:
        total += ScoringRules.miss;
    }
  }
  return total;
}

int scoreQualifying(List<String> picks, List<SessionResult> result) =>
    _scoreOrdered(picks, result, 2);

int scoreRace(List<String> picks, List<SessionResult> result) =>
    _scoreOrdered(picks, result, 5);

int scoreSprintQualifying(List<String> picks, List<SessionResult> result) =>
    _scoreOrdered(picks, result, 1);

int scoreSprint(List<String> picks, List<SessionResult> result) =>
    _scoreOrdered(picks, result, 3);
```

- [ ] **Step 4: Run tests + analyze**

Run: `flutter analyze && flutter test test/domain/scoring_test.dart`
Expected: 11 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/domain/scoring.dart test/domain/scoring_test.dart
git commit -m "feat(domain): scoring functions for all session types"
```

---

### Task 9: ThemeController + AuthController + LeagueController

**Files:**
- Create: `lib/state/theme_controller.dart`
- Create: `lib/state/auth_controller.dart`
- Create: `lib/state/league_controller.dart`
- Create: `test/state/controllers_test.dart`

- [ ] **Step 1: Write failing test**

`test/state/controllers_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/domain/league.dart';
import 'package:predictiongame/state/auth_controller.dart';
import 'package:predictiongame/state/league_controller.dart';
import 'package:predictiongame/state/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('ThemeController defaults to system and persists changes', () async {
    final c = await ThemeController.load();
    expect(c.mode, ThemeMode.system);
    var notified = 0;
    c.addListener(() => notified++);
    await c.setMode(ThemeMode.dark);
    expect(c.mode, ThemeMode.dark);
    expect(notified, 1);

    final c2 = await ThemeController.load();
    expect(c2.mode, ThemeMode.dark);
  });

  test('AuthController login persists and notifies', () async {
    final c = await AuthController.load();
    expect(c.currentUserId, isNull);
    var notified = 0;
    c.addListener(() => notified++);
    await c.login('anton');
    expect(c.currentUserId, 'anton');
    expect(notified, 1);
    final c2 = await AuthController.load();
    expect(c2.currentUserId, 'anton');
  });

  test('LeagueController holds the box', () {
    final c = LeagueController(league: theBoxLeague);
    expect(c.league.name, 'The Box');
    expect(c.league.players.length, 5);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/state/controllers_test.dart`
Expected: FAIL — controllers missing.

- [ ] **Step 3: Create `lib/state/theme_controller.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeController extends ChangeNotifier {
  static const _key = 'theme_mode';
  ThemeMode _mode;
  ThemeController(this._mode);

  ThemeMode get mode => _mode;

  static Future<ThemeController> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    final m = ThemeMode.values
        .firstWhere((v) => v.name == raw, orElse: () => ThemeMode.system);
    return ThemeController(m);
  }

  Future<void> setMode(ThemeMode m) async {
    if (m == _mode) return;
    _mode = m;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, m.name);
    notifyListeners();
  }
}
```

- [ ] **Step 4: Create `lib/state/auth_controller.dart`**

```dart
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthController extends ChangeNotifier {
  static const _key = 'current_user_id';
  String? _currentUserId;
  AuthController(this._currentUserId);

  String? get currentUserId => _currentUserId;
  bool get isLoggedIn => _currentUserId != null;

  static Future<AuthController> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AuthController(prefs.getString(_key));
  }

  Future<void> login(String userId) async {
    _currentUserId = userId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, userId);
    notifyListeners();
  }

  Future<void> logout() async {
    _currentUserId = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    notifyListeners();
  }
}
```

- [ ] **Step 5: Create `lib/state/league_controller.dart`**

```dart
import 'package:flutter/foundation.dart';
import '../domain/league.dart';

const League theBoxLeague = League(
  id: 'the_box',
  name: 'The Box',
  players: [
    Player(id: 'anton', displayName: 'Anton'),
    Player(id: 'lukas', displayName: 'Lukas'),
    Player(id: 'simon', displayName: 'Simon'),
    Player(id: 'paul', displayName: 'Paul'),
    Player(id: 'peter', displayName: 'Peter'),
  ],
);

class LeagueController extends ChangeNotifier {
  League _league;
  LeagueController({required League league}) : _league = league;
  League get league => _league;
}
```

- [ ] **Step 6: Run tests + analyze**

Run: `flutter analyze && flutter test test/state/controllers_test.dart`
Expected: 3 tests PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/state/ test/state/
git commit -m "feat(state): Theme + Auth + League controllers (persisted)"
```

---

### Task 10: PredictionsStore

**Files:**
- Create: `lib/state/predictions_store.dart`
- Create: `test/state/predictions_store_test.dart`

- [ ] **Step 1: Write failing test**

`test/state/predictions_store_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/state/predictions_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('save then read roundtrip', () async {
    final s = await PredictionsStore.load();
    await s.save(
      userId: 'anton',
      sessionId: 52,
      picks: const ['VER', 'LEC', 'NOR', 'PIA', 'SAI'],
    );
    final picks = s.picksFor(userId: 'anton', sessionId: 52);
    expect(picks, ['VER', 'LEC', 'NOR', 'PIA', 'SAI']);
  });

  test('lock sets lockedAt and prevents save', () async {
    final s = await PredictionsStore.load();
    await s.save(userId: 'anton', sessionId: 52, picks: const ['VER']);
    await s.lock(userId: 'anton', sessionId: 52);
    expect(s.isLocked(userId: 'anton', sessionId: 52), true);
    expect(
      () => s.save(userId: 'anton', sessionId: 52, picks: const ['LEC']),
      throwsStateError,
    );
  });

  test('persistence across reload', () async {
    final s = await PredictionsStore.load();
    await s.save(userId: 'anton', sessionId: 52, picks: const ['VER', 'LEC']);
    final s2 = await PredictionsStore.load();
    expect(s2.picksFor(userId: 'anton', sessionId: 52), ['VER', 'LEC']);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/state/predictions_store_test.dart`
Expected: FAIL.

- [ ] **Step 3: Create `lib/state/predictions_store.dart`**

```dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/prediction.dart';

class PredictionsStore extends ChangeNotifier {
  static const _key = 'predictions_v1';
  final Map<String, PredictionEntry> _entries;

  PredictionsStore(this._entries);

  static Future<PredictionsStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    final map = <String, PredictionEntry>{};
    if (raw != null) {
      final decoded = (jsonDecode(raw) as Map).cast<String, dynamic>();
      decoded.forEach((k, v) {
        map[k] = PredictionEntry.fromJson((v as Map).cast<String, dynamic>());
      });
    }
    return PredictionsStore(map);
  }

  String _k(String userId, int sessionId) => '$userId:$sessionId';

  List<String> picksFor({required String userId, required int sessionId}) =>
      _entries[_k(userId, sessionId)]?.picks ?? const [];

  bool isLocked({required String userId, required int sessionId}) =>
      _entries[_k(userId, sessionId)]?.isLocked ?? false;

  PredictionEntry? entryFor({required String userId, required int sessionId}) =>
      _entries[_k(userId, sessionId)];

  Future<void> save({
    required String userId,
    required int sessionId,
    required List<String> picks,
  }) async {
    final existing = _entries[_k(userId, sessionId)];
    if (existing?.isLocked == true) {
      throw StateError('Prediction is locked');
    }
    _entries[_k(userId, sessionId)] = PredictionEntry(
      sessionId: sessionId,
      userId: userId,
      picks: List.unmodifiable(picks),
    );
    await _persist();
    notifyListeners();
  }

  Future<void> lock({required String userId, required int sessionId}) async {
    final existing = _entries[_k(userId, sessionId)];
    if (existing == null) return;
    _entries[_k(userId, sessionId)] =
        existing.copyWith(lockedAt: DateTime.now().toUtc());
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(
      _entries.map((k, v) => MapEntry(k, v.toJson())),
    );
    await prefs.setString(_key, encoded);
  }
}
```

- [ ] **Step 4: Run tests + analyze**

Run: `flutter analyze && flutter test test/state/predictions_store_test.dart`
Expected: 3 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/state/predictions_store.dart test/state/predictions_store_test.dart
git commit -m "feat(state): PredictionsStore with shared_preferences persistence"
```

---

### Task 11: AppState `InheritedNotifier` + wire to main

**Files:**
- Create: `lib/state/app_state.dart`
- Modify: `lib/main.dart`
- Create: `lib/app.dart`
- Modify: `test/widget_test.dart`

- [ ] **Step 1: Write failing test**

Replace `test/widget_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/mock_api_client.dart';
import 'package:predictiongame/app.dart';
import 'package:predictiongame/state/app_state.dart';
import 'package:predictiongame/state/auth_controller.dart';
import 'package:predictiongame/state/league_controller.dart';
import 'package:predictiongame/state/predictions_store.dart';
import 'package:predictiongame/state/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('App boots with all controllers in scope', (tester) async {
    final api = MockApiClient(bundle: rootBundle);
    final auth = await AuthController.load();
    final league = LeagueController(league: theBoxLeague);
    final theme = await ThemeController.load();
    final preds = await PredictionsStore.load();
    await tester.pumpWidget(F1PgApp(
      api: api,
      auth: auth,
      league: league,
      theme: theme,
      predictions: preds,
    ));
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget_test.dart`
Expected: FAIL — `app.dart`, `app_state.dart` missing.

- [ ] **Step 3: Create `lib/state/app_state.dart`**

```dart
import 'package:flutter/widgets.dart';
import '../api/api_client.dart';
import 'auth_controller.dart';
import 'league_controller.dart';
import 'predictions_store.dart';
import 'theme_controller.dart';

class AppState extends StatefulWidget {
  final ApiClient api;
  final AuthController auth;
  final LeagueController league;
  final ThemeController theme;
  final PredictionsStore predictions;
  final Widget child;

  const AppState({
    super.key,
    required this.api,
    required this.auth,
    required this.league,
    required this.theme,
    required this.predictions,
    required this.child,
  });

  @override
  State<AppState> createState() => _AppStateState();

  static _AppStateScope of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<_AppStateScope>();
    assert(scope != null, 'AppState not found in widget tree');
    return scope!;
  }
}

class _AppStateState extends State<AppState> {
  @override
  Widget build(BuildContext context) => _AppStateScope(
        api: widget.api,
        auth: widget.auth,
        league: widget.league,
        theme: widget.theme,
        predictions: widget.predictions,
        child: widget.child,
      );
}

class _AppStateScope extends InheritedWidget {
  final ApiClient api;
  final AuthController auth;
  final LeagueController league;
  final ThemeController theme;
  final PredictionsStore predictions;

  const _AppStateScope({
    required this.api,
    required this.auth,
    required this.league,
    required this.theme,
    required this.predictions,
    required super.child,
  });

  @override
  bool updateShouldNotify(_AppStateScope oldWidget) => false;
}
```

- [ ] **Step 4: Create `lib/app.dart`**

```dart
import 'package:flutter/material.dart';
import 'api/api_client.dart';
import 'state/app_state.dart';
import 'state/auth_controller.dart';
import 'state/league_controller.dart';
import 'state/predictions_store.dart';
import 'state/theme_controller.dart';
import 'theme/app_theme.dart';

class F1PgApp extends StatelessWidget {
  final ApiClient api;
  final AuthController auth;
  final LeagueController league;
  final ThemeController theme;
  final PredictionsStore predictions;

  const F1PgApp({
    super.key,
    required this.api,
    required this.auth,
    required this.league,
    required this.theme,
    required this.predictions,
  });

  @override
  Widget build(BuildContext context) {
    return AppState(
      api: api,
      auth: auth,
      league: league,
      theme: theme,
      predictions: predictions,
      child: ListenableBuilder(
        listenable: theme,
        builder: (_, __) => MaterialApp(
          title: 'F1PG',
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: theme.mode,
          home: const Scaffold(body: Center(child: Text('F1PG'))),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Update `lib/main.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'api/api_client.dart';
import 'api/http_api_client.dart';
import 'api/mock_api_client.dart';
import 'app.dart';
import 'state/auth_controller.dart';
import 'state/league_controller.dart';
import 'state/predictions_store.dart';
import 'state/theme_controller.dart';

const _useMock = bool.fromEnvironment('USE_MOCK', defaultValue: true);
const _apiUrl = String.fromEnvironment('API_URL', defaultValue: '');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final ApiClient api = _useMock
      ? MockApiClient(bundle: rootBundle)
      : HttpApiClient(baseUrl: _apiUrl, client: http.Client());
  final auth = await AuthController.load();
  final theme = await ThemeController.load();
  final preds = await PredictionsStore.load();
  runApp(F1PgApp(
    api: api,
    auth: auth,
    league: LeagueController(league: theBoxLeague),
    theme: theme,
    predictions: preds,
  ));
}
```

- [ ] **Step 6: Run tests + analyze**

Run: `flutter analyze && flutter test`
Expected: analyze clean; all tests PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/state/app_state.dart lib/app.dart lib/main.dart test/widget_test.dart
git commit -m "feat(state): AppState scope + ApiClient factory wired to runApp"
```

---

### Task 12: Foundation components — AppCard, TrendBadge, SessionChip, Countdown

**Files:**
- Create: `lib/components/app_card.dart`
- Create: `lib/components/trend_badge.dart`
- Create: `lib/components/session_chip.dart`
- Create: `lib/components/countdown.dart`
- Create: `test/components/foundation_test.dart`

- [ ] **Step 1: Write failing widget tests**

`test/components/foundation_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/components/app_card.dart';
import 'package:predictiongame/components/countdown.dart';
import 'package:predictiongame/components/session_chip.dart';
import 'package:predictiongame/components/trend_badge.dart';
import 'package:predictiongame/theme/app_theme.dart';

Widget _frame(Widget child, {Brightness b = Brightness.light}) => MaterialApp(
      theme: b == Brightness.light ? AppTheme.light() : AppTheme.dark(),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  testWidgets('AppCard renders its child', (tester) async {
    await tester.pumpWidget(_frame(const AppCard(child: Text('hi'))));
    expect(find.text('hi'), findsOneWidget);
  });

  testWidgets('TrendBadge shows direction', (tester) async {
    await tester.pumpWidget(_frame(const TrendBadge(direction: TrendDirection.up, label: '1')));
    expect(find.text('▲ 1'), findsOneWidget);
  });

  testWidgets('SessionChip shows label and state', (tester) async {
    await tester.pumpWidget(_frame(const SessionChip(label: 'RACE', state: ChipState.next)));
    expect(find.text('RACE'), findsOneWidget);
  });

  testWidgets('Countdown renders D/H/M from a future date', (tester) async {
    final target = DateTime.now().add(const Duration(days: 2, hours: 14, minutes: 32));
    await tester.pumpWidget(_frame(Countdown(target: target)));
    expect(find.text('02'), findsOneWidget);
    expect(find.text('14'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/components/foundation_test.dart`
Expected: FAIL — files missing.

- [ ] **Step 3: Create `lib/components/app_card.dart`**

```dart
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? background;
  final bool elevated;
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Spacing.lg),
    this.background,
    this.elevated = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: background ?? t.colorScheme.surface,
        borderRadius: Radii.rLg,
        border: Border.all(color: t.strokeColor, width: Strokes.card),
        boxShadow: elevated
            ? const [
                BoxShadow(
                  color: Colors.black,
                  offset: Offset(0, 6),
                  blurRadius: 0,
                )
              ]
            : null,
      ),
      child: child,
    );
  }
}
```

- [ ] **Step 4: Create `lib/components/trend_badge.dart`**

```dart
import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

enum TrendDirection { up, down, equal }

class TrendBadge extends StatelessWidget {
  final TrendDirection direction;
  final String label;
  const TrendBadge({super.key, required this.direction, required this.label});

  @override
  Widget build(BuildContext context) {
    final (glyph, bg, fg) = switch (direction) {
      TrendDirection.up => ('▲', BrandColors.ok, Colors.black),
      TrendDirection.down => ('▼', Colors.black, Colors.white),
      TrendDirection.equal => ('━', Colors.transparent, Theme.of(context).colorScheme.onSurface.withOpacity(0.4)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: const BorderRadius.all(Radius.circular(4))),
      child: Text('$glyph $label', style: AppText.label(10, color: fg)),
    );
  }
}
```

- [ ] **Step 5: Create `lib/components/session_chip.dart`**

```dart
import 'package:flutter/material.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

enum ChipState { idle, done, next, live }

class SessionChip extends StatelessWidget {
  final String label;
  final ChipState state;
  const SessionChip({super.key, required this.label, this.state = ChipState.idle});

  @override
  Widget build(BuildContext context) {
    final (bg, fg, deco) = switch (state) {
      ChipState.idle => (Colors.black.withOpacity(0.25), Colors.white, TextDecoration.none),
      ChipState.done => (Colors.white.withOpacity(0.18), Colors.white.withOpacity(0.6), TextDecoration.lineThrough),
      ChipState.next => (Colors.black, Colors.white, TextDecoration.none),
      ChipState.live => (const Color(0xFFE10600), Colors.white, TextDecoration.none),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: Spacing.xxs),
      decoration: BoxDecoration(color: bg, borderRadius: const BorderRadius.all(Radius.circular(6))),
      child: Text(label, style: AppText.label(9, color: fg).copyWith(decoration: deco)),
    );
  }
}
```

- [ ] **Step 6: Create `lib/components/countdown.dart`**

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

class Countdown extends StatefulWidget {
  final DateTime target;
  final double size;
  const Countdown({super.key, required this.target, this.size = 30});

  @override
  State<Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<Countdown> {
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(Durations.tick, (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final diff = widget.target.difference(DateTime.now());
    final d = diff.isNegative ? 0 : diff.inDays;
    final h = diff.isNegative ? 0 : diff.inHours.remainder(24);
    final m = diff.isNegative ? 0 : diff.inMinutes.remainder(60);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _unit(d, 'd'),
        const SizedBox(width: Spacing.lg),
        _unit(h, 'h'),
        const SizedBox(width: Spacing.lg),
        _unit(m, 'm'),
      ],
    );
  }

  Widget _unit(int v, String u) => Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(v.toString().padLeft(2, '0'), style: AppText.display(widget.size)),
          const SizedBox(width: 2),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(u, style: AppText.label(9)),
          ),
        ],
      );
}
```

- [ ] **Step 7: Run tests + analyze**

Run: `flutter analyze && flutter test test/components/foundation_test.dart`
Expected: 4 tests PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/components/ test/components/
git commit -m "feat(components): AppCard, TrendBadge, SessionChip, Countdown"
```

---

### Task 13: Tile family — RaceTile, PodTile, DriverTile, Slot

**Files:**
- Create: `lib/components/race_tile.dart`
- Create: `lib/components/pod_tile.dart`
- Create: `lib/components/driver_tile.dart`
- Create: `lib/components/slot.dart`
- Create: `test/components/tiles_test.dart`

- [ ] **Step 1: Write failing widget tests**

`test/components/tiles_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/components/driver_tile.dart';
import 'package:predictiongame/components/pod_tile.dart';
import 'package:predictiongame/components/race_tile.dart';
import 'package:predictiongame/components/slot.dart';
import 'package:predictiongame/theme/app_theme.dart';

Widget _frame(Widget child) => MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: Center(child: SizedBox(width: 360, child: child))),
    );

void main() {
  testWidgets('RaceTile shows round, name, when', (tester) async {
    await tester.pumpWidget(_frame(RaceTile(
      round: 8,
      country: 'Monaco',
      name: 'Monaco GP',
      when: '24 – 26 May',
      state: RaceState.next,
    )));
    expect(find.text('08'), findsOneWidget);
    expect(find.text('Monaco GP'), findsOneWidget);
    expect(find.text('NEXT'), findsOneWidget);
  });

  testWidgets('PodTile shows position + code + team-coloured background',
      (tester) async {
    await tester.pumpWidget(_frame(const PodTile(
      position: 1,
      driverCode: 'NOR',
      constructorId: 'mclaren',
      mark: PodMark.exact,
    )));
    expect(find.text('NOR'), findsOneWidget);
    expect(find.text('P1'), findsOneWidget);
  });

  testWidgets('DriverTile shows code and number; picked badge if assigned',
      (tester) async {
    await tester.pumpWidget(_frame(const DriverTile(
      code: 'VER',
      number: 1,
      constructorId: 'red_bull',
      pickedSlot: 1,
    )));
    expect(find.text('VER'), findsOneWidget);
    expect(find.text('#1'), findsOneWidget);
    expect(find.text('P1'), findsOneWidget);
  });

  testWidgets('Slot empty vs filled', (tester) async {
    await tester.pumpWidget(_frame(const Slot(position: 4)));
    expect(find.text('P4'), findsOneWidget);
    expect(find.text('Tap a driver below'), findsOneWidget);

    await tester.pumpWidget(_frame(const Slot(
      position: 1,
      driverCode: 'VER',
      driverName: 'Verstappen',
      number: 1,
      constructorId: 'red_bull',
    )));
    expect(find.text('Verstappen'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/components/tiles_test.dart`
Expected: FAIL.

- [ ] **Step 3: Create `lib/components/race_tile.dart`**

```dart
import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'app_card.dart';

enum RaceState { past, next, live, future }

class RaceTile extends StatelessWidget {
  final int round;
  final String country;
  final String name;
  final String when;
  final RaceState state;
  final int? pointsScored;
  final List<bool>? pickHits;
  final bool sprint;
  final String? distanceFromNow;
  final VoidCallback? onTap;

  const RaceTile({
    super.key,
    required this.round,
    required this.country,
    required this.name,
    required this.when,
    required this.state,
    this.pointsScored,
    this.pickHits,
    this.sprint = false,
    this.distanceFromNow,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final stripeColor = state == RaceState.live ? BrandColors.live : null;
    return InkWell(
      onTap: onTap,
      borderRadius: Radii.rLg,
      child: AppCard(
        padding: EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: Radii.rLg,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (stripeColor != null)
                Container(width: 5, color: stripeColor),
              Padding(
                padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.md, Spacing.lg, Spacing.md),
                child: Text(
                  round.toString().padLeft(2, '0'),
                  style: AppText.display(28),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Spacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(country.toUpperCase(),
                          style: AppText.label(10, color: t.colorScheme.onSurface.withOpacity(0.55))),
                      const SizedBox(height: Spacing.xxs),
                      Text(
                        name.toUpperCase(),
                        style: AppText.display(16).copyWith(
                          decoration: state == RaceState.past ? TextDecoration.lineThrough : null,
                          decorationColor: Colors.black26,
                        ),
                      ),
                      const SizedBox(height: Spacing.xxs),
                      Text(when, style: AppText.body(11, color: t.colorScheme.onSurface.withOpacity(0.7))),
                      if (pickHits != null) ...[
                        const SizedBox(height: 5),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: pickHits!
                              .map((hit) => Container(
                                    margin: const EdgeInsets.only(right: 3),
                                    width: 7,
                                    height: 7,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: hit ? BrandColors.ok : BrandColors.accent,
                                    ),
                                  ))
                              .toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(0, Spacing.md, Spacing.lg, Spacing.md),
                child: _rightSide(t),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rightSide(ThemeData t) {
    if (state == RaceState.next) {
      return _badge('NEXT', Colors.black, Colors.white);
    }
    if (state == RaceState.live) {
      return _badge('LIVE', BrandColors.live, Colors.white);
    }
    if (pointsScored != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('+$pointsScored', style: AppText.display(18)),
          Text('pts', style: AppText.label(9, color: t.colorScheme.onSurface.withOpacity(0.6))),
        ],
      );
    }
    if (distanceFromNow != null) {
      return Text(distanceFromNow!, style: AppText.body(11, color: t.colorScheme.onSurface.withOpacity(0.5)));
    }
    return const SizedBox.shrink();
  }

  Widget _badge(String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: Spacing.xxs),
        decoration: BoxDecoration(color: bg, borderRadius: const BorderRadius.all(Radius.circular(6))),
        child: Text(text, style: AppText.label(10, color: fg)),
      );
}
```

- [ ] **Step 4: Create `lib/components/pod_tile.dart`**

```dart
import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../theme/team_colors.dart';
import '../theme/typography.dart';

enum PodMark { none, exact, miss }

class PodTile extends StatelessWidget {
  final int position;
  final String driverCode;
  final String constructorId;
  final PodMark mark;
  const PodTile({
    super.key,
    required this.position,
    required this.driverCode,
    required this.constructorId,
    this.mark = PodMark.none,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 10, 6, 8),
      decoration: BoxDecoration(
        color: teamColor(constructorId),
        borderRadius: const BorderRadius.all(Radius.circular(10)),
      ),
      child: Stack(
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('P$position', style: AppText.label(9, color: Colors.white)),
                const SizedBox(height: 2),
                Text(driverCode, style: AppText.display(13, color: Colors.white)),
              ],
            ),
          ),
          if (mark != PodMark.none)
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: mark == PodMark.exact ? BrandColors.ok : Colors.black,
                ),
                child: Center(
                  child: Text(
                    mark == PodMark.exact ? '✓' : '✗',
                    style: TextStyle(
                      color: mark == PodMark.exact ? Colors.black : Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: Create `lib/components/driver_tile.dart`**

```dart
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/team_colors.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

class DriverTile extends StatelessWidget {
  final String code;
  final int? number;
  final String constructorId;
  final int? pickedSlot;
  final VoidCallback? onTap;
  const DriverTile({
    super.key,
    required this.code,
    required this.constructorId,
    this.number,
    this.pickedSlot,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final picked = pickedSlot != null;
    final t = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: const BorderRadius.all(Radius.circular(8)),
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 5),
        decoration: BoxDecoration(
          color: picked ? Colors.black : t.colorScheme.surface,
          border: Border.all(color: t.strokeColor, width: Strokes.subtle),
          borderRadius: const BorderRadius.all(Radius.circular(8)),
        ),
        child: Stack(
          children: [
            Positioned(left: 0, top: 0, bottom: 0,
              child: Container(width: 4, color: teamColor(constructorId)),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(code,
                      style: AppText.display(13, color: picked ? Colors.white : t.colorScheme.onSurface)),
                  if (number != null)
                    Text('#$number',
                        style: AppText.label(8, color: (picked ? Colors.white : t.colorScheme.onSurface).withOpacity(0.55))),
                ],
              ),
            ),
            if (picked)
              Positioned(
                top: 2,
                right: 3,
                child: Text('P$pickedSlot',
                    style: AppText.display(10, color: Colors.white)),
              ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: Create `lib/components/slot.dart`**

```dart
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/team_colors.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

class Slot extends StatelessWidget {
  final int position;
  final String? driverCode;
  final String? driverName;
  final int? number;
  final String? constructorId;
  final VoidCallback? onClear;
  const Slot({
    super.key,
    required this.position,
    this.driverCode,
    this.driverName,
    this.number,
    this.constructorId,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final filled = driverCode != null;
    final t = Theme.of(context);
    return Container(
      padding: EdgeInsets.fromLTRB(filled ? 0 : 10, Spacing.sm, 10, Spacing.sm),
      decoration: BoxDecoration(
        border: Border.all(
          color: t.strokeColor,
          width: Strokes.subtle,
          style: filled ? BorderStyle.solid : BorderStyle.solid,
        ),
        borderRadius: const BorderRadius.all(Radius.circular(10)),
      ),
      child: Row(
        children: [
          if (filled && constructorId != null)
            Container(width: 5, height: 32, color: teamColor(constructorId!)),
          if (filled) const SizedBox(width: Spacing.sm),
          Container(
            width: 32,
            padding: const EdgeInsets.only(left: filled ? 0 : 0),
            child: Text('P$position', style: AppText.display(18)),
          ),
          Expanded(
            child: filled
                ? Text(driverName ?? '', style: AppText.body(14, weight: FontWeight.w700))
                : Text('Tap a driver below',
                    style: AppText.body(12, color: t.colorScheme.onSurface.withOpacity(0.35))
                        .copyWith(fontStyle: FontStyle.italic)),
          ),
          if (filled && number != null)
            Text('#$number', style: AppText.label(11, color: t.colorScheme.onSurface.withOpacity(0.5))),
          if (filled && onClear != null)
            IconButton(icon: const Icon(Icons.close, size: 16), onPressed: onClear),
        ],
      ),
    );
  }
}
```

- [ ] **Step 7: Run tests + analyze**

Run: `flutter analyze && flutter test test/components/tiles_test.dart`
Expected: 4 tests PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/components/race_tile.dart lib/components/pod_tile.dart lib/components/driver_tile.dart lib/components/slot.dart test/components/tiles_test.dart
git commit -m "feat(components): RaceTile, PodTile, DriverTile, Slot"
```

---

### Task 14: Standings + Insights primitives — LeagueRow, ScoreBanner, FactCard, TrajectoryChart

**Files:**
- Create: `lib/components/league_row.dart`
- Create: `lib/components/score_banner.dart`
- Create: `lib/components/fact_card.dart`
- Create: `lib/components/trajectory_chart.dart`
- Create: `test/components/standings_insights_test.dart`

- [ ] **Step 1: Write failing widget tests**

`test/components/standings_insights_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/components/fact_card.dart';
import 'package:predictiongame/components/league_row.dart';
import 'package:predictiongame/components/score_banner.dart';
import 'package:predictiongame/components/trajectory_chart.dart';
import 'package:predictiongame/components/trend_badge.dart';
import 'package:predictiongame/theme/app_theme.dart';

Widget _frame(Widget c) => MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: SizedBox(width: 360, child: c)),
    );

void main() {
  testWidgets('LeagueRow shows rank, name, points', (tester) async {
    await tester.pumpWidget(_frame(const LeagueRow(
      rank: 3, initials: 'AN', name: 'Anton', subtitle: '+24 last race',
      points: 148, trend: TrendDirection.equal, isMe: true,
    )));
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Anton'), findsOneWidget);
    expect(find.text('148'), findsOneWidget);
  });

  testWidgets('ScoreBanner shows label + big number', (tester) async {
    await tester.pumpWidget(_frame(const ScoreBanner(
      label: 'Your score', value: '+24', subtitle: '3 exact', trailing: '2nd in The Box',
    )));
    expect(find.text('+24'), findsOneWidget);
    expect(find.text('Your score'), findsOneWidget);
  });

  testWidgets('FactCard shows emblem + text', (tester) async {
    await tester.pumpWidget(_frame(const FactCard(emblem: '★', text: 'Lukas won 4')));
    expect(find.text('★'), findsOneWidget);
    expect(find.text('Lukas won 4'), findsOneWidget);
  });

  testWidgets('TrajectoryChart paints without throwing', (tester) async {
    await tester.pumpWidget(_frame(const TrajectoryChart(
      series: [
        ChartSeries(label: 'You', color: Colors.red, points: [0, 18, 40, 56, 72, 90, 114, 148]),
        ChartSeries(label: 'Leader', color: Colors.black, points: [0, 25, 50, 75, 100, 125, 150, 167]),
      ],
      xLabels: ['R1','R2','R3','R4','R5','R6','R7','R8'],
    )));
    expect(find.byType(CustomPaint), findsWidgets);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/components/standings_insights_test.dart`
Expected: FAIL.

- [ ] **Step 3: Create `lib/components/league_row.dart`**

```dart
import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'trend_badge.dart';

class LeagueRow extends StatelessWidget {
  final int rank;
  final String initials;
  final String name;
  final String? subtitle;
  final int points;
  final TrendDirection trend;
  final bool isMe;
  const LeagueRow({
    super.key,
    required this.rank,
    required this.initials,
    required this.name,
    this.subtitle,
    required this.points,
    required this.trend,
    this.isMe = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: Spacing.md),
      color: isMe ? const Color(0xFFFFF7D1) : null,
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text('$rank',
                style: AppText.display(18, color: isMe ? BrandColors.accent : t.colorScheme.onSurface)),
          ),
          const SizedBox(width: 10),
          Container(
            width: 32, height: 32,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFEEEEEE)),
            alignment: Alignment.center,
            child: Text(initials, style: AppText.display(12)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name, style: AppText.body(13, weight: isMe ? FontWeight.w800 : FontWeight.w700)),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!, style: AppText.body(10, color: t.colorScheme.onSurface.withOpacity(0.5))),
                  ),
              ],
            ),
          ),
          TrendBadge(direction: trend, label: trend == TrendDirection.equal ? '' : '1'),
          const SizedBox(width: Spacing.sm),
          SizedBox(
            width: 42,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('$points', style: AppText.display(18)),
                Text('pts', style: AppText.label(8, color: t.colorScheme.onSurface.withOpacity(0.6))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Create `lib/components/score_banner.dart`**

```dart
import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'app_card.dart';

class ScoreBanner extends StatelessWidget {
  final String label;
  final String value;
  final String? subtitle;
  final String? trailing;
  const ScoreBanner({
    super.key,
    required this.label,
    required this.value,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      background: BrandColors.accent,
      padding: const EdgeInsets.all(Spacing.lg),
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: Colors.white),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: AppText.label(10, color: Colors.white.withOpacity(0.85))),
                const SizedBox(height: 2),
                Text(value, style: AppText.display(36, color: Colors.white)),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: Spacing.xxs),
                    child: Text(subtitle!, style: AppText.body(12, color: Colors.white.withOpacity(0.9))),
                  ),
              ],
            ),
            if (trailing != null)
              Positioned(
                bottom: 0, right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: Spacing.xxs),
                  decoration: const BoxDecoration(
                    color: Color(0x4D000000),
                    borderRadius: BorderRadius.all(Radius.circular(6)),
                  ),
                  child: Text(trailing!, style: AppText.label(10, color: Colors.white)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Create `lib/components/fact_card.dart`**

```dart
import 'package:flutter/material.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'app_card.dart';

class FactCard extends StatelessWidget {
  final String emblem;
  final String text;
  const FactCard({super.key, required this.emblem, required this.text});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.sm),
      child: Row(
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 42),
            padding: const EdgeInsets.symmetric(horizontal: Spacing.xxs, vertical: Spacing.xs),
            decoration: const BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.all(Radius.circular(6)),
            ),
            alignment: Alignment.center,
            child: Text(emblem, style: AppText.display(14, color: Colors.white)),
          ),
          const SizedBox(width: Spacing.md),
          Expanded(child: Text(text, style: AppText.body(12))),
        ],
      ),
    );
  }
}
```

- [ ] **Step 6: Create `lib/components/trajectory_chart.dart`**

```dart
import 'package:flutter/material.dart';
import '../theme/typography.dart';

class ChartSeries {
  final String label;
  final Color color;
  final List<double> points;
  const ChartSeries({required this.label, required this.color, required this.points});
}

class TrajectoryChart extends StatelessWidget {
  final List<ChartSeries> series;
  final List<String> xLabels;
  final double height;
  const TrajectoryChart({super.key, required this.series, required this.xLabels, this.height = 140});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 10,
          children: series
              .map((s) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 14, height: 3, color: s.color),
                      const SizedBox(width: 5),
                      Text(s.label, style: AppText.body(10)),
                    ],
                  ))
              .toList(),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: height,
          child: CustomPaint(painter: _ChartPainter(series, t.colorScheme.onSurface.withOpacity(0.12))),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: xLabels
              .map((l) => Text(l, style: AppText.body(9, color: t.colorScheme.onSurface.withOpacity(0.55))))
              .toList(),
        ),
      ],
    );
  }
}

class _ChartPainter extends CustomPainter {
  final List<ChartSeries> series;
  final Color gridColor;
  _ChartPainter(this.series, this.gridColor);

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = size.height * (i / 3);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (series.isEmpty) return;
    final maxV = series
        .expand((s) => s.points)
        .fold<double>(0, (m, v) => v > m ? v : m);
    if (maxV == 0) return;
    for (final s in series) {
      final paint = Paint()
        ..color = s.color
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke;
      final path = Path();
      for (var i = 0; i < s.points.length; i++) {
        final x = size.width * (i / (s.points.length - 1));
        final y = size.height - (s.points[i] / maxV) * size.height;
        if (i == 0) path.moveTo(x, y); else path.lineTo(x, y);
      }
      canvas.drawPath(path, paint);
      final dot = Offset(size.width, size.height - (s.points.last / maxV) * size.height);
      canvas.drawCircle(dot, 3.5, Paint()..color = s.color);
    }
  }

  @override
  bool shouldRepaint(_ChartPainter old) => true;
}
```

- [ ] **Step 7: Run tests + analyze**

Run: `flutter analyze && flutter test test/components/standings_insights_test.dart`
Expected: 4 tests PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/components/league_row.dart lib/components/score_banner.dart lib/components/fact_card.dart lib/components/trajectory_chart.dart test/components/standings_insights_test.dart
git commit -m "feat(components): LeagueRow, ScoreBanner, FactCard, TrajectoryChart"
```

---

### Task 15: BottomNav

**Files:**
- Create: `lib/components/bottom_nav.dart`
- Create: `test/components/bottom_nav_test.dart`

- [ ] **Step 1: Write failing widget test**

`test/components/bottom_nav_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/components/bottom_nav.dart';
import 'package:predictiongame/theme/app_theme.dart';

void main() {
  testWidgets('BottomNav fires onTap with the index', (tester) async {
    int? tapped;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        bottomNavigationBar: BottomNav(currentIndex: 0, onTap: (i) => tapped = i),
      ),
    ));
    await tester.tap(find.text('Calendar'));
    expect(tapped, 1);
    await tester.tap(find.text('Predict'));
    expect(tapped, 2);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/components/bottom_nav_test.dart`
Expected: FAIL.

- [ ] **Step 3: Create `lib/components/bottom_nav.dart`**

```dart
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

class BottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  const BottomNav({super.key, required this.currentIndex, required this.onTap});

  static const _items = [
    ('⌂', 'Home'),
    ('▦', 'Calendar'),
    ('◉', 'Predict'),
    ('≡', 'Standings'),
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(Spacing.xl, Spacing.sm, Spacing.xl, Spacing.xxl),
      decoration: BoxDecoration(
        color: t.colorScheme.surface,
        border: Border(top: BorderSide(color: t.strokeColor, width: Strokes.card)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: List.generate(_items.length, (i) {
            final active = i == currentIndex;
            final (ic, label) = _items[i];
            return Expanded(
              child: InkWell(
                onTap: () => onTap(i),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(ic, style: TextStyle(fontSize: 18, color: active ? BrandColors.accent : t.colorScheme.onSurface.withOpacity(0.55))),
                        const SizedBox(height: 2),
                        Text(label.toUpperCase(),
                            style: AppText.label(9, color: active ? BrandColors.accent : t.colorScheme.onSurface.withOpacity(0.55))),
                      ],
                    ),
                    if (active)
                      const Positioned(
                        top: -2,
                        child: SizedBox(
                          width: 24,
                          height: 3,
                          child: DecoratedBox(
                            decoration: BoxDecoration(color: BrandColors.accent, borderRadius: BorderRadius.all(Radius.circular(2))),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests + analyze**

Run: `flutter analyze && flutter test test/components/bottom_nav_test.dart`
Expected: 1 test PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/components/bottom_nav.dart test/components/bottom_nav_test.dart
git commit -m "feat(components): BottomNav with 4 tabs + red pill indicator"
```

---

### Task 16: Router + AppShell

**Files:**
- Create: `lib/nav/router.dart`
- Create: `lib/nav/app_shell.dart`
- Modify: `lib/app.dart`
- Create: `test/nav/router_test.dart`

- [ ] **Step 1: Write failing test**

`test/nav/router_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/mock_api_client.dart';
import 'package:predictiongame/app.dart';
import 'package:predictiongame/domain/league.dart';
import 'package:predictiongame/state/auth_controller.dart';
import 'package:predictiongame/state/league_controller.dart';
import 'package:predictiongame/state/predictions_store.dart';
import 'package:predictiongame/state/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({'current_user_id': 'anton'}));

  testWidgets('Shell shows bottom nav with 4 items when logged in', (tester) async {
    final api = MockApiClient(bundle: rootBundle);
    final auth = await AuthController.load();
    final theme = await ThemeController.load();
    final preds = await PredictionsStore.load();
    await tester.pumpWidget(F1PgApp(
      api: api, auth: auth,
      league: LeagueController(league: theBoxLeague),
      theme: theme, predictions: preds,
    ));
    await tester.pumpAndSettle();
    expect(find.text('HOME'), findsOneWidget);
    expect(find.text('CALENDAR'), findsOneWidget);
    expect(find.text('PREDICT'), findsOneWidget);
    expect(find.text('STANDINGS'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/nav/router_test.dart`
Expected: FAIL — router/shell missing.

- [ ] **Step 3: Create placeholder screen files (one-liners; real impls follow)**

For each path below, create the file with this exact body, substituting the class name:

```dart
import 'package:flutter/material.dart';
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override Widget build(BuildContext context) => const Scaffold(body: Center(child: Text('Home')));
}
```

Files (one per path, change class name):
- `lib/screens/home_screen.dart` — `HomeScreen`
- `lib/screens/calendar_screen.dart` — `CalendarScreen`
- `lib/screens/predict_screen.dart` — `PredictScreen`
- `lib/screens/session_results_screen.dart` — `SessionResultsScreen` (constructor takes `final int round; final int sessionId;`)
- `lib/screens/standings/standings_screen.dart` — `StandingsScreen` (constructor takes `final String subTab;`)
- `lib/screens/settings_screen.dart` — `SettingsScreen`
- `lib/screens/login_screen.dart` — `LoginScreen`

For `SessionResultsScreen`, the body must be:
```dart
import 'package:flutter/material.dart';
class SessionResultsScreen extends StatelessWidget {
  final int round;
  final int sessionId;
  const SessionResultsScreen({super.key, required this.round, required this.sessionId});
  @override Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text('Race $round / Session $sessionId')));
}
```

For `StandingsScreen`:
```dart
import 'package:flutter/material.dart';
class StandingsScreen extends StatelessWidget {
  final String subTab;
  const StandingsScreen({super.key, this.subTab = 'league'});
  @override Widget build(BuildContext context) => Scaffold(body: Center(child: Text('Standings: $subTab')));
}
```

- [ ] **Step 4: Create `lib/nav/app_shell.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../components/bottom_nav.dart';

class AppShell extends StatelessWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  static const _paths = ['/home', '/calendar', '/predict', '/standings'];

  int _indexFor(String location) {
    for (var i = 0; i < _paths.length; i++) {
      if (location.startsWith(_paths[i])) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    return Scaffold(
      body: child,
      bottomNavigationBar: BottomNav(
        currentIndex: _indexFor(location),
        onTap: (i) => context.go(_paths[i]),
      ),
    );
  }
}
```

- [ ] **Step 5: Create `lib/nav/router.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../screens/calendar_screen.dart';
import '../screens/home_screen.dart';
import '../screens/login_screen.dart';
import '../screens/predict_screen.dart';
import '../screens/session_results_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/standings/standings_screen.dart';
import '../state/auth_controller.dart';
import 'app_shell.dart';

GoRouter buildRouter(AuthController auth) {
  return GoRouter(
    initialLocation: '/home',
    refreshListenable: auth,
    redirect: (context, state) {
      final loggedIn = auth.isLoggedIn;
      final atLogin = state.matchedLocation == '/login';
      if (!loggedIn && !atLogin) return '/login';
      if (loggedIn && atLogin) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      ShellRoute(
        builder: (_, __, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
          GoRoute(path: '/calendar', builder: (_, __) => const CalendarScreen()),
          GoRoute(path: '/predict', builder: (_, __) => const PredictScreen()),
          GoRoute(
            path: '/standings',
            redirect: (_, s) => s.matchedLocation == '/standings' ? '/standings/league' : null,
            routes: [
              GoRoute(path: 'league', builder: (_, __) => const StandingsScreen(subTab: 'league')),
              GoRoute(path: 'f1', builder: (_, __) => const StandingsScreen(subTab: 'f1')),
              GoRoute(path: 'insights', builder: (_, __) => const StandingsScreen(subTab: 'insights')),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/race/:round/:session',
        builder: (_, s) => SessionResultsScreen(
          round: int.parse(s.pathParameters['round']!),
          sessionId: int.parse(s.pathParameters['session']!),
        ),
      ),
      GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
    ],
  );
}
```

- [ ] **Step 6: Update `lib/app.dart` to use router**

```dart
import 'package:flutter/material.dart';
import 'api/api_client.dart';
import 'nav/router.dart';
import 'state/app_state.dart';
import 'state/auth_controller.dart';
import 'state/league_controller.dart';
import 'state/predictions_store.dart';
import 'state/theme_controller.dart';
import 'theme/app_theme.dart';

class F1PgApp extends StatefulWidget {
  final ApiClient api;
  final AuthController auth;
  final LeagueController league;
  final ThemeController theme;
  final PredictionsStore predictions;

  const F1PgApp({
    super.key,
    required this.api,
    required this.auth,
    required this.league,
    required this.theme,
    required this.predictions,
  });

  @override
  State<F1PgApp> createState() => _F1PgAppState();
}

class _F1PgAppState extends State<F1PgApp> {
  late final router = buildRouter(widget.auth);

  @override
  Widget build(BuildContext context) {
    return AppState(
      api: widget.api,
      auth: widget.auth,
      league: widget.league,
      theme: widget.theme,
      predictions: widget.predictions,
      child: ListenableBuilder(
        listenable: widget.theme,
        builder: (_, __) => MaterialApp.router(
          title: 'F1PG',
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: widget.theme.mode,
          routerConfig: router,
        ),
      ),
    );
  }
}
```

- [ ] **Step 7: Run tests + analyze**

Run: `flutter analyze && flutter test test/nav/router_test.dart && flutter test`
Expected: analyze clean; all tests PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/nav/ lib/screens/ lib/app.dart test/nav/
git commit -m "feat(nav): go_router shell + placeholder screens"
```

---

### Task 17: LoginScreen (pick-a-user stub)

**Files:**
- Modify: `lib/screens/login_screen.dart`
- Create: `test/screens/login_screen_test.dart`

- [ ] **Step 1: Write failing widget test**

`test/screens/login_screen_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/mock_api_client.dart';
import 'package:predictiongame/app.dart';
import 'package:predictiongame/domain/league.dart';
import 'package:predictiongame/state/auth_controller.dart';
import 'package:predictiongame/state/league_controller.dart';
import 'package:predictiongame/state/predictions_store.dart';
import 'package:predictiongame/state/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Login lists players and signs the user in', (tester) async {
    final api = MockApiClient(bundle: rootBundle);
    final auth = await AuthController.load();
    final theme = await ThemeController.load();
    final preds = await PredictionsStore.load();
    await tester.pumpWidget(F1PgApp(
      api: api, auth: auth,
      league: LeagueController(league: theBoxLeague),
      theme: theme, predictions: preds,
    ));
    await tester.pumpAndSettle();
    expect(find.text('The Box'), findsOneWidget);
    expect(find.text('Anton'), findsOneWidget);
    await tester.tap(find.text('Anton'));
    await tester.pumpAndSettle();
    expect(auth.currentUserId, 'anton');
    expect(find.text('HOME'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/screens/login_screen_test.dart`
Expected: FAIL — placeholder doesn't pick a user.

- [ ] **Step 3: Replace `lib/screens/login_screen.dart`**

```dart
import 'package:flutter/material.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppState.of(context);
    final league = scope.league.league;
    final t = Theme.of(context);
    return Scaffold(
      backgroundColor: t.colorScheme.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.xl, Spacing.xxl, Spacing.xl, Spacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    color: Colors.black,
                    child: Text('F1', style: AppText.display(14, color: Colors.white)),
                  ),
                  const SizedBox(width: 4),
                  Text('PG', style: AppText.display(14)),
                ],
              ),
              const SizedBox(height: Spacing.xxl),
              Text('Who are you?', style: AppText.display(28)),
              const SizedBox(height: Spacing.sm),
              Text('Pick yourself to enter ${league.name}', style: AppText.body(13, color: t.colorScheme.onSurface.withOpacity(0.6))),
              const SizedBox(height: Spacing.xl),
              Expanded(
                child: ListView.separated(
                  itemCount: league.players.length,
                  separatorBuilder: (_, __) => const SizedBox(height: Spacing.sm),
                  itemBuilder: (_, i) {
                    final p = league.players[i];
                    return InkWell(
                      onTap: () => scope.auth.login(p.id),
                      borderRadius: const BorderRadius.all(Radius.circular(14)),
                      child: Container(
                        padding: const EdgeInsets.all(Spacing.lg),
                        decoration: BoxDecoration(
                          border: Border.all(color: t.strokeColor, width: Strokes.card),
                          borderRadius: const BorderRadius.all(Radius.circular(14)),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(backgroundColor: const Color(0xFFEEEEEE),
                              child: Text(p.initials, style: AppText.display(14))),
                            const SizedBox(width: Spacing.md),
                            Expanded(child: Text(p.displayName, style: AppText.body(15, weight: FontWeight.w700))),
                            const Text('›', style: TextStyle(fontSize: 22)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              Center(child: Text(league.name, style: AppText.label(10, color: BrandColors.accent))),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test + analyze**

Run: `flutter analyze && flutter test test/screens/login_screen_test.dart`
Expected: 1 test PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/login_screen.dart test/screens/login_screen_test.dart
git commit -m "feat(screens): LoginScreen (pick-a-user stub)"
```

---

### Task 18: HomeScreen

**Files:**
- Modify: `lib/screens/home_screen.dart`
- Create: `test/screens/home_screen_test.dart`

- [ ] **Step 1: Write failing widget test**

`test/screens/home_screen_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/mock_api_client.dart';
import 'package:predictiongame/app.dart';
import 'package:predictiongame/domain/league.dart';
import 'package:predictiongame/state/auth_controller.dart';
import 'package:predictiongame/state/league_controller.dart';
import 'package:predictiongame/state/predictions_store.dart';
import 'package:predictiongame/state/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({'current_user_id': 'anton'}));

  testWidgets('Home shows next race + last result + league snapshot', (tester) async {
    final api = MockApiClient(bundle: rootBundle);
    final auth = await AuthController.load();
    final theme = await ThemeController.load();
    final preds = await PredictionsStore.load();
    await tester.pumpWidget(F1PgApp(
      api: api, auth: auth,
      league: LeagueController(league: theBoxLeague),
      theme: theme, predictions: preds,
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('MONACO'), findsWidgets);
    expect(find.text('The Box · 5'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/screens/home_screen_test.dart`
Expected: FAIL — placeholder doesn't render Monaco.

- [ ] **Step 3: Replace `lib/screens/home_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../api/api_client.dart';
import '../api/models/event.dart';
import '../api/models/session.dart';
import '../api/models/session_result.dart';
import '../components/app_card.dart';
import '../components/countdown.dart';
import '../components/pod_tile.dart';
import '../components/session_chip.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Future<_HomeData>? _data;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _data ??= _load(AppState.of(context).api);
  }

  Future<_HomeData> _load(ApiClient api) async {
    final events = await api.events();
    final next = await api.nextSession();
    final last = events.lastWhere(
      (e) => e.sessions.any((s) => s.type == SessionType.race && s.status == SessionStatus.finished),
      orElse: () => events.first,
    );
    final lastRace = last.sessions.firstWhere((s) => s.type == SessionType.race);
    final lastResult = await api.sessionResults(lastRace.id);
    final nextEvent = events.firstWhere(
      (e) => e.sessions.any((s) => s.id == next.id),
      orElse: () => events.first,
    );
    return _HomeData(events: events, next: next, nextEvent: nextEvent, lastEvent: last, lastResult: lastResult);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final scope = AppState.of(context);
    return Scaffold(
      backgroundColor: t.colorScheme.surface,
      body: SafeArea(
        bottom: false,
        child: FutureBuilder<_HomeData>(
          future: _data,
          builder: (_, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) return Center(child: Text('${snap.error}'));
            final d = snap.data!;
            return ListView(
              padding: const EdgeInsets.fromLTRB(0, Spacing.lg, 0, Spacing.xxl),
              children: [
                _topbar(scope.league.league.name, scope.league.league.players.length),
                const SizedBox(height: Spacing.xs),
                _hero(d, t),
                _section('Last race · ${d.lastEvent.name}', onTap: () =>
                    context.go('/race/${d.lastEvent.round}/${d.lastEvent.sessions.firstWhere((s) => s.type == SessionType.race).id}')),
                _lastCard(d, t),
                _section('${scope.league.league.name} · Standings', onTap: () => context.go('/standings/league')),
                _leagueCard(scope.league.league.players.map((p) => p.displayName).toList(), scope.auth.currentUserId, t),
                const SizedBox(height: Spacing.xxl),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _topbar(String leagueName, int memberCount) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
        child: Row(
          children: [
            Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3), color: Colors.black,
              child: Text('F1', style: AppText.display(14, color: Colors.white))),
            const SizedBox(width: 4),
            Text('PG', style: AppText.display(14)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 5),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black, width: 1.5),
                borderRadius: const BorderRadius.all(Radius.circular(999)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 8, height: 8, decoration: const BoxDecoration(color: BrandColors.accent, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text('$leagueName · $memberCount', style: AppText.label(11)),
              ]),
            ),
            const SizedBox(width: Spacing.sm),
            IconButton(onPressed: () => context.push('/settings'), icon: const Icon(Icons.settings_outlined)),
          ],
        ),
      );

  Widget _hero(_HomeData d, ThemeData t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xs, Spacing.lg, 0),
      child: AppCard(
        background: BrandColors.accent,
        padding: const EdgeInsets.fromLTRB(Spacing.xl, Spacing.xl, Spacing.xl, Spacing.xl),
        child: DefaultTextStyle.merge(
          style: const TextStyle(color: Colors.white),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${d.nextEvent.country.toUpperCase()} · ROUND ${d.nextEvent.round}',
                  style: AppText.label(10, color: Colors.white.withOpacity(0.85))),
              const SizedBox(height: Spacing.xs),
              Text(d.nextEvent.name.toUpperCase(), style: AppText.display(28, color: Colors.white)),
              const SizedBox(height: Spacing.xs),
              Countdown(target: d.next.scheduledStart, size: 30),
              const SizedBox(height: Spacing.md),
              Row(children: _chips(d).map((c) => Padding(padding: const EdgeInsets.only(right: 6), child: c)).toList()),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _chips(_HomeData d) {
    final order = [SessionType.fp1, SessionType.fp2, SessionType.fp3,
      SessionType.qualifying, SessionType.sprint_quali, SessionType.sprint, SessionType.race];
    final labels = {
      SessionType.fp1:'FP1', SessionType.fp2:'FP2', SessionType.fp3:'FP3',
      SessionType.qualifying:'QUALI', SessionType.sprint_quali:'SQ',
      SessionType.sprint:'SPRINT', SessionType.race:'RACE',
    };
    return [
      for (final t in order)
        if (d.nextEvent.sessions.any((s) => s.type == t))
          SessionChip(label: labels[t]!, state: d.nextEvent.sessions
              .firstWhere((s) => s.type == t).status == SessionStatus.finished
              ? ChipState.done
              : (d.next.id == d.nextEvent.sessions.firstWhere((s) => s.type == t).id
                  ? ChipState.next : ChipState.idle))
    ];
  }

  Widget _section(String title, {VoidCallback? onTap}) => Padding(
        padding: const EdgeInsets.fromLTRB(Spacing.xl, Spacing.xl, Spacing.xl, Spacing.xs),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title.toUpperCase(), style: AppText.label(11)),
            if (onTap != null)
              GestureDetector(onTap: onTap, child: Text('All ›', style: AppText.label(11, color: Colors.black.withOpacity(0.5)))),
          ],
        ),
      );

  Widget _lastCard(_HomeData d, ThemeData t) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
        child: AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Top 3', style: AppText.label(11, color: t.colorScheme.onSurface.withOpacity(0.6))),
                ],
              ),
              const SizedBox(height: Spacing.sm),
              Row(children: [
                for (final r in d.lastResult.take(3))
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: PodTile(position: r.position, driverCode: r.driverCode, constructorId: r.constructorId),
                    ),
                  ),
              ]),
            ],
          ),
        ),
      );

  Widget _leagueCard(List<String> names, String? meId, ThemeData t) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
        child: AppCard(
          child: Column(
            children: List.generate(names.length.clamp(0, 4), (i) {
              final isMe = names[i].toLowerCase() == (meId ?? '');
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(children: [
                      SizedBox(width: 18, child: Text('${i+1}', style: AppText.display(13, color: isMe ? BrandColors.accent : t.colorScheme.onSurface))),
                      const SizedBox(width: 8),
                      Text(isMe ? '${names[i]} (you)' : names[i], style: AppText.body(13, weight: isMe ? FontWeight.w800 : FontWeight.w600)),
                    ]),
                    Text('${(200 - i * 18)}', style: AppText.display(13)),
                  ],
                ),
              );
            }),
          ),
        ),
      );
}

class _HomeData {
  final List<Event> events;
  final Session next;
  final Event nextEvent;
  final Event lastEvent;
  final List<SessionResult> lastResult;
  _HomeData({required this.events, required this.next, required this.nextEvent,
    required this.lastEvent, required this.lastResult});
}
```

- [ ] **Step 4: Run test + analyze**

Run: `flutter analyze && flutter test test/screens/home_screen_test.dart`
Expected: 1 test PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/home_screen.dart test/screens/home_screen_test.dart
git commit -m "feat(screens): HomeScreen — hero, last podium, league snapshot"
```

---

### Task 19: CalendarScreen

**Files:**
- Modify: `lib/screens/calendar_screen.dart`
- Create: `test/screens/calendar_screen_test.dart`

- [ ] **Step 1: Write failing widget test**

`test/screens/calendar_screen_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:predictiongame/api/mock_api_client.dart';
import 'package:predictiongame/app.dart';
import 'package:predictiongame/domain/league.dart';
import 'package:predictiongame/state/auth_controller.dart';
import 'package:predictiongame/state/league_controller.dart';
import 'package:predictiongame/state/predictions_store.dart';
import 'package:predictiongame/state/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({'current_user_id': 'anton'}));

  testWidgets('Calendar lists race weekends', (tester) async {
    final api = MockApiClient(bundle: rootBundle);
    final auth = await AuthController.load();
    final theme = await ThemeController.load();
    final preds = await PredictionsStore.load();
    await tester.pumpWidget(F1PgApp(
      api: api, auth: auth,
      league: LeagueController(league: theBoxLeague),
      theme: theme, predictions: preds,
    ));
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/calendar');
    await tester.pumpAndSettle();
    expect(find.textContaining('MONACO GP'), findsWidgets);
    expect(find.text('NEXT'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/screens/calendar_screen_test.dart`
Expected: FAIL.

- [ ] **Step 3: Replace `lib/screens/calendar_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../api/models/event.dart';
import '../api/models/session.dart';
import '../components/race_tile.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  Future<List<Event>>? _events;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _events ??= AppState.of(context).api.events();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        bottom: false,
        child: FutureBuilder<List<Event>>(
          future: _events,
          builder: (_, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) return Center(child: Text('${snap.error}'));
            final events = snap.data!..sort((a,b) => a.round.compareTo(b.round));
            final children = <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(Spacing.xl, Spacing.lg, Spacing.xl, Spacing.xs),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Calendar'.toUpperCase(), style: AppText.display(28)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 5),
                      decoration: BoxDecoration(border: Border.all(color: Colors.black, width: 1.5), borderRadius: const BorderRadius.all(Radius.circular(999))),
                      child: const Text('2026 ▾', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11)),
                    ),
                  ],
                ),
              ),
            ];
            String? lastMonth;
            for (final e in events) {
              final race = e.sessions.firstWhere((s) => s.type == SessionType.race, orElse: () => e.sessions.first);
              final month = DateFormat('MMMM').format(race.scheduledStart);
              if (month != lastMonth) {
                children.add(Padding(
                  padding: const EdgeInsets.fromLTRB(Spacing.xl, Spacing.lg, Spacing.xl, Spacing.xs),
                  child: Row(children: [
                    Text(month.toUpperCase(), style: AppText.label(11)),
                    const SizedBox(width: 10),
                    Expanded(child: Container(height: 1, color: Colors.black.withOpacity(0.15))),
                  ]),
                ));
                lastMonth = month;
              }
              final now = DateTime.now();
              final raceState = race.scheduledStart.isAfter(now.add(const Duration(days: 0)))
                  ? (events.where((x) => x.sessions.any((s) => s.scheduledStart.isAfter(now))).first.round == e.round
                      ? RaceState.next : RaceState.future)
                  : RaceState.past;
              children.add(Padding(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: 5),
                child: RaceTile(
                  round: e.round,
                  country: '${e.country} · ${e.circuitName}',
                  name: e.name,
                  when: '${DateFormat('d MMM').format(e.sessions.first.scheduledStart)} – ${DateFormat('d MMM').format(race.scheduledStart)}',
                  state: raceState,
                  sprint: e.hasSprint,
                  distanceFromNow: raceState == RaceState.future ? _humanDelta(race.scheduledStart) : null,
                  onTap: () => context.push('/race/${e.round}/${race.id}'),
                ),
              ));
            }
            children.add(const SizedBox(height: Spacing.xxl));
            return ListView(children: children);
          },
        ),
      ),
    );
  }

  String _humanDelta(DateTime when) {
    final d = when.difference(DateTime.now()).inDays;
    return 'in ${d}d';
  }
}
```

- [ ] **Step 4: Run test + analyze**

Run: `flutter analyze && flutter test test/screens/calendar_screen_test.dart`
Expected: 1 test PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/calendar_screen.dart test/screens/calendar_screen_test.dart
git commit -m "feat(screens): CalendarScreen with month dividers + race tiles"
```

---

### Task 20: PredictScreen

**Files:**
- Modify: `lib/screens/predict_screen.dart`
- Create: `test/screens/predict_screen_test.dart`

- [ ] **Step 1: Write failing widget test**

`test/screens/predict_screen_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:predictiongame/api/mock_api_client.dart';
import 'package:predictiongame/app.dart';
import 'package:predictiongame/domain/league.dart';
import 'package:predictiongame/state/auth_controller.dart';
import 'package:predictiongame/state/league_controller.dart';
import 'package:predictiongame/state/predictions_store.dart';
import 'package:predictiongame/state/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({'current_user_id': 'anton'}));

  testWidgets('Predict shows slots and tapping a driver fills next slot',
      (tester) async {
    final api = MockApiClient(bundle: rootBundle);
    final auth = await AuthController.load();
    final theme = await ThemeController.load();
    final preds = await PredictionsStore.load();
    await tester.pumpWidget(F1PgApp(
      api: api, auth: auth,
      league: LeagueController(league: theBoxLeague),
      theme: theme, predictions: preds,
    ));
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/predict');
    await tester.pumpAndSettle();
    expect(find.text('P1'), findsWidgets);
    expect(find.text('Tap a driver below'), findsWidgets);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/screens/predict_screen_test.dart`
Expected: FAIL.

- [ ] **Step 3: Replace `lib/screens/predict_screen.dart`**

```dart
import 'package:flutter/material.dart';
import '../api/models/event.dart';
import '../api/models/session.dart';
import '../api/models/session_result.dart';
import '../components/driver_tile.dart';
import '../components/slot.dart';
import '../domain/prediction.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

class PredictScreen extends StatefulWidget {
  const PredictScreen({super.key});
  @override
  State<PredictScreen> createState() => _PredictScreenState();
}

class _PredictScreenState extends State<PredictScreen> {
  Future<_PredictData>? _data;
  List<String> _picks = [];

  Future<_PredictData> _load() async {
    final scope = AppState.of(context);
    final events = await scope.api.events();
    final upcoming = events.firstWhere(
      (e) => e.sessions.any((s) => s.status == SessionStatus.scheduled),
      orElse: () => events.last,
    );
    final session = upcoming.sessions.firstWhere(
      (s) => s.status == SessionStatus.scheduled,
      orElse: () => upcoming.sessions.last,
    );
    final existing = scope.predictions.picksFor(userId: scope.auth.currentUserId!, sessionId: session.id);
    _picks = List<String>.from(existing);
    // Drivers from most recent finished session as a proxy lineup
    final finished = events.expand((e) => e.sessions).where((s) => s.status == SessionStatus.finished).toList();
    finished.sort((a,b) => b.scheduledStart.compareTo(a.scheduledStart));
    final lineup = finished.isEmpty ? <SessionResult>[] : await scope.api.sessionResults(finished.first.id);
    return _PredictData(event: upcoming, session: session, drivers: lineup);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _data ??= _load();
  }

  void _toggleDriver(String code) {
    final required = requiredPicks(/*from data*/ _currentType);
    setState(() {
      if (_picks.contains(code)) {
        _picks.remove(code);
      } else if (_picks.length < required) {
        _picks.add(code);
      }
    });
  }

  SessionType _currentType = SessionType.race;

  Future<void> _lock() async {
    final scope = AppState.of(context);
    final session = (await _data!).session;
    await scope.predictions.save(userId: scope.auth.currentUserId!, sessionId: session.id, picks: _picks);
    await scope.predictions.lock(userId: scope.auth.currentUserId!, sessionId: session.id);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pick locked')));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      backgroundColor: t.colorScheme.surface,
      body: SafeArea(
        bottom: false,
        child: FutureBuilder<_PredictData>(
          future: _data,
          builder: (_, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) return Center(child: Text('${snap.error}'));
            final d = snap.data!;
            _currentType = d.session.type;
            final req = requiredPicks(d.session.type);
            return ListView(
              padding: const EdgeInsets.only(bottom: Spacing.xxl + Spacing.xxl),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(Spacing.xl, Spacing.lg, Spacing.xl, Spacing.sm),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text(d.event.name, style: AppText.display(22)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 4),
                      decoration: BoxDecoration(border: Border.all(color: BrandColors.accent, width: 1.5), borderRadius: const BorderRadius.all(Radius.circular(999))),
                      child: Text(_lockLabel(d.session.scheduledStart), style: AppText.label(10, color: BrandColors.accent)),
                    ),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Spacing.xl, Spacing.md, Spacing.xl, Spacing.xs),
                  child: Text('${d.session.type.name.toUpperCase()} · TOP $req', style: AppText.label(11, color: t.colorScheme.onSurface.withOpacity(0.6))),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Spacing.lg, 6, Spacing.lg, 6),
                  child: Column(
                    children: List.generate(req, (i) {
                      final filled = i < _picks.length;
                      final pickCode = filled ? _picks[i] : null;
                      final r = filled ? d.drivers.firstWhere((dr) => dr.driverCode == pickCode, orElse: () => d.drivers.first) : null;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Slot(
                          position: i + 1,
                          driverCode: pickCode,
                          driverName: r?.driverName,
                          number: null,
                          constructorId: r?.constructorId,
                          onClear: filled ? () => setState(() => _picks.removeAt(i)) : null,
                        ),
                      );
                    }),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.lg, Spacing.lg, Spacing.sm),
                  child: Text('DRIVERS', style: AppText.label(11, color: t.colorScheme.onSurface.withOpacity(0.6))),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
                  child: GridView.count(
                    crossAxisCount: 4,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                    childAspectRatio: 1.4,
                    children: d.drivers.map((r) {
                      final slot = _picks.indexOf(r.driverCode);
                      return DriverTile(
                        code: r.driverCode,
                        constructorId: r.constructorId,
                        pickedSlot: slot == -1 ? null : slot + 1,
                        onTap: () => _toggleDriver(r.driverCode),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: Spacing.xxl),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _picks.length == req ? _lock : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: BrandColors.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: Spacing.md),
                        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                      ),
                      child: Text('LOCK PICK', style: AppText.label(13, color: Colors.white)),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _lockLabel(DateTime when) {
    final diff = when.difference(DateTime.now());
    if (diff.isNegative) return 'LOCKED';
    return 'LOCKS IN ${diff.inHours}h ${diff.inMinutes.remainder(60)}m';
  }
}

class _PredictData {
  final Event event;
  final Session session;
  final List<SessionResult> drivers;
  _PredictData({required this.event, required this.session, required this.drivers});
}
```

- [ ] **Step 4: Run test + analyze**

Run: `flutter analyze && flutter test test/screens/predict_screen_test.dart`
Expected: 1 test PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/predict_screen.dart test/screens/predict_screen_test.dart
git commit -m "feat(screens): PredictScreen with slots + driver grid + lock CTA"
```

---

### Task 21: SessionResultsScreen

**Files:**
- Modify: `lib/screens/session_results_screen.dart`
- Create: `test/screens/session_results_screen_test.dart`

- [ ] **Step 1: Write failing widget test**

`test/screens/session_results_screen_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:predictiongame/api/mock_api_client.dart';
import 'package:predictiongame/app.dart';
import 'package:predictiongame/domain/league.dart';
import 'package:predictiongame/state/auth_controller.dart';
import 'package:predictiongame/state/league_controller.dart';
import 'package:predictiongame/state/predictions_store.dart';
import 'package:predictiongame/state/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({'current_user_id': 'anton'}));

  testWidgets('Session results shows score banner + classification',
      (tester) async {
    final api = MockApiClient(bundle: rootBundle);
    final auth = await AuthController.load();
    final theme = await ThemeController.load();
    final preds = await PredictionsStore.load();
    await tester.pumpWidget(F1PgApp(
      api: api, auth: auth,
      league: LeagueController(league: theBoxLeague),
      theme: theme, predictions: preds,
    ));
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.byType(Scaffold).first)).push('/race/7/42');
    await tester.pumpAndSettle();
    expect(find.text('NOR'), findsWidgets);
    expect(find.textContaining('Your score'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/screens/session_results_screen_test.dart`
Expected: FAIL.

- [ ] **Step 3: Replace `lib/screens/session_results_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../api/models/event.dart';
import '../api/models/session_result.dart';
import '../components/app_card.dart';
import '../components/score_banner.dart';
import '../domain/scoring.dart';
import '../state/app_state.dart';
import '../theme/colors.dart';
import '../theme/team_colors.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

class SessionResultsScreen extends StatefulWidget {
  final int round;
  final int sessionId;
  const SessionResultsScreen({super.key, required this.round, required this.sessionId});
  @override
  State<SessionResultsScreen> createState() => _SessionResultsScreenState();
}

class _SessionResultsScreenState extends State<SessionResultsScreen> {
  Future<_RaceData>? _data;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _data ??= _load();
  }

  Future<_RaceData> _load() async {
    final scope = AppState.of(context);
    final event = await scope.api.event(widget.round);
    final result = await scope.api.sessionResults(widget.sessionId);
    final myPicks = scope.predictions.picksFor(
      userId: scope.auth.currentUserId ?? 'anton',
      sessionId: widget.sessionId,
    );
    return _RaceData(event: event, result: result, myPicks: myPicks);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      backgroundColor: t.colorScheme.surface,
      body: SafeArea(
        child: FutureBuilder<_RaceData>(
          future: _data,
          builder: (_, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) return Center(child: Text('${snap.error}'));
            final d = snap.data!;
            final score = scoreRace(d.myPicks, d.result);
            final picksHits = d.myPicks.asMap().entries.map((e) {
              final o = outcomeFor(e.value, e.key + 1, d.result, 5);
              return (slot: e.key + 1, code: e.value, outcome: o);
            }).toList();
            return ListView(
              padding: const EdgeInsets.only(bottom: Spacing.xxl),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.lg, Spacing.lg, Spacing.sm),
                  child: Row(
                    children: [
                      IconButton(onPressed: () => context.pop(), icon: const Icon(Icons.arrow_back_ios_new, size: 16)),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(d.event.name, style: AppText.display(20)),
                            Text('Round ${d.event.round} · Race', style: AppText.label(10, color: t.colorScheme.onSurface.withOpacity(0.55))),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
                  child: ScoreBanner(
                    label: 'Your score',
                    value: '+$score',
                    subtitle: '${picksHits.where((p) => p.outcome == PickOutcome.exact).length} exact · ${picksHits.where((p) => p.outcome == PickOutcome.inTopN).length} in top-5 · ${picksHits.where((p) => p.outcome == PickOutcome.miss).length} miss',
                  ),
                ),
                if (d.myPicks.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.lg, Spacing.lg, Spacing.xs),
                    child: Text('PICK VS RESULT', style: AppText.label(11, color: t.colorScheme.onSurface.withOpacity(0.6))),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
                    child: AppCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: picksHits.map((p) {
                          final actual = d.result.firstWhere((r) => r.position == p.slot,
                              orElse: () => d.result.first);
                          final color = switch (p.outcome) {
                            PickOutcome.exact => BrandColors.ok,
                            PickOutcome.inTopN => BrandColors.near,
                            PickOutcome.miss => Colors.black,
                          };
                          final glyph = switch (p.outcome) {
                            PickOutcome.exact => '✓',
                            PickOutcome.inTopN => '~',
                            PickOutcome.miss => '✗',
                          };
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 8),
                            child: Row(
                              children: [
                                SizedBox(width: 24, child: Text('P${p.slot}', style: AppText.display(14))),
                                Expanded(child: Text(p.code, style: AppText.body(13, weight: FontWeight.w700))),
                                Container(width: 22, height: 22, alignment: Alignment.center,
                                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                                  child: Text(glyph, style: TextStyle(color: p.outcome == PickOutcome.miss ? Colors.white : Colors.black, fontWeight: FontWeight.w900, fontSize: 11))),
                                Expanded(child: Text(actual.driverCode, textAlign: TextAlign.right, style: AppText.body(13, weight: FontWeight.w700))),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
                Padding(
                  padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.lg, Spacing.lg, Spacing.xs),
                  child: Text('FULL CLASSIFICATION', style: AppText.label(11, color: t.colorScheme.onSurface.withOpacity(0.6))),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
                  child: AppCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: d.result.map((r) {
                        final mine = d.myPicks.contains(r.driverCode);
                        return Container(
                          color: mine ? const Color(0xFFFFF7D1) : null,
                          padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 7),
                          child: Row(
                            children: [
                              SizedBox(width: 22, child: Text('${r.position}', style: AppText.display(13))),
                              Container(width: 3, height: 18, color: teamColor(r.constructorId)),
                              const SizedBox(width: Spacing.sm),
                              Expanded(child: Text('${r.driverCode}  ${r.driverName}', style: AppText.body(12, weight: FontWeight.w600))),
                              Text(r.raceTime ?? '', style: AppText.display(11, color: t.colorScheme.onSurface.withOpacity(0.6))),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _RaceData {
  final Event event;
  final List<SessionResult> result;
  final List<String> myPicks;
  _RaceData({required this.event, required this.result, required this.myPicks});
}
```

- [ ] **Step 4: Run test + analyze**

Run: `flutter analyze && flutter test test/screens/session_results_screen_test.dart`
Expected: 1 test PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/session_results_screen.dart test/screens/session_results_screen_test.dart
git commit -m "feat(screens): SessionResults with pick-vs-result diff + full classification"
```

---

### Task 22: StandingsScreen with 3 sub-tabs (League / F1 / Insights)

**Files:**
- Modify: `lib/screens/standings/standings_screen.dart`
- Create: `lib/screens/standings/league_tab.dart`
- Create: `lib/screens/standings/f1_tab.dart`
- Create: `lib/screens/standings/insights_tab.dart`
- Create: `test/screens/standings_test.dart`

- [ ] **Step 1: Write failing widget test**

`test/screens/standings_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:predictiongame/api/mock_api_client.dart';
import 'package:predictiongame/app.dart';
import 'package:predictiongame/domain/league.dart';
import 'package:predictiongame/state/auth_controller.dart';
import 'package:predictiongame/state/league_controller.dart';
import 'package:predictiongame/state/predictions_store.dart';
import 'package:predictiongame/state/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({'current_user_id': 'anton'}));

  testWidgets('Standings League shows player names', (tester) async {
    final api = MockApiClient(bundle: rootBundle);
    final auth = await AuthController.load();
    final theme = await ThemeController.load();
    final preds = await PredictionsStore.load();
    await tester.pumpWidget(F1PgApp(
      api: api, auth: auth,
      league: LeagueController(league: theBoxLeague),
      theme: theme, predictions: preds,
    ));
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/standings/league');
    await tester.pumpAndSettle();
    expect(find.text('Lukas'), findsWidgets);
    expect(find.text('Simon'), findsWidgets);
  });

  testWidgets('F1 tab shows driver standings', (tester) async {
    final api = MockApiClient(bundle: rootBundle);
    final auth = await AuthController.load();
    final theme = await ThemeController.load();
    final preds = await PredictionsStore.load();
    await tester.pumpWidget(F1PgApp(
      api: api, auth: auth,
      league: LeagueController(league: theBoxLeague),
      theme: theme, predictions: preds,
    ));
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/standings/f1');
    await tester.pumpAndSettle();
    expect(find.text('NOR'), findsWidgets);
  });

  testWidgets('Insights tab shows stat grid', (tester) async {
    final api = MockApiClient(bundle: rootBundle);
    final auth = await AuthController.load();
    final theme = await ThemeController.load();
    final preds = await PredictionsStore.load();
    await tester.pumpWidget(F1PgApp(
      api: api, auth: auth,
      league: LeagueController(league: theBoxLeague),
      theme: theme, predictions: preds,
    ));
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/standings/insights');
    await tester.pumpAndSettle();
    expect(find.text('TOTAL POINTS'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/screens/standings_test.dart`
Expected: FAIL.

- [ ] **Step 3: Replace `lib/screens/standings/standings_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../state/app_state.dart';
import '../../theme/colors.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import 'f1_tab.dart';
import 'insights_tab.dart';
import 'league_tab.dart';

class StandingsScreen extends StatelessWidget {
  final String subTab;
  const StandingsScreen({super.key, this.subTab = 'league'});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final scope = AppState.of(context);
    return Scaffold(
      backgroundColor: t.colorScheme.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Spacing.xl, Spacing.lg, Spacing.xl, Spacing.xs),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Standings'.toUpperCase(), style: AppText.display(28)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 5),
                    decoration: BoxDecoration(border: Border.all(color: Colors.black, width: 1.5), borderRadius: const BorderRadius.all(Radius.circular(999))),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(width: 8, height: 8, decoration: const BoxDecoration(color: BrandColors.accent, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Text('${scope.league.league.name} · ${scope.league.league.players.length}', style: AppText.label(11)),
                    ]),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Spacing.xl, Spacing.md, Spacing.xl, Spacing.xs),
              child: Row(children: [
                Expanded(child: _tab(context, 'league', 'LEAGUE')),
                const SizedBox(width: 6),
                Expanded(child: _tab(context, 'f1', 'F1')),
                const SizedBox(width: 6),
                Expanded(child: _tab(context, 'insights', 'INSIGHTS')),
              ]),
            ),
            Expanded(child: switch (subTab) {
              'f1' => const F1Tab(),
              'insights' => const InsightsTab(),
              _ => const LeagueTab(),
            }),
          ],
        ),
      ),
    );
  }

  Widget _tab(BuildContext context, String id, String label) {
    final on = subTab == id;
    return GestureDetector(
      onTap: () => context.go('/standings/$id'),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: on ? Colors.black : Colors.transparent,
          border: Border.all(color: Colors.black, width: 1.5),
          borderRadius: const BorderRadius.all(Radius.circular(8)),
        ),
        child: Text(label, textAlign: TextAlign.center, style: AppText.label(10, color: on ? Colors.white : Colors.black)),
      ),
    );
  }
}
```

- [ ] **Step 4: Create `lib/screens/standings/league_tab.dart`**

```dart
import 'package:flutter/material.dart';
import '../../components/app_card.dart';
import '../../components/league_row.dart';
import '../../components/trend_badge.dart';
import '../../state/app_state.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';

class LeagueTab extends StatelessWidget {
  const LeagueTab({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppState.of(context);
    final players = scope.league.league.players;
    // Mock cumulative points per player (deterministic ordering for visual)
    final rows = List.generate(players.length, (i) => (
      player: players[i],
      points: 200 - i * 18,
    ));
    rows.sort((a, b) => b.points.compareTo(a.points));
    return ListView(
      padding: const EdgeInsets.only(bottom: Spacing.xxl),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.md, Spacing.lg, 0),
          child: _Podium(rows: rows.take(3).toList()),
        ),
        const SizedBox(height: Spacing.md),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
          child: AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: List.generate(rows.length, (i) {
                final r = rows[i];
                final me = r.player.id == scope.auth.currentUserId;
                return LeagueRow(
                  rank: i + 1,
                  initials: r.player.initials,
                  name: me ? '${r.player.displayName} (you)' : r.player.displayName,
                  points: r.points,
                  trend: TrendDirection.equal,
                  isMe: me,
                );
              }),
            ),
          ),
        ),
      ],
    );
  }
}

class _Podium extends StatelessWidget {
  final List<dynamic> rows;
  const _Podium({required this.rows});
  @override
  Widget build(BuildContext context) {
    if (rows.length < 3) return const SizedBox.shrink();
    final colors = [const Color(0xFFFFD233), const Color(0xFFCFCFCF), const Color(0xFFC08350)];
    final heights = [60.0, 42.0, 30.0];
    final order = [rows[1], rows[0], rows[2]]; // visual: 2-1-3
    final pos = [2, 1, 3];
    return AppCard(
      background: const Color(0xFFFAFAFA),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(3, (i) {
          final r = order[i];
          final p = pos[i];
          return Expanded(
            child: Column(
              children: [
                CircleAvatar(backgroundColor: p == 1 ? const Color(0xFFFFD233) : Colors.black,
                  child: Text(r.player.initials, style: AppText.display(14, color: p == 1 ? Colors.black : Colors.white))),
                const SizedBox(height: 6),
                Text(r.player.displayName, style: AppText.label(11)),
                Text('${r.points}', style: AppText.display(13)),
                const SizedBox(height: 6),
                Container(width: double.infinity, height: heights[i],
                  color: colors[i],
                  alignment: Alignment.center,
                  child: Text('$p', style: AppText.display(18))),
              ],
            ),
          );
        }),
      ),
    );
  }
}
```

- [ ] **Step 5: Create `lib/screens/standings/f1_tab.dart`**

```dart
import 'package:flutter/material.dart';
import '../../api/models/standing.dart';
import '../../components/app_card.dart';
import '../../components/league_row.dart';
import '../../components/trend_badge.dart';
import '../../state/app_state.dart';
import '../../theme/team_colors.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';

class F1Tab extends StatefulWidget {
  const F1Tab({super.key});
  @override
  State<F1Tab> createState() => _F1TabState();
}

class _F1TabState extends State<F1Tab> {
  String _which = 'drivers';
  Future<List<DriverStanding>>? _drivers;
  Future<List<ConstructorStanding>>? _constructors;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final api = AppState.of(context).api;
    _drivers ??= api.driverStandings();
    _constructors ??= api.constructorStandings();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.md, Spacing.lg, Spacing.sm),
        child: Row(children: [
          _seg('drivers', 'DRIVERS'),
          _seg('constructors', 'CONSTRUCTORS'),
        ]),
      ),
      Expanded(child: _which == 'drivers' ? _driverList() : _constructorList()),
    ]);
  }

  Widget _seg(String id, String label) {
    final on = id == _which;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () => setState(() => _which = id),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 6),
          decoration: BoxDecoration(
            color: on ? Colors.black : null,
            border: Border.all(color: Colors.black, width: 1.5),
            borderRadius: const BorderRadius.all(Radius.circular(8)),
          ),
          child: Text(label, style: AppText.label(10, color: on ? Colors.white : Colors.black)),
        ),
      ),
    );
  }

  Widget _driverList() => FutureBuilder<List<DriverStanding>>(
        future: _drivers,
        builder: (_, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) return Center(child: Text('${snap.error}'));
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: Spacing.md),
            children: [
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: snap.data!.map((d) => LeagueRow(
                    rank: d.position, initials: d.driverCode, name: d.driverName,
                    subtitle: '${d.wins} wins',
                    points: d.points, trend: TrendDirection.equal,
                  )).toList(),
                ),
              ),
            ],
          );
        },
      );

  Widget _constructorList() => FutureBuilder<List<ConstructorStanding>>(
        future: _constructors,
        builder: (_, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) return Center(child: Text('${snap.error}'));
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: Spacing.md),
            children: [
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: snap.data!.map((c) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 10),
                    child: Row(
                      children: [
                        SizedBox(width: 24, child: Text('${c.position}', style: AppText.display(16))),
                        Container(width: 4, height: 22, color: teamColor(c.constructorId)),
                        const SizedBox(width: 10),
                        Expanded(child: Text(c.constructorName, style: AppText.body(13, weight: FontWeight.w700))),
                        Text('${c.points}', style: AppText.display(16)),
                      ],
                    ),
                  )).toList(),
                ),
              ),
            ],
          );
        },
      );
}
```

- [ ] **Step 6: Create `lib/screens/standings/insights_tab.dart`**

```dart
import 'package:flutter/material.dart';
import '../../components/app_card.dart';
import '../../components/fact_card.dart';
import '../../components/trajectory_chart.dart';
import '../../theme/colors.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';

class InsightsTab extends StatelessWidget {
  const InsightsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.only(bottom: Spacing.xxl),
      children: [
        _h('YOUR SEASON'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
          child: GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            childAspectRatio: 2.0,
            children: [
              _stat(t, 'TOTAL POINTS', '148', '3rd of 5', accent: true),
              _stat(t, 'AVERAGE / ROUND', '21.1', 'league avg 19.6'),
              _stat(t, 'HIT RATE', '62%', '22 of 35 picks'),
              _stat(t, 'BEST ROUND', '+24', 'Imola · R7'),
            ],
          ),
        ),
        _h('TRAJECTORY'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
          child: AppCard(
            child: const TrajectoryChart(
              series: [
                ChartSeries(label: 'Lukas', color: Colors.black, points: [0, 25, 50, 75, 100, 125, 150, 167]),
                ChartSeries(label: 'You', color: BrandColors.accent, points: [0, 18, 40, 56, 72, 90, 114, 148]),
                ChartSeries(label: 'Avg', color: Color(0xFFBBBBBB), points: [0, 12, 25, 40, 55, 75, 100, 120]),
              ],
              xLabels: ['R1','R2','R3','R4','R5','R6','R7','R8'],
            ),
          ),
        ),
        _h('LEAGUE GOSSIP'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
          child: Column(children: const [
            FactCard(emblem: '★', text: 'Lukas has won 4 of 7 rounds — runaway form.'),
            SizedBox(height: 6),
            FactCard(emblem: '!?', text: 'Paul missed last week\'s pick — first zero of the season.'),
            SizedBox(height: 6),
            FactCard(emblem: '≈', text: 'Imola was the closest round: 4-point spread between top 4.'),
          ]),
        ),
      ],
    );
  }

  Widget _h(String s) => Padding(
        padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.lg, Spacing.lg, Spacing.xs),
        child: Text(s, style: AppText.label(11)),
      );

  Widget _stat(ThemeData t, String label, String value, String extra, {bool accent = false}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(Spacing.md, Spacing.sm, Spacing.md, Spacing.sm),
      decoration: BoxDecoration(
        color: accent ? BrandColors.accent : null,
        border: Border.all(color: Colors.black, width: 2),
        borderRadius: const BorderRadius.all(Radius.circular(12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppText.label(9, color: accent ? Colors.white.withOpacity(0.9) : t.colorScheme.onSurface.withOpacity(0.55))),
          const SizedBox(height: 4),
          Text(value, style: AppText.display(24, color: accent ? Colors.white : t.colorScheme.onSurface)),
          Text(extra, style: AppText.body(10, color: accent ? Colors.white.withOpacity(0.85) : t.colorScheme.onSurface.withOpacity(0.6))),
        ],
      ),
    );
  }
}
```

- [ ] **Step 7: Run tests + analyze**

Run: `flutter analyze && flutter test test/screens/standings_test.dart`
Expected: 3 tests PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/screens/standings/ test/screens/standings_test.dart
git commit -m "feat(screens): Standings with League, F1, Insights sub-tabs"
```

---

### Task 23: SettingsScreen

**Files:**
- Modify: `lib/screens/settings_screen.dart`
- Create: `test/screens/settings_screen_test.dart`

- [ ] **Step 1: Write failing widget test**

`test/screens/settings_screen_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:predictiongame/api/mock_api_client.dart';
import 'package:predictiongame/app.dart';
import 'package:predictiongame/domain/league.dart';
import 'package:predictiongame/state/auth_controller.dart';
import 'package:predictiongame/state/league_controller.dart';
import 'package:predictiongame/state/predictions_store.dart';
import 'package:predictiongame/state/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({'current_user_id': 'anton'}));

  testWidgets('Settings toggles theme + signs out', (tester) async {
    final api = MockApiClient(bundle: rootBundle);
    final auth = await AuthController.load();
    final theme = await ThemeController.load();
    final preds = await PredictionsStore.load();
    await tester.pumpWidget(F1PgApp(
      api: api, auth: auth,
      league: LeagueController(league: theBoxLeague),
      theme: theme, predictions: preds,
    ));
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.byType(Scaffold).first)).push('/settings');
    await tester.pumpAndSettle();
    expect(find.text('THEME'), findsOneWidget);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(theme.mode, ThemeMode.dark);

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(auth.isLoggedIn, false);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/screens/settings_screen_test.dart`
Expected: FAIL.

- [ ] **Step 3: Replace `lib/screens/settings_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../state/app_state.dart';
import '../theme/colors.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final scope = AppState.of(context);
    final currentName = scope.league.league.players
        .firstWhere((p) => p.id == scope.auth.currentUserId,
            orElse: () => scope.league.league.players.first)
        .displayName;
    return Scaffold(
      backgroundColor: t.colorScheme.surface,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(Spacing.lg),
          children: [
            Row(children: [
              IconButton(onPressed: () => context.pop(), icon: const Icon(Icons.arrow_back_ios_new, size: 16)),
              Text('Settings'.toUpperCase(), style: AppText.display(24)),
            ]),
            const SizedBox(height: Spacing.lg),
            Text('THEME', style: AppText.label(11)),
            const SizedBox(height: Spacing.sm),
            ListenableBuilder(
              listenable: scope.theme,
              builder: (_, __) => Row(children: [
                _opt(context, 'Light', ThemeMode.light, scope.theme.mode),
                _opt(context, 'Dark', ThemeMode.dark, scope.theme.mode),
                _opt(context, 'System', ThemeMode.system, scope.theme.mode),
              ]),
            ),
            const SizedBox(height: Spacing.xl),
            Text('ACCOUNT', style: AppText.label(11)),
            const SizedBox(height: Spacing.sm),
            Container(
              padding: const EdgeInsets.all(Spacing.lg),
              decoration: BoxDecoration(border: Border.all(color: Colors.black, width: 2), borderRadius: const BorderRadius.all(Radius.circular(14))),
              child: Row(children: [
                Expanded(child: Text(currentName, style: AppText.body(14, weight: FontWeight.w700))),
                TextButton(onPressed: () => scope.auth.logout(), child: const Text('Sign out')),
              ]),
            ),
            const SizedBox(height: Spacing.xl),
            Text('LEAGUE', style: AppText.label(11)),
            const SizedBox(height: Spacing.sm),
            Container(
              padding: const EdgeInsets.all(Spacing.lg),
              decoration: BoxDecoration(border: Border.all(color: Colors.black, width: 2), borderRadius: const BorderRadius.all(Radius.circular(14))),
              child: Text(scope.league.league.name, style: AppText.body(14, weight: FontWeight.w700)),
            ),
            const SizedBox(height: Spacing.xl),
            Text('ABOUT', style: AppText.label(11)),
            const SizedBox(height: Spacing.sm),
            Text('F1 Prediction Game · v1.0.0', style: AppText.body(12, color: t.colorScheme.onSurface.withOpacity(0.6))),
          ],
        ),
      ),
    );
  }

  Widget _opt(BuildContext context, String label, ThemeMode m, ThemeMode current) {
    final on = m == current;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () => AppState.of(context).theme.setMode(m),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 7),
          decoration: BoxDecoration(
            color: on ? BrandColors.accent : null,
            border: Border.all(color: Colors.black, width: 1.5),
            borderRadius: const BorderRadius.all(Radius.circular(8)),
          ),
          child: Text(label, style: AppText.label(11, color: on ? Colors.white : Colors.black)),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test + analyze**

Run: `flutter analyze && flutter test test/screens/settings_screen_test.dart`
Expected: 1 test PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/settings_screen.dart test/screens/settings_screen_test.dart
git commit -m "feat(screens): SettingsScreen with theme toggle + sign out"
```

---

### Task 24: Integration flow + final polish

**Files:**
- Create: `test/integration/pick_lock_flow_test.dart`
- Modify: `pubspec.yaml` (register Anton + Inter font families; only if google_fonts caching is disabled in tests)

- [ ] **Step 1: Write end-to-end integration test**

`test/integration/pick_lock_flow_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:predictiongame/api/mock_api_client.dart';
import 'package:predictiongame/app.dart';
import 'package:predictiongame/domain/league.dart';
import 'package:predictiongame/state/auth_controller.dart';
import 'package:predictiongame/state/league_controller.dart';
import 'package:predictiongame/state/predictions_store.dart';
import 'package:predictiongame/state/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({'current_user_id': 'anton'}));

  testWidgets('Login → predict → lock → home shows lock state', (tester) async {
    final api = MockApiClient(bundle: rootBundle);
    final auth = await AuthController.load();
    final theme = await ThemeController.load();
    final preds = await PredictionsStore.load();
    await tester.pumpWidget(F1PgApp(
      api: api, auth: auth,
      league: LeagueController(league: theBoxLeague),
      theme: theme, predictions: preds,
    ));
    await tester.pumpAndSettle();

    // Go to Predict via bottom nav
    await tester.tap(find.text('PREDICT'));
    await tester.pumpAndSettle();
    expect(find.text('P1'), findsWidgets);

    // Tap five distinct driver codes from mock results
    for (final code in ['NOR', 'PIA', 'LEC', 'TSU', 'RUS']) {
      await tester.tap(find.text(code).first);
      await tester.pump();
    }

    // Lock button enabled — tap it
    await tester.tap(find.text('LOCK PICK'));
    await tester.pumpAndSettle();
    expect(preds.isLocked(userId: 'anton', sessionId: 52), true);

    // Back to home — verify pick is persisted
    await tester.tap(find.text('HOME'));
    await tester.pumpAndSettle();
    expect(find.byType(Scaffold), findsWidgets);
  });
}
```

- [ ] **Step 2: Run the integration test**

Run: `flutter test test/integration/pick_lock_flow_test.dart`
Expected: PASS.

- [ ] **Step 3: Run the whole suite + analyze**

Run: `flutter analyze && flutter test`
Expected: analyze clean (0 issues); all tests PASS.

- [ ] **Step 4: Smoke run on a platform**

Run on one device of choice:
```bash
flutter run -d chrome --dart-define=USE_MOCK=true
```
Expected: app boots into Login → pick Anton → Home renders Monaco hero + last podium + league snapshot. Bottom nav switches between Home / Calendar / Predict / Standings.

- [ ] **Step 5: Commit**

```bash
git add test/integration/
git commit -m "test: end-to-end pick → lock flow"
```

- [ ] **Step 6: Final commit summary**

After all green, post a short note in PR description / commit message linking back to the spec at `docs/superpowers/specs/2026-05-25-frontend-redesign-design.md`. No code changes; this step is just documentation.

---

## Self-review notes

**Spec coverage:** All six screens + Login + Settings + bottom nav + theme toggle + login stub + scoring + mock API + theme tokens + 13 component primitives are implemented in the tasks above.

**Skipped from spec, intentionally:** F1 driver standings podium hero (the F1 tab uses a flat list; podium hero only on the League sub-tab) — adding a podium for drivers would be cosmetic duplication and is not in the screen description.

**Open after execution:**
- Driver number population in `MockApiClient.driver()` (returns null permanentNumber). Real backend will populate.
- Real backend wiring smoke test (`USE_MOCK=false`) blocked on sub-project 1 deploy — call out in PR description.

