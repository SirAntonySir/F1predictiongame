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

  testWidgets('Standings League shows player names', (tester) async {
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/standings/league');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Lukas'), findsWidgets);
    expect(find.text('Simon'), findsWidgets);
  });

  testWidgets('F1 tab shows driver standings', (tester) async {
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/standings/f1');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('NOR'), findsWidgets);
  });

  testWidgets('Insights tab shows stat grid', (tester) async {
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/standings/insights');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('TOTAL POINTS'), findsOneWidget);
  });
}
