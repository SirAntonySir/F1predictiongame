import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/api_client.dart';
import 'package:predictiongame/api/models/event.dart';
import 'package:predictiongame/api/models/pick.dart';
import 'package:predictiongame/api/models/prediction_view.dart';
import 'package:predictiongame/api/models/session.dart';
import 'package:predictiongame/api/models/session_result.dart';
import 'package:predictiongame/api/models/upcoming_prediction.dart';
import 'package:predictiongame/api/models/user.dart';
import 'package:predictiongame/api/models/user_league.dart';
import 'package:predictiongame/avatar/avatar_config.dart';
import 'package:predictiongame/screens/predict_screen.dart';
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

Session _race({required bool locked}) => Session(
      id: 91,
      type: SessionType.race,
      scheduledStart: locked
          ? _now.subtract(const Duration(hours: 2))
          : _now.add(const Duration(hours: 2)),
      scheduledEnd: locked
          ? _now.subtract(const Duration(hours: 0))
          : _now.add(const Duration(hours: 4)),
      status: SessionStatus.scheduled,
    );

Event _event(Session race) => Event(
      round: 9,
      name: 'Spanish Grand Prix',
      country: 'Spain',
      circuitName: 'Barcelona',
      hasSprint: false,
      sessions: [_quali, race],
    );

const _lineup = [
  SessionResult(position: 1, driverCode: 'ANT', driverName: 'Kimi Antonelli', constructorId: 'mercedes', constructorName: 'Mercedes'),
  SessionResult(position: 2, driverCode: 'VER', driverName: 'Max Verstappen', constructorId: 'red_bull', constructorName: 'Red Bull'),
  SessionResult(position: 3, driverCode: 'NOR', driverName: 'Lando Norris', constructorId: 'mclaren', constructorName: 'McLaren'),
  SessionResult(position: 4, driverCode: 'RUS', driverName: 'George Russell', constructorId: 'mercedes', constructorName: 'Mercedes'),
  SessionResult(position: 5, driverCode: 'HAM', driverName: 'Lewis Hamilton', constructorId: 'ferrari', constructorName: 'Ferrari'),
];

class _FakeApi implements ApiClient {
  _FakeApi(this.race);
  final Session race;
  PredictionView? myPrediction;
  final puts = <List<Pick>>[];
  final deleted = <int>[];

  @override
  Future<List<Event>> events() async => [_event(race)];

  @override
  Future<List<SessionResult>> sessionResults(int id) async => _lineup;

  @override
  Future<PredictionView?> getMyPrediction(int sessionId) async => myPrediction;

  @override
  Future<PredictionView> putMyPrediction(int sessionId, List<Pick> picks) async {
    puts.add(picks);
    return myPrediction = PredictionView(
        sessionId: sessionId, picks: picks, updatedAt: null, isLocked: false);
  }

  @override
  Future<void> deleteMyPrediction(int sessionId) async {
    deleted.add(sessionId);
    myPrediction = null;
  }

  @override
  Future<UpcomingBundle> upcomingPredictions() async =>
      const UpcomingBundle(upcoming: [], jokersRemaining: 3);

  @override
  Future<String?> circuitSvg(String circuitId,
          {String detail = 'detailed',
          String variant = 'white',
          String? layout}) async =>
      null;

  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Widget _app(_FakeApi api, PredictionsController predictions) {
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
    child: const MaterialApp(
      home: PredictScreen(sessionId: 91),
    ),
  );
}

void main() {
  testWidgets(
      'clearing every saved pick deletes the prediction instead of saving an '
      'empty one (which would block the joker)', (tester) async {
    final api = _FakeApi(_race(locked: false))
      ..myPrediction = const PredictionView(
        sessionId: 91,
        picks: [Pick(position: 1, driverCode: 'ANT')],
        updatedAt: null,
        isLocked: false,
      );
    await tester.pumpWidget(_app(api, PredictionsController(api: api)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('EDIT'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close)); // clear P1
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('predict-action')));
    await tester.pumpAndSettle();

    expect(api.puts, isEmpty);
    expect(api.deleted, [91]);
    // Still open for picking — not stuck on a LOCKED bar.
    expect(find.text('LOCKED'), findsNothing);
    await tester.pump(const Duration(seconds: 3)); // let the toast time out
  });

  testWidgets('with nothing saved and nothing picked there is nothing to save',
      (tester) async {
    final api = _FakeApi(_race(locked: false));
    await tester.pumpWidget(_app(api, PredictionsController(api: api)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('predict-action')));
    await tester.pumpAndSettle();

    expect(api.puts, isEmpty);
    expect(api.deleted, isEmpty);
  });

  testWidgets('saving part of a race set asks first, then saves', (tester) async {
    final api = _FakeApi(_race(locked: false));
    await tester.pumpWidget(_app(api, PredictionsController(api: api)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('ANT').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('predict-action')));
    await tester.pumpAndSettle();

    expect(find.text('Save 1 of 5 picks?'), findsOneWidget);
    expect(api.puts, isEmpty);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(api.puts.single.map((p) => p.driverCode), ['ANT']);
    await tester.pump(const Duration(seconds: 3)); // let the toast time out
  });
}
