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

const _fivePicks = [
  Pick(position: 1, driverCode: 'ANT'),
  Pick(position: 2, driverCode: 'VER'),
  Pick(position: 3, driverCode: 'NOR'),
  Pick(position: 4, driverCode: 'RUS'),
  Pick(position: 5, driverCode: 'HAM'),
];

class _FakeApi implements ApiClient {
  _FakeApi(this.race);
  final Session race;
  PredictionView? myPrediction;
  UpcomingBundle bundle = const UpcomingBundle(upcoming: [], jokersRemaining: 3);

  @override
  Future<List<Event>> events() async => [_event(race)];

  @override
  Future<List<SessionResult>> sessionResults(int id) async => _lineup;

  @override
  Future<PredictionView?> getMyPrediction(int sessionId) async => myPrediction;

  @override
  Future<UpcomingBundle> upcomingPredictions() async => bundle;

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
  testWidgets('joker-filled locked race shows the joker badge', (tester) async {
    final api = _FakeApi(_race(locked: true))
      ..myPrediction = const PredictionView(
        sessionId: 91,
        picks: _fivePicks,
        updatedAt: null,
        isLocked: true,
        isJoker: true,
      );
    await tester.pumpWidget(_app(api, PredictionsController(api: api)));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('predict.jokerBadge')), findsOneWidget);
    expect(find.text('JOKER'), findsOneWidget);
  });

  testWidgets('open race shows remaining jokers, no badge', (tester) async {
    final api = _FakeApi(_race(locked: false))
      ..bundle = const UpcomingBundle(upcoming: [], jokersRemaining: 2);
    final predictions = PredictionsController(api: api);
    await predictions.refreshUpcoming();

    await tester.pumpWidget(_app(api, predictions));
    await tester.pumpAndSettle();

    expect(find.text('JOKERS 2/3'), findsOneWidget);
    expect(find.byKey(const Key('predict.jokerBadge')), findsNothing);
  });

  testWidgets('own locked pick shows no joker badge', (tester) async {
    final api = _FakeApi(_race(locked: true))
      ..myPrediction = const PredictionView(
        sessionId: 91,
        picks: _fivePicks,
        updatedAt: null,
        isLocked: true,
      );
    await tester.pumpWidget(_app(api, PredictionsController(api: api)));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('predict.jokerBadge')), findsNothing);
  });
}
