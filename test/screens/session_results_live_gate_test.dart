import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/api_client.dart';
import 'package:predictiongame/api/models/event.dart';
import 'package:predictiongame/api/models/live_snapshot.dart';
import 'package:predictiongame/api/models/member_prediction.dart';
import 'package:predictiongame/api/models/my_score.dart';
import 'package:predictiongame/api/models/pick.dart';
import 'package:predictiongame/api/models/prediction_view.dart';
import 'package:predictiongame/api/models/session.dart';
import 'package:predictiongame/api/models/session_result.dart';
import 'package:predictiongame/api/models/user.dart';
import 'package:predictiongame/api/models/user_league.dart';
import 'package:predictiongame/avatar/avatar_config.dart';
import 'package:predictiongame/screens/session_results_screen.dart';
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

/// A sprint that started 30 minutes ago and is still inside its scheduled
/// window — "live" by the clock, but the backend `/live` snapshot reports
/// `unavailable` (no OpenF1 session key). The regular REST path has everything:
/// the session is locked, so league members' picks are visible.
final _now = DateTime.now();
final _sprint = Session(
  id: 44,
  type: SessionType.sprint,
  scheduledStart: _now.subtract(const Duration(minutes: 30)),
  scheduledEnd: _now.add(const Duration(minutes: 30)),
  status: SessionStatus.scheduled,
);
final _event = Event(
  round: 9,
  name: 'British Grand Prix',
  country: 'UK',
  circuitName: 'Silverstone',
  hasSprint: true,
  sessions: [_sprint],
);

class _FakeApi implements ApiClient {
  @override
  Future<List<Event>> events() async => [_event];

  @override
  Future<List<SessionResult>> sessionResults(int id) async =>
      throw const NotFoundException('results not published');

  @override
  Future<PredictionView?> getMyPrediction(int sessionId) async =>
      PredictionView(
        sessionId: sessionId,
        picks: const [
          Pick(position: 1, driverCode: 'HAM'),
          Pick(position: 2, driverCode: 'ANT'),
          Pick(position: 3, driverCode: 'VER'),
        ],
        updatedAt: null,
        isLocked: true,
      );

  @override
  Future<List<MyScore>> myScores({int? season}) async => const [];

  @override
  Future<LeagueSessionPredictions> leagueSessionPredictions(
          String leagueId, int sessionId) async =>
      const LeagueSessionPredictions(
        sessionLocked: true,
        predictions: [
          MemberPrediction(
            userId: 'u2',
            displayName: 'Lukas',
            picks: [
              (position: 1, driverCode: 'VER'),
              (position: 2, driverCode: 'NOR'),
              (position: 3, driverCode: 'PIA'),
            ],
            pointsTotal: null,
          ),
        ],
      );

  @override
  Future<LiveSnapshot> sessionLive(int id, {String? leagueId}) async =>
      LiveSnapshot(
        sessionId: id,
        state: LiveState.unavailable,
        order: const [],
        myPointsTotal: null,
        league: const [],
      );

  @override
  Future<String?> circuitSvg(String circuitId,
          {String detail = 'detailed',
          String variant = 'white',
          String? layout}) async =>
      null;

  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  testWidgets(
      'clock-live session with an unavailable live snapshot falls back to the '
      'regular body and still shows LEAGUE PICKS', (tester) async {
    final api = _FakeApi();
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
    final live = LiveSessionController(api: api);
    // Make the controller consider the sprint live (clock-based), then feed it
    // the backend's `unavailable` snapshot — exactly the state during a running
    // session whose OpenF1 key hasn't resolved.
    live.update([_event], _now, autoPoll: false);
    await live.refreshOnce();
    expect(live.isLiveFor(44), isTrue);
    expect(live.snapshot?.state, LiveState.unavailable);

    await tester.pumpWidget(AppState(
      api: api,
      auth: auth,
      avatar: AvatarController(const AvatarConfig()),
      league: LeagueController(api: api),
      theme: ThemeController(ThemeMode.light),
      predictions: predictions,
      preseason: PreseasonController(api: api),
      notifications: NotificationSettingsController.forTesting(api: api),
      homeCache: HomeCacheController(api: api, auth: auth, predictions: predictions),
      live: live,
      child: const MaterialApp(
        home: SessionResultsScreen(round: 9, sessionId: 44),
      ),
    ));
    await tester.pumpAndSettle();

    // The empty live body must not win over the REST payload: the session has
    // started (locked), so league members' picks are visible.
    expect(find.text('LEAGUE PICKS'), findsOneWidget);
    expect(find.text('LUKAS'), findsOneWidget);
    // And no misleading LIVE badge with an empty order.
    expect(find.text('LIVE'), findsNothing);
  });
}
