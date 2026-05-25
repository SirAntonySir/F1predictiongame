import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/mock_api_client.dart';
import 'package:predictiongame/app.dart';
import 'package:predictiongame/state/auth_controller.dart';
import 'package:predictiongame/state/league_controller.dart';
import 'package:predictiongame/state/predictions_store.dart';
import 'package:predictiongame/state/theme_controller.dart';
import 'package:predictiongame/theme/colors.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Light theme uses the brand surface', (tester) async {
    final api = MockApiClient(bundle: rootBundle);
    final auth = await AuthController.load();
    final league = LeagueController(league: theBoxLeague);
    final theme = await ThemeController.load();
    final preds = await PredictionsStore.load();
    await tester.pumpWidget(F1PgApp(
      api: api,
      auth: auth,
      league: league,
      theme: theme,
      predictions: preds,
    ));
    final BuildContext ctx = tester.element(find.byType(Scaffold));
    expect(Theme.of(ctx).scaffoldBackgroundColor, LightPalette.surface);
  });

  testWidgets('App boots with all controllers in scope', (tester) async {
    final api = MockApiClient(bundle: rootBundle);
    final auth = await AuthController.load();
    final league = LeagueController(league: theBoxLeague);
    final theme = await ThemeController.load();
    final preds = await PredictionsStore.load();
    await tester.pumpWidget(F1PgApp(
      api: api,
      auth: auth,
      league: league,
      theme: theme,
      predictions: preds,
    ));
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
