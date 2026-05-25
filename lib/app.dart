import 'package:flutter/material.dart';
import 'api/api_client.dart';
import 'state/app_state.dart';
import 'state/auth_controller.dart';
import 'state/league_controller.dart';
import 'state/predictions_store.dart';
import 'state/theme_controller.dart';
import 'theme/app_theme.dart';

class F1PgApp extends StatelessWidget {
  final ApiClient api;
  final AuthController auth;
  final LeagueController league;
  final ThemeController theme;
  final PredictionsStore predictions;

  const F1PgApp({
    super.key,
    required this.api,
    required this.auth,
    required this.league,
    required this.theme,
    required this.predictions,
  });

  @override
  Widget build(BuildContext context) {
    return AppState(
      api: api,
      auth: auth,
      league: league,
      theme: theme,
      predictions: predictions,
      child: ListenableBuilder(
        listenable: theme,
        builder: (_, __) => MaterialApp(
          title: 'F1PG',
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: theme.mode,
          home: const Scaffold(body: Center(child: Text('F1PG'))),
        ),
      ),
    );
  }
}
