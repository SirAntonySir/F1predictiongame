import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/api_client.dart';
import 'package:predictiongame/api/models/constructor.dart';
import 'package:predictiongame/api/models/driver.dart';
import 'package:predictiongame/api/models/event.dart';
import 'package:predictiongame/api/models/me_result.dart';
import 'package:predictiongame/api/models/pick.dart';
import 'package:predictiongame/api/models/prediction_view.dart';
import 'package:predictiongame/api/models/season.dart';
import 'package:predictiongame/api/models/session.dart';
import 'package:predictiongame/api/models/session_result.dart';
import 'package:predictiongame/api/models/standing.dart';
import 'package:predictiongame/api/models/upcoming_prediction.dart';
import 'package:predictiongame/screens/predict_screen.dart';
import 'package:predictiongame/state/app_state.dart';
import 'package:predictiongame/state/auth_controller.dart';
import 'package:predictiongame/state/league_controller.dart';
import 'package:predictiongame/state/predictions_controller.dart';
import 'package:predictiongame/state/preseason_store.dart';
import 'package:predictiongame/state/theme_controller.dart';
import 'package:predictiongame/state/token_storage.dart';

class _FakeApi implements ApiClient {
  List<UpcomingPrediction> upcoming = const [];
  PredictionView? prediction;
  Object? putError;
  PredictionView? putReply;
  List<SessionResult> results = const [];
  @override Future<List<UpcomingPrediction>> upcomingPredictions() async => upcoming;
  @override Future<PredictionView?> getMyPrediction(int s) async => prediction;
  @override Future<PredictionView>  putMyPrediction(int s, List<Pick> picks) async {
    if (putError != null) throw putError!;
    return putReply ?? PredictionView(sessionId: s, picks: picks, updatedAt: DateTime.utc(2026,5,1), isLocked: false);
  }
  @override Future<List<SessionResult>> sessionResults(int id) async => results;
  @override noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Widget _wrap({required _FakeApi api, required PredictionsController controller, required AuthController auth}) {
  return AppState(
    api: api,
    auth: auth,
    league: LeagueController(league: theBoxLeague),
    theme: ThemeController(ThemeMode.system),
    predictions: controller,
    preseason: PreseasonStore({}),
    child: const MaterialApp(home: PredictScreen()),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows "Nothing to predict" when upcoming is empty', (tester) async {
    final api = _FakeApi();
    final auth = AuthController(storage: InMemoryTokenStorage())..api = api;
    final c = PredictionsController(api: api);
    await tester.pumpWidget(_wrap(api: api, controller: c, auth: auth));
    await tester.pumpAndSettle();
    expect(find.textContaining('Nothing to predict'), findsOneWidget);
  });

  testWidgets('renders next session name', (tester) async {
    final api = _FakeApi()
      ..upcoming = [
        UpcomingPrediction(
          sessionId: 26, sessionType: SessionType.qualifying, eventId: 6, eventRound: 6,
          eventName: 'Monaco Grand Prix', eventCountry: 'Monaco', picksRequired: 2,
          locksAt: DateTime.utc(2026, 6, 6), isLocked: false, myPicks: null,
        ),
      ]
      ..prediction = const PredictionView(sessionId: 26, picks: [Pick(position: 1, driverCode: 'VER'), Pick(position: 2, driverCode: 'NOR')], updatedAt: null, isLocked: false);
    final auth = AuthController(storage: InMemoryTokenStorage())..api = api;
    final c = PredictionsController(api: api);
    await tester.pumpWidget(_wrap(api: api, controller: c, auth: auth));
    await tester.pumpAndSettle();
    expect(find.text('Monaco Grand Prix'), findsOneWidget);
  });

  testWidgets('save → ConflictException shows SnackBar', (tester) async {
    final api = _FakeApi()
      ..upcoming = [
        UpcomingPrediction(
          sessionId: 26, sessionType: SessionType.qualifying, eventId: 6, eventRound: 6,
          eventName: 'Monaco', eventCountry: 'MC', picksRequired: 2,
          locksAt: DateTime.utc(2026, 6, 6), isLocked: false, myPicks: null,
        ),
      ]
      ..prediction = const PredictionView(sessionId: 26, picks: [Pick(position: 1, driverCode: 'VER'), Pick(position: 2, driverCode: 'NOR')], updatedAt: null, isLocked: false)
      ..putError = const ConflictException('Predictions are locked');
    final auth = AuthController(storage: InMemoryTokenStorage())..api = api;
    final c = PredictionsController(api: api);
    await tester.pumpWidget(_wrap(api: api, controller: c, auth: auth));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('predict.save')));
    await tester.pumpAndSettle();
    expect(find.text('Predictions are locked'), findsOneWidget);
  });
}
