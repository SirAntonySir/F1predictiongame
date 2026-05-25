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
  setUp(() => SharedPreferences.setMockInitialValues({'current_user_id': 'anton'}));

  testWidgets('Shell shows bottom nav with 4 items when logged in', (tester) async {
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
    expect(find.text('HOME'), findsOneWidget);
    expect(find.text('CALENDAR'), findsOneWidget);
    expect(find.text('PREDICT'), findsOneWidget);
    expect(find.text('STANDINGS'), findsOneWidget);
  });
}
