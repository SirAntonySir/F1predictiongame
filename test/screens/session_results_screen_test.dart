import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:predictiongame/api/mock_api_client.dart';
import 'package:predictiongame/app.dart';
import 'package:predictiongame/state/auth_controller.dart';
import 'package:predictiongame/state/league_controller.dart';
import 'package:predictiongame/state/predictions_store.dart';
import 'package:predictiongame/state/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({'current_user_id': 'anton'}));

  testWidgets('Session results shows score banner + classification',
      (tester) async {
    final api = MockApiClient(bundle: rootBundle);
    final auth = await AuthController.load();
    final theme = await ThemeController.load();
    final preds = await PredictionsStore.load();
    await tester.pumpWidget(F1PgApp(
      api: api, auth: auth,
      league: LeagueController(league: theBoxLeague),
      theme: theme, predictions: preds,
    ));
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.byType(Scaffold).first)).push('/race/7/42');
    await tester.pumpAndSettle();
    expect(find.text('NOR'), findsWidgets);
    expect(find.textContaining('Your score'), findsOneWidget);
  });
}
