import 'package:flutter/material.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'api/api_client.dart';
import 'nav/router.dart';
import 'nav/deep_link.dart';
import 'state/app_state.dart';
import 'state/auth_controller.dart';
import 'state/home_cache_controller.dart';
import 'state/league_controller.dart';
import 'state/live_session_controller.dart';
import 'state/notification_settings_controller.dart';
import 'state/predictions_controller.dart';
import 'state/preseason_controller.dart';
import 'state/theme_controller.dart';
import 'theme/app_theme.dart';

class F1PgApp extends StatefulWidget {
  final ApiClient api;
  final AuthController auth;
  final LeagueController league;
  final ThemeController theme;
  final PredictionsController predictions;
  final PreseasonController preseason;
  final NotificationSettingsController notifications;
  final HomeCacheController homeCache;
  final LiveSessionController live;

  const F1PgApp({
    super.key,
    required this.api,
    required this.auth,
    required this.league,
    required this.theme,
    required this.predictions,
    required this.preseason,
    required this.notifications,
    required this.homeCache,
    required this.live,
  });

  @override
  State<F1PgApp> createState() => _F1PgAppState();
}

class _F1PgAppState extends State<F1PgApp> {
  late final router = buildRouter(widget.auth);

  @override
  void initState() {
    super.initState();
    // Expose the router so notification taps (wired at boot) can deep-link,
    // and replay any route buffered before the router existed (cold start).
    registerAppRouter(router);
  }

  @override
  Widget build(BuildContext context) {
    return AppState(
      api: widget.api,
      auth: widget.auth,
      league: widget.league,
      theme: widget.theme,
      predictions: widget.predictions,
      preseason: widget.preseason,
      notifications: widget.notifications,
      homeCache: widget.homeCache,
      live: widget.live,
      child: ListenableBuilder(
        listenable: widget.theme,
        builder: (_, __) => MaterialApp.router(
          title: 'Undercut',
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: widget.theme.mode,
          routerConfig: router,
          // Brand the skeleton loading globally: a calm pulse in the app's
          // own neutral (onSurface at low alpha, so it adapts to light/dark)
          // instead of the default Material grey shimmer.
          builder: (context, child) {
            final onSurface = Theme.of(context).colorScheme.onSurface;
            return SkeletonizerConfig(
              data: SkeletonizerConfigData(
                effect: PulseEffect(
                  from: onSurface.withValues(alpha: 0.07),
                  to: onSurface.withValues(alpha: 0.15),
                ),
              ),
              child: child ?? const SizedBox.shrink(),
            );
          },
        ),
      ),
    );
  }
}
