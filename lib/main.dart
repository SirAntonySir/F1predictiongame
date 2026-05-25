import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'api/http_api_client.dart';
import 'app.dart';
import 'state/auth_controller.dart';
import 'state/league_controller.dart';
import 'state/predictions_store.dart';
import 'state/preseason_store.dart';
import 'state/theme_controller.dart';

const _apiUrl =
    String.fromEnvironment('API_URL', defaultValue: 'http://localhost:3000');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final api = HttpApiClient(baseUrl: _apiUrl, client: http.Client());
  final auth = await AuthController.load();
  final theme = await ThemeController.load();
  final preds = await PredictionsStore.load();
  final preseason = await PreseasonStore.load();
  runApp(F1PgApp(
    api: api,
    auth: auth,
    league: LeagueController(league: theBoxLeague),
    theme: theme,
    predictions: preds,
    preseason: preseason,
  ));
}
