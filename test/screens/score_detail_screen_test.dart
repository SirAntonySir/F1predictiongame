import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/api_client.dart';
import 'package:predictiongame/api/models/my_score.dart';
import 'package:predictiongame/api/models/prediction_view.dart';
import 'package:predictiongame/api/models/score_breakdown.dart';
import 'package:predictiongame/api/models/session.dart';
import 'package:predictiongame/api/models/upcoming_prediction.dart';
import 'package:predictiongame/screens/score_detail_screen.dart';
import 'package:predictiongame/state/app_state.dart';
import 'package:predictiongame/state/auth_controller.dart';
import 'package:predictiongame/state/league_controller.dart';
import 'package:predictiongame/state/predictions_controller.dart';
import 'package:predictiongame/state/preseason_store.dart';
import 'package:predictiongame/state/theme_controller.dart';
import 'package:predictiongame/state/token_storage.dart';

class _FakeApi implements ApiClient {
  List<MyScore> scoresReply = const [];
  @override Future<List<MyScore>> myScores({int? season}) async => scoresReply;
  @override Future<PredictionView?> getMyPrediction(int s) async => null;
  @override Future<List<UpcomingPrediction>> upcomingPredictions() async => const [];
  @override noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

MyScore _ms({required int sid, required int pts, required ScoreBreakdown breakdown}) => MyScore(
      sessionId: sid,
      sessionType: SessionType.race,
      eventRound: 1,
      eventName: 'Australian Grand Prix',
      sessionScheduledStart: DateTime.utc(2026, 3, 8),
      pointsTotal: pts,
      breakdown: breakdown,
      computedAt: DateTime.utc(2026, 5, 26),
    );

Widget _wrap({required _FakeApi api, required PredictionsController controller}) {
  return AppState(
    api: api,
    auth: AuthController(storage: InMemoryTokenStorage())..api = api,
    league: LeagueController(league: theBoxLeague),
    theme: ThemeController(ThemeMode.system),
    predictions: controller,
    preseason: PreseasonStore({}),
    child: const MaterialApp(home: ScoreDetailScreen()),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('empty state when no scores', (tester) async {
    final api = _FakeApi();
    final c = PredictionsController(api: api);
    await tester.pumpWidget(_wrap(api: api, controller: c));
    await tester.pumpAndSettle();
    expect(find.textContaining('No scored sessions yet'), findsOneWidget);
  });

  testWidgets('renders MyScore with totals + breakdown when expanded', (tester) async {
    final api = _FakeApi()..scoresReply = [
      _ms(sid: 1, pts: 13, breakdown: const ScoreBreakdown(
        perPosition: [
          ScoreBreakdownPerPosition(position: 1, exact: true, wrongPos: false, points: 3),
          ScoreBreakdownPerPosition(position: 2, exact: false, wrongPos: true, points: 1),
        ],
        teamBonus: ScoreTeamBonus(applied: true, points: 2),
        rule: 'race-v1',
      )),
    ];
    final c = PredictionsController(api: api);
    await tester.pumpWidget(_wrap(api: api, controller: c));
    await tester.pumpAndSettle();
    expect(find.text('Australian Grand Prix race'), findsOneWidget);
    expect(find.text('13 pts'), findsOneWidget);
    await tester.tap(find.text('Australian Grand Prix race'));
    await tester.pumpAndSettle();
    expect(find.textContaining('P1'), findsOneWidget);
    expect(find.textContaining('Team bonus'), findsOneWidget);
    expect(find.textContaining('race-v1'), findsOneWidget);
  });
}
