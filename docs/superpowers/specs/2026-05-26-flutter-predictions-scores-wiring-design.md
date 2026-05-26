# Flutter Predictions + Scores Wiring — Design

**Date:** 2026-05-26
**Status:** Draft (pending user review)
**Predecessor:** [2026-05-26 Flutter auth wiring](2026-05-26-flutter-auth-wiring-design.md)
**Companion to:** the post-merge state on `main` (Tippspiel Excel import + scoring engine + leagues)

## Context

The Flutter app currently keeps prediction state in a `PredictionsStore` backed by `SharedPreferences`, keyed by `(userId, sessionId)` with a client-side `lockedAt` flag. There is no connection to the backend's `/api/sessions/:id/my-prediction` family of endpoints, and the app never displays computed scores.

This sub-project follows the auth wiring spec (which provides bearer-attached `HttpApiClient` and a logged-in `currentUser`). It wires the existing `PredictScreen` to the backend write/read path, replaces the local store with a small in-memory controller, and adds a new score-detail screen so we can validate the scoring engine output against the Excel comparison table.

## Goal

After login, the user lands on the home screen, opens the predict screen, sees their server-stored picks (or makes new ones) for the next upcoming session, and can drill into a new "My Scores" screen that lists per-session points with the full scoring breakdown (per-position exact/wrongPos/0, team bonus, rule version).

For Anton's validation use-case: log in as `anton@tippspiel.test`, open My Scores, see Australia Race = 15 pts with the breakdown, compare against the terminal table from `npm run import:tippspiel` (Excel said 12, App says 15, Δ +3) — then drill into the breakdown to see *why* the App gave more.

## Decisions

| # | Decision | Rationale |
|---|---|---|
| D1 | **Drop `PredictionsStore` entirely** | It is keyed by fake user ids from the demo era; nothing in it would survive the auth-spec's D5 wipe. Replacement is in-memory only. |
| D2 | **In-memory controller, no disk cache** | Backend is fast (local Postgres). One round-trip per screen open is cheaper than reasoning about cache invalidation. |
| D3 | **Server is source of truth for lock** | `isLocked` comes from backend `PredictionView`; client uses it to disable the Save button. `ConflictException` from race condition handled gracefully. |
| D4 | **`getMyPrediction` returns `null` for 404** | "No prediction yet" is a normal state, not an error. Keeps callers from needing try/catch around the common case. |
| D5 | **Score breakdown rendered verbatim from backend JSON** | No client-side scoring logic; the whole point is to validate the engine. Adding parallel client logic would defeat the purpose. |
| D6 | **Out of scope:** other players' picks after lock, league leaderboard wiring, preseason wiring | Each is a follow-up. This spec ends when Anton can see his own picks and his own scores. |

## Architecture

### Layered shape

```
lib/
  api/
    api_client.dart              ← + 5 new methods (predictions + scores)
    models/
      pick.dart                  ← NEW
      prediction_view.dart       ← NEW
      upcoming_prediction.dart   ← NEW
      score_breakdown.dart       ← NEW (Score + Breakdown + PerPosition + TeamBonus)
      my_score.dart              ← NEW
    http_api_client.dart         ← + new methods, JSON parsing
  state/
    predictions_controller.dart  ← NEW (replaces PredictionsStore)
    predictions_store.dart       ← DELETED
    app_state.dart               ← rewires AppState.predictions to PredictionsController
  screens/
    predict_screen.dart          ← rewrite data path (no PredictionsStore)
    score_detail_screen.dart     ← NEW
    home_screen.dart             ← edits: use upcomingPredictions[0] for hero
  nav/
    router.dart                  ← + /scores route
  domain/
    prediction.dart              ← DELETED if only PredictionsStore consumed it; keep PredictionEntry only if other code needs it
```

### `PredictionsController`

