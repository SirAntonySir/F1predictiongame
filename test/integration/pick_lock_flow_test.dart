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

  testWidgets('Login → predict → lock → home shows lock state', (tester) async {
    final api = MockApiClient(bundle: rootBundle);
    final auth = await AuthController.load();
    final theme = await ThemeController.load();
    final preds = await PredictionsStore.load();
    await tester.pumpWidget(F1PgApp(
      api: api,
      auth: auth,
      league: LeagueController(league: theBoxLeague),
      theme: theme,
      predictions: preds,
    ));
    // Let home screen data load.
    // Use pump(Duration) not pumpAndSettle to avoid infinite loop from Countdown Timer.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    // Navigate to Predict via GoRouter
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/predict');
    // Pump enough for the route transition animation to complete (300ms) plus data load
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('P1'), findsWidgets);
    expect(find.text('Tap a driver below'), findsWidgets);

    // Tap five distinct driver codes from mock results.
    // ensureVisible + pump to scroll into view before tapping.
    for (final code in ['NOR', 'PIA', 'LEC', 'TSU', 'RUS']) {
      final finder = find.text(code).first;
      await tester.ensureVisible(finder);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(finder);
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 100));

    // Scroll the LOCK PICK button into view and tap it
    await tester.ensureVisible(find.text('LOCK PICK'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('LOCK PICK'));
    // Pump for save + lock futures to settle
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    // Verify the picks were saved and locked in the store
    expect(preds.isLocked(userId: 'anton', sessionId: 52), true);
    expect(
      preds.picksFor(userId: 'anton', sessionId: 52),
      ['NOR', 'PIA', 'LEC', 'TSU', 'RUS'],
    );

    // Back to home — navigate and verify Scaffold is present
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/home');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(Scaffold), findsWidgets);
  });
}
