import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'api/api_client.dart';
import 'api/http_api_client.dart';
import 'api/mock_api_client.dart';
import 'app.dart';
import 'state/auth_controller.dart';
import 'state/league_controller.dart';
import 'state/predictions_store.dart';
import 'state/theme_controller.dart';

const _useMock = bool.fromEnvironment('USE_MOCK', defaultValue: true);
const _apiUrl = String.fromEnvironment('API_URL', defaultValue: '');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final ApiClient api = _useMock
      ? MockApiClient(bundle: rootBundle)
      : HttpApiClient(baseUrl: _apiUrl, client: http.Client());
  final auth = await AuthController.load();
  final theme = await ThemeController.load();
  final preds = await PredictionsStore.load();
  runApp(F1PgApp(
    api: api,
    auth: auth,
    league: LeagueController(league: theBoxLeague),
    theme: theme,
    predictions: preds,
  ));
}