```dart
class PredictionsController extends ChangeNotifier {
  PredictionsController({required this.api});
  final ApiClient api;

  final Map<int, PredictionView> _byId = {};
  final Map<int, MyScore> _scoresById = {};
  List<UpcomingPrediction> _upcoming = const [];

  PredictionView? prediction(int sessionId) => _byId[sessionId];
  MyScore?        score(int sessionId)      => _scoresById[sessionId];
  List<UpcomingPrediction> get upcoming     => _upcoming;

  Future<void> refreshUpcoming();                                   // GET /api/predictions/upcoming
  Future<PredictionView?> fetchPrediction(int sessionId);          // GET; cached on success
  Future<PredictionView>  savePrediction(int sessionId, List<Pick> picks); // PUT; cached
  Future<void> refreshScores({int? season});                        // GET /api/users/me/scores; replaces _scoresById
  void clear();                                                     // called by AuthController on logout/invalidate
}
```

`clear()` is invoked from `AuthController.invalidate()` and `logout()` to drop per-user state on auth changes. (The auth spec already mentions wiping `predictions_v1` — that's the old store; the controller wipe is the new equivalent.)

### `ApiClient` additions

```dart
Future<PredictionView?>          getMyPrediction(int sessionId);
Future<PredictionView>           putMyPrediction(int sessionId, List<Pick> picks);
Future<void>                     deleteMyPrediction(int sessionId);
Future<List<UpcomingPrediction>> upcomingPredictions();
Future<List<MyScore>>            myScores({int? season});
```

### DTO models

```dart
// pick.dart
class Pick {
  final int position;
  final String driverCode;
  Pick({required this.position, required this.driverCode});
  factory Pick.fromJson(Map<String, dynamic> j) => Pick(
    position: j['position'] as int,
    driverCode: j['driverCode'] as String,
  );
  Map<String, dynamic> toJson() => {'position': position, 'driverCode': driverCode};
}

// prediction_view.dart
class PredictionView {
  final int sessionId;
  final List<Pick> picks;
  final DateTime? updatedAt;
  final bool isLocked;
  factory PredictionView.fromJson(Map<String, dynamic> j) => PredictionView(
    sessionId: j['sessionId'] as int,
    picks: (j['picks'] as List).map((p) => Pick.fromJson(p)).toList(),
    updatedAt: j['updatedAt'] != null ? DateTime.parse(j['updatedAt']) : null,
    isLocked: j['isLocked'] as bool,
  );
  // ctor + named...
}

// upcoming_prediction.dart
class UpcomingPrediction {
  final int sessionId;
  final SessionType sessionType;
  final int eventId;
  final int eventRound;
  final String eventName;
  final String eventCountry;
  final int picksRequired;
  final DateTime locksAt;
  final bool isLocked;
  final List<Pick>? myPicks;
  factory UpcomingPrediction.fromJson(Map<String, dynamic> j) { /* ... */ }
}

// score_breakdown.dart
class ScoreBreakdownPerPosition {
  final int position;
  final bool exact;
  final bool wrongPos;
  final int points;
}
class ScoreTeamBonus {
  final bool applied;
  final int points;
}
class ScoreBreakdown {
  final List<ScoreBreakdownPerPosition> perPosition;
  final ScoreTeamBonus teamBonus;
  final String rule;  // e.g. "race-v1"
}

// my_score.dart
class MyScore {
  final int sessionId;
  final SessionType sessionType;
  final int eventRound;
  final String eventName;
  final DateTime sessionScheduledStart;
  final int pointsTotal;
  final ScoreBreakdown breakdown;
  final DateTime computedAt;
}
```

### HTTP wire details

| Endpoint | Method | Body | Maps to |
|---|---|---|---|
| `/api/sessions/:id/my-prediction` | PUT | `{ "picks": [{"position": N, "driverCode": "VER"}] }` | `PredictionView` |
| `/api/sessions/:id/my-prediction` | GET | — | `PredictionView` or `null` (404 = no prediction) |
| `/api/sessions/:id/my-prediction` | DELETE | — | void |
| `/api/predictions/upcoming` | GET | — | `List<UpcomingPrediction>` |
| `/api/users/me/scores?season=YYYY` | GET | — | `List<MyScore>` |

Backend response shape for `GET /api/users/me/scores` is `{ scores: [...], season: N }` — client reads `.scores`. Similarly for `/predictions/upcoming` → `.upcoming`. Single-prediction endpoints return `{ prediction: {...} }` → client unwraps.

### Error handling

Reuses the auth spec's exception hierarchy (`UnauthorizedException`, `ConflictException`, `ValidationException`, `NotFoundException`).

- `getMyPrediction` catches `NotFoundException` and returns `null`. All other exceptions propagate.
- `putMyPrediction` propagates everything. The screen catches `ConflictException`/`ValidationException` and shows a SnackBar with the backend `message`.
- `upcomingPredictions` and `myScores` propagate `UnauthorizedException` (the global 401 hook handles it).

## Screen specs

### `PredictScreen` (rewrite of data path)

| Behavior | Old | New |
|---|---|---|
| Find next session | iterate events, pick earliest scheduled non-FP | `controller.refreshUpcoming()`, take `upcoming.firstWhere(!isLocked)` |
| Load existing picks | `predictions.picksFor(...)` from SharedPreferences | `controller.fetchPrediction(sessionId)` → `PredictionView.picks` (or empty) |
| Driver lineup | from last finished session results | unchanged — `scope.api.sessionResults(lastFinishedId)` |
| Save | `predictions.save(...)` then `lock(...)` | `controller.savePrediction(sessionId, picks)` |
| Lock indicator | `predictions.isLocked(...)` (client-only) | `predictionView.isLocked` (server-derived) |
| Save error | StateError thrown to user as SnackBar | `ConflictException` → "Predictions are locked"; `ValidationException` → backend message |

The screen UI (driver tiles, slots, layout) is untouched. Only the data calls change.

### `ScoreDetailScreen` (new, route `/scores`)

```
Scaffold
  AppBar: "My Scores"
  Body: RefreshIndicator + ListView builder over MyScore[]
    Item: ExpansionTile
      title: "{eventName} {sessionTypeLabel}" + trailing "{pointsTotal} pts"
      subtitle: DateFormat.yMd(scheduledStart)
      children (expanded):
        - For each perPosition entry:
            "P{position}  {pickedDriverCode} → {exact ? 'exact' : wrongPos ? 'wrongPos' : 'miss'}  +{points}"
        - If teamBonus.applied:
            "Team bonus  +{teamBonus.points}"
        - Footer: "Rule: {rule}"
```

The picked driver code comes from joining `PredictionView` (cached after a `fetchPrediction` from the breakdown click) with the breakdown row. If not cached, show position-only. (Cheap optimization — kick off `fetchPrediction(sessionId)` when expansion opens.)

Empty state: "No scored sessions yet. Once the next race finishes, your scores will appear here."

### `HomeScreen` (edit)

`_noNextHero` / `_hero` logic switches from `controller.nextSession` (current) to `controller.upcoming.firstWhereOrNull(!isLocked)`. If `myPicks != null`, the hero gets a green dot + "Pick locked in"; if null, "Tap to predict". Tap routes to `/predict` regardless (existing behavior).

Empty state ("Season's done — or the schedule hasn't been published"): triggered when `upcoming.isEmpty`.

### Settings — no change beyond what auth spec already adds.

## Data flow

### App launch (cold), assuming already-logged-in

```
auth.bootstrap() succeeds → user + leagues populated
PredictionsController is constructed with api reference
no eager loading; controller is empty until a screen requests
```

### Open Predict screen

```
PredictScreen.didChangeDependencies →
  controller.refreshUpcoming()              // GET /api/predictions/upcoming
  pick first non-locked → sessionId = N
  controller.fetchPrediction(N)             // GET /api/sessions/N/my-prediction
    → cached
  scope.api.sessionResults(lastFinishedId)  // driver lineup
```

### Submit picks

```
user taps Save →
  controller.savePrediction(N, picks)       // PUT /api/sessions/N/my-prediction
    → cached
  SnackBar "Pick saved"
  on ConflictException → SnackBar "Predictions are locked"
  on ValidationException → SnackBar with message
```

### Open Scores screen

```
ScoreDetailScreen.initState →
  controller.refreshScores()                // GET /api/users/me/scores
ExpansionTile expands →
  if controller.prediction(sid) == null:
    controller.fetchPrediction(sid)         // for the picked driver labels
```

### Logout / 401

```
AuthController.invalidate()/logout() →
  predictionsController.clear()
  notifyListeners propagates to widgets
  GoRouter sends user to /login
```

## Testing

| Layer | Test | Notes |
|---|---|---|
| unit | `Pick.fromJson` round-trip | |
| unit | `PredictionView.fromJson` with/without updatedAt | |
| unit | `UpcomingPrediction.fromJson` with/without myPicks | null vs present |
| unit | `ScoreBreakdown.fromJson` full round-trip incl. teamBonus | |
| unit | `MyScore.fromJson` round-trip | |
| unit | `HttpApiClient.getMyPrediction` 200 → PredictionView | MockClient |
| unit | `HttpApiClient.getMyPrediction` 404 → returns null | |
| unit | `HttpApiClient.putMyPrediction` 200 + 409 | |
| unit | `HttpApiClient.putMyPrediction` 422 → ValidationException with backend message | |
| unit | `HttpApiClient.upcomingPredictions` 200 → list | |
| unit | `HttpApiClient.myScores` 200 → list, season query attached | |
| unit | `PredictionsController.fetchPrediction` caches result | one network call on second access |
| unit | `PredictionsController.savePrediction` updates cache | |
| unit | `PredictionsController.clear` empties everything | |
| widget | `PredictScreen` renders next session from controller | with fake controller |
| widget | `PredictScreen` Save calls savePrediction | |
| widget | `PredictScreen` ConflictException shows SnackBar | |
| widget | `ScoreDetailScreen` renders MyScore list with breakdown | |
| widget | `ScoreDetailScreen` empty state | |

Existing `predictions_store_test.dart` is deleted (store gone). `controllers_test.dart` updated to reference the new controller if it touched the old store.

## Out of Scope

Explicit follow-ups:
- **Other players' picks after lock** — `GET /api/sessions/:id/predictions`. Useful for validation Spieler-für-Spieler.
- **League leaderboard wiring** — `GET /api/leagues/:id/leaderboard` + sessions breakdown.
- **Preseason wiring** — `/api/preseason/*` endpoints.
- **Live polling** — manual pull-to-refresh only; no WebSocket / SSE.

## Risks & open questions

| # | Risk | Mitigation |
|---|---|---|
| R1 | `PredictScreen` driver lineup fetch (`sessionResults(lastFinishedId)`) is separate from the new flow; could fail with `NotFoundException` and leave the slots empty | Existing try/catch already handles `NotFoundException` → empty lineup. Keep as-is. |
| R2 | `myScores` returns all scores in one shot; could be many across 22 events × multiple sessions | 22×3 ≈ 66 scores max for a full season. Trivial payload. |
| R3 | Server lock and client clock could disagree by a few seconds | Server is authoritative; client merely renders flag. Worst case: user taps Save right at lock boundary, gets 409. We show SnackBar. |
| R4 | Stale cache after backend rescore (e.g., admin re-imports tippspiel) | `RefreshIndicator` on ScoreDetailScreen calls `refreshScores`. No automatic invalidation; user pulls. |
| R5 | `PredictionsController.clear` not called on every auth event | Wire it inside `AuthController.invalidate` AND `logout`; verified via tests. |
