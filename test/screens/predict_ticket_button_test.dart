import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/api_client.dart';
import 'package:predictiongame/api/models/event.dart';
import 'package:predictiongame/api/models/pick.dart';
import 'package:predictiongame/api/models/prediction_view.dart';
import 'package:predictiongame/api/models/session.dart';
import 'package:predictiongame/api/models/session_result.dart';
import 'package:predictiongame/api/models/user.dart';
import 'package:predictiongame/api/models/user_league.dart';
import 'package:predictiongame/avatar/avatar_config.dart';
import 'package:predictiongame/components/ticket/pick_ticket.dart';
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
// Finished same-weekend quali (reference session for the race lineup) plus
// the future race being predicted.
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
final _event = Event(
  round: 9,
  name: 'Spanish Grand Prix',
  country: 'Spain',
  circuitName: 'Barcelona',
  hasSprint: false,
  sessions: [_quali, _race],
);

const _lineup = [
  SessionResult(position: 1, driverCode: 'ANT', driverName: 'Kimi Antonelli', constructorId: 'mercedes', constructorName: 'Mercedes'),
  SessionResult(position: 2, driverCode: 'VER', driverName: 'Max Verstappen', constructorId: 'red_bull', constructorName: 'Red Bull'),
  SessionResult(position: 3, driverCode: 'NOR', driverName: 'Lando Norris', constructorId: 'mclaren', constructorName: 'McLaren'),
  SessionResult(position: 4, driverCode: 'RUS', driverName: 'George Russell', constructorId: 'mercedes', constructorName: 'Mercedes'),
  SessionResult(position: 5, driverCode: 'HAM', driverName: 'Lewis Hamilton', constructorId: 'ferrari', constructorName: 'Ferrari'),
];

class _FakeApi implements ApiClient {
  PredictionView? myPrediction;

  @override
  Future<List<Event>> events() async => [_event];

  @override
  Future<List<SessionResult>> sessionResults(int id) async => _lineup;

  @override
  Future<PredictionView?> getMyPrediction(int sessionId) async => myPrediction;

  @override
  Future<String?> circuitSvg(String circuitId,
          {String detail = 'detailed',
          String variant = 'white',
          String? layout}) async =>
      null;

  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Widget _app(_FakeApi api) {
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
    child: const MaterialApp(
      home: PredictScreen(sessionId: 91),
    ),
  );
}

void main() {
  testWidgets('saved pick shows ticket button; tapping opens the pick ticket',
      (tester) async {
    final api = _FakeApi()
      ..myPrediction = const PredictionView(
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
      );
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    expect(find.text('EDIT'), findsOneWidget);
    final ticketButton = find.byKey(const Key('predict.viewTicket'));
    expect(ticketButton, findsOneWidget);

    await tester.tap(ticketButton);
    await tester.pumpAndSettle();

    expect(find.byType(PickTicket), findsOneWidget);
    expect(find.text('DRAFT'), findsOneWidget);
  });

  testWidgets('no saved pick → editing mode without a ticket button',
      (tester) async {
    final api = _FakeApi(); // myPrediction stays null
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    expect(find.text('LOCK PICK'), findsOneWidget);
    expect(find.byKey(const Key('predict.viewTicket')), findsNothing);
  });
}
