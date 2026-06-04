import 'package:flutter/widgets.dart';
import '../api/api_client.dart';
import 'auth_controller.dart';
import 'home_cache_controller.dart';
import 'league_controller.dart';
import 'notification_settings_controller.dart';
import 'predictions_controller.dart';
import 'preseason_controller.dart';
import 'theme_controller.dart';

class AppState extends StatefulWidget {
  final ApiClient api;
  final AuthController auth;
  final LeagueController league;
  final ThemeController theme;
  final PredictionsController predictions;
  final PreseasonController preseason;
  final NotificationSettingsController notifications;
  final HomeCacheController homeCache;
  final Widget child;

  const AppState({
    super.key,
    required this.api,
    required this.auth,
    required this.league,
    required this.theme,
    required this.predictions,
    required this.preseason,
    required this.notifications,
    required this.homeCache,
    required this.child,
  });

  @override
  State<AppState> createState() => _AppStateState();

  // ignore: library_private_types_in_public_api
  static _AppStateScope of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<_AppStateScope>();
    assert(scope != null, 'AppState not found in widget tree');
    return scope!;
  }
}

class _AppStateState extends State<AppState> {
  @override
  Widget build(BuildContext context) => _AppStateScope(
        api: widget.api,
        auth: widget.auth,
        league: widget.league,
        theme: widget.theme,
        predictions: widget.predictions,
        preseason: widget.preseason,
        notifications: widget.notifications,
        homeCache: widget.homeCache,
        child: widget.child,
      );
}

class _AppStateScope extends InheritedWidget {
  final ApiClient api;
  final AuthController auth;
  final LeagueController league;
  final ThemeController theme;
  final PredictionsController predictions;
  final PreseasonController preseason;
  final NotificationSettingsController notifications;
  final HomeCacheController homeCache;

  const _AppStateScope({
    required this.api,
    required this.auth,
    required this.league,
    required this.theme,
    required this.predictions,
    required this.preseason,
    required this.notifications,
    required this.homeCache,
    required super.child,
  });

  @override
  bool updateShouldNotify(_AppStateScope oldWidget) => false;
}
