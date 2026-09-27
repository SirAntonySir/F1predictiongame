import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:predictiongame/api/api_client.dart';
import 'package:predictiongame/api/models/event.dart';
import 'package:predictiongame/api/models/leaderboard_row.dart';
import 'package:predictiongame/api/models/pick.dart';
import 'package:predictiongame/api/models/prediction_view.dart';
import 'package:predictiongame/api/models/reference_laps.dart';
import 'package:predictiongame/api/models/session.dart';
import 'package:predictiongame/api/models/session_leaderboard_row.dart';
import 'package:predictiongame/api/models/session_result.dart';
import 'package:predictiongame/api/models/user.dart';
import 'package:predictiongame/api/models/user_league.dart';
import 'package:predictiongame/avatar/avatar_config.dart';
import 'package:predictiongame/components/bottom_nav.dart';
import 'package:predictiongame/nav/router.dart';
import 'package:predictiongame/state/app_state.dart';
import 'package:predictiongame/state/auth_controller.dart';
import 'package:predictiongame/state/avatar_controller.dart';
import 'package:predictiongame/state/home_cache_controller.dart';
import 'package:predictiongame/state/league_controller.dart';
import 'package:predictiongame/state/live_session_controller.dart';
import 'package:predictiongame/state/notification_settings_controller.dart';
import 'package:predictiongame/state/predictions_controller.dart';
import 'package:predictiongame/state/preseason_controller.dart';
import 'package:predictiongame/state/theme_controller.dart';
import 'package:predictiongame/state/token_storage.dart';

final _now = DateTime.now();
final _quali = Session(
  id: 90,
  type: SessionType.qualifying,
  scheduledStart: _now.subtract(const Duration(days: 1)),
  scheduledEnd: _now.subtract(const Duration(hours: 23)),
  status: SessionStatus.finished,
);
final _race = Session(
  id: 91,
  type: SessionType.race,
  scheduledStart: _now.add(const Duration(hours: 2)),
  scheduledEnd: _now.add(const Duration(hours: 4)),
  status: SessionStatus.scheduled,
);
final _spain = Event(
  round: 9,
  name: 'Spanish Grand Prix',
  country: 'Spain',
  circuitName: 'Barcelona',
  hasSprint: false,
  sessions: [_quali, _race],
);
final _laterRace = Session(
  id: 92,
  type: SessionType.race,
  scheduledStart: _now.add(const Duration(days: 14)),
  scheduledEnd: _now.add(const Duration(days: 14, hours: 2)),
  status: SessionStatus.scheduled,
);
final _britain = Event(
  round: 10,
  name: 'British Grand Prix',
  country: 'UK',
  circuitName: 'Silverstone',
  hasSprint: false,
  sessions: [_laterRace],
);

const _lineup = [
  SessionResult(position: 1, driverCode: 'ANT', driverName: 'Kimi Antonelli', constructorId: 'mercedes', constructorName: 'Mercedes'),
  SessionResult(position: 2, driverCode: 'VER', driverName: 'Max Verstappen', constructorId: 'red_bull', constructorName: 'Red Bull'),
  SessionResult(position: 3, driverCode: 'NOR', driverName: 'Lando Norris', constructorId: 'mclaren', constructorName: 'McLaren'),
  SessionResult(position: 4, driverCode: 'RUS', driverName: 'George Russell', constructorId: 'mercedes', constructorName: 'Mercedes'),
  SessionResult(position: 5, driverCode: 'HAM', driverName: 'Lewis Hamilton', constructorId: 'ferrari', constructorName: 'Ferrari'),
];

class _FakeApi implements ApiClient {
  /// Only the predict screen hits this endpoint — counting its calls tells
  /// us whether the tab's State was recreated (a recreation reloads and
  /// bumps the counter).
  int referenceLapsCalls = 0;

  @override
  Future<List<Event>> events() async => [_spain, _britain];

  @override
  Future<Session> nextSession() async => _race;

  @override
  Future<List<SessionResult>> sessionResults(int id) async => _lineup;

  @override
  Future<PredictionView?> getMyPrediction(int sessionId) async =>
      sessionId == 91
          ? const PredictionView(
              sessionId: 91,
              picks: [
                Pick(position: 1, driverCode: 'ANT'),
                Pick(position: 2, driverCode: 'VER'),
                Pick(position: 3, driverCode: 'NOR'),
                Pick(position: 4, driverCode: 'RUS'),
                Pick(position: 5, driverCode: 'HAM'),
              ],
              updatedAt: null,
              isLocked: false,
            )
          : null;

