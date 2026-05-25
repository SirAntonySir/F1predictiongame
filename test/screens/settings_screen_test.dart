import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
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

  testWidgets('Settings toggles theme + signs out', (tester) async {
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
    GoRouter.of(tester.element(find.byType(Scaffold).first)).push('/settings');
    await tester.pumpAndSettle();
    expect(find.text('THEME'), findsOneWidget);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(theme.mode, ThemeMode.dark);

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(auth.isLoggedIn, false);
  });
}
