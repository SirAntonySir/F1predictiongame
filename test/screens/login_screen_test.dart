import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/mock_api_client.dart';
import 'package:predictiongame/app.dart';
import 'package:predictiongame/state/auth_controller.dart';
import 'package:predictiongame/state/league_controller.dart';
import 'package:predictiongame/state/predictions_store.dart';
import 'package:predictiongame/state/preseason_store.dart';
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
    final preseason = await PreseasonStore.load();
    await tester.pumpWidget(F1PgApp(
      api: api, auth: auth,
      league: LeagueController(league: theBoxLeague),
      theme: theme, predictions: preds,
      preseason: preseason,
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