  @override
  Future<ReferenceLapsResponse> sessionReferenceLaps(int id) async {
    referenceLapsCalls++;
    throw Exception('no laps yet');
  }

  @override
  Future<List<LeaderboardRow>> leagueLeaderboard(String leagueId, {int? season}) async => const [];

  @override
  Future<List<SessionLeaderboardRow>> leagueSessionBreakdown(String leagueId, {int? season}) async => const [];

  @override
  Future<String?> circuitSvg(String circuitId,
          {String detail = 'detailed',
          String variant = 'white',
          String? layout}) async =>
      null;

  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Widget _app(_FakeApi api, AuthController auth, GoRouter router) {
  final predictions = PredictionsController(api: api);
  return AppState(
    api: api,
    auth: auth,
    avatar: AvatarController(const AvatarConfig()),
    league: LeagueController(api: api),
    theme: ThemeController(ThemeMode.light),
    predictions: predictions,
    preseason: PreseasonController(api: api),
    notifications: NotificationSettingsController.forTesting(api: api),
    homeCache: HomeCacheController(api: api, auth: auth, predictions: predictions),
    live: LiveSessionController(api: api),
    child: MaterialApp.router(routerConfig: router),
  );
}

AuthController _auth(_FakeApi api) {
  final auth = AuthController(storage: InMemoryTokenStorage())..api = api;
  auth.applyTestState(
    user: User(
        id: 'u1',
        email: 'a@b.com',
        displayName: 'Anton',
        createdAt: DateTime.utc(2026, 1, 1)),
    token: 'tok',
    leagues: const [UserLeague(id: 'L', name: 'Eins', role: 'member')],
  );
  return auth;
}

/// The home hero runs a 1 Hz countdown timer, so pumpAndSettle never
/// settles — bounded pumps instead.
Future<void> _pumpABit(WidgetTester tester,
    {int frames = 8, Duration step = const Duration(milliseconds: 50)}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(step);
  }
}

Finder _navTab(String label) => find.descendant(
    of: find.byType(BottomNav), matching: find.text(label.toUpperCase()));

void main() {
  testWidgets('predict tab keeps its State across tab switches', (tester) async {
    final api = _FakeApi();
    final auth = _auth(api);
    await tester.pumpWidget(_app(api, auth, buildRouter(auth)));
    await _pumpABit(tester);

    await tester.tap(_navTab('Predict'));
    await _pumpABit(tester);
    expect(find.text('EDIT'), findsOneWidget);
    expect(api.referenceLapsCalls, 1);

    await tester.tap(_navTab('Calendar'));
    await _pumpABit(tester);
    expect(find.text('EDIT'), findsNothing); // offstage while on calendar

    await tester.tap(_navTab('Predict'));
    await tester.pump();
    // State was preserved: content is back within a single frame (a
    // recreated State would show the loading skeleton here) and the screen
    // did not reload its data.
    expect(find.text('EDIT'), findsOneWidget);
    expect(api.referenceLapsCalls, 1);
  });

  testWidgets('re-navigating with a new ?session= reloads in place',
      (tester) async {
    final api = _FakeApi();
    final auth = _auth(api);
    final router = buildRouter(auth);
    await tester.pumpWidget(_app(api, auth, router));
    await _pumpABit(tester);

    await tester.tap(_navTab('Predict'));
    await _pumpABit(tester);
    // Auto-found next pickable session → Spanish GP with saved picks.
    expect(find.text('Spanish Grand Prix'), findsOneWidget);
    expect(find.text('EDIT'), findsOneWidget);

    // Simulates a home ticket-stub / race-hero navigation while the predict
    // State is alive: same widget position, new sessionId param. The kept
    // State must reload for the new target, not keep showing Spain.
    router.go('/predict?session=92');
    await _pumpABit(tester);
    expect(find.text('British Grand Prix'), findsOneWidget);
    expect(find.text('Spanish Grand Prix'), findsNothing);
    // Session 92 has no saved prediction → opens in pick mode.
    expect(find.text('LOCK PICK'), findsOneWidget);
  });
}
