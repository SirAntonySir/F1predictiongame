import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'api/http_api_client.dart';
import 'app.dart';
import 'screens/splash_screen.dart';
import 'state/auth_controller.dart';
import 'state/league_controller.dart';
import 'state/predictions_controller.dart';
import 'state/preseason_controller.dart';
import 'state/theme_controller.dart';
import 'state/token_storage.dart';

const _apiUrl =
    String.fromEnvironment('API_URL', defaultValue: 'https://f1pg-backend.onrender.com');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = SecureTokenStorage();
  final auth = AuthController(storage: storage);
  final api = HttpApiClient(
    baseUrl: _apiUrl,
    tokenProvider: () => auth.token,
    onUnauthorized: () => auth.invalidate(),
    client: http.Client(),
  );
  auth.api = api;

  runApp(_Boot(api: api, auth: auth));
}

class _Boot extends StatefulWidget {
  final HttpApiClient api;
  final AuthController auth;
  const _Boot({required this.api, required this.auth});
  @override
  State<_Boot> createState() => _BootState();
}

class _BootState extends State<_Boot> {
  Future<void>? _bootstrap;
  Object? _bootError;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    setState(() {
      _bootError = null;
      _bootstrap = widget.auth.bootstrap().catchError((e) {
        setState(() => _bootError = e);
        throw e;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _bootstrap,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done || _bootError != null) {
          return SplashScreen(
            onRetry: () async => _start(),
            error: _bootError,
          );
        }
        return _AfterBoot(api: widget.api, auth: widget.auth);
      },
    );
  }
}

class _AfterBoot extends StatefulWidget {
  final HttpApiClient api;
  final AuthController auth;
  const _AfterBoot({required this.api, required this.auth});
  @override
  State<_AfterBoot> createState() => _AfterBootState();
}

class _AfterBootState extends State<_AfterBoot> {
  late final Future<_LateState> _late;

  @override
  void initState() {
    super.initState();
    _late = _loadLate();
  }

  Future<_LateState> _loadLate() async {
    final theme = await ThemeController.load();
    final preds = PredictionsController(api: widget.api);
    widget.auth.attachPredictionsController(preds);
    final league = LeagueController(api: widget.api);
    if (widget.auth.leagues.isNotEmpty) {
      await league.load(widget.auth.leagues.first.id);
    }
    // Keep the LeagueController in sync with auth.leagues so Settings and
    // Standings (which read scope.league.league directly) show the right name
    // and join code after login/logout/league-switch — without this the
    // controller only loads at app boot and stays null for everyone who
    // signs in afterwards.
    widget.auth.addListener(() {
      final leagues = widget.auth.leagues;
      if (leagues.isEmpty) {
        league.clear();
        return;
      }
      if (league.league?.id != leagues.first.id) {
        // ignore: discarded_futures
        league.load(leagues.first.id);
      }
    });
    final preseason = PreseasonController(api: widget.api);
    if (widget.auth.isLoggedIn) {
      // Best-effort prefetch; screen calls refresh() on demand if it fails.
      try { await preseason.refresh(); } catch (_) {}
    }
    return _LateState(theme: theme, predictions: preds, preseason: preseason, league: league);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_LateState>(
      future: _late,
      builder: (_, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return SplashScreen(onRetry: () async {}, error: null);
        }
        final s = snap.data!;
        return F1PgApp(
          api: widget.api,
          auth: widget.auth,
          league: s.league,
          theme: s.theme,
          predictions: s.predictions,
          preseason: s.preseason,
        );
      },
    );
  }
}

class _LateState {
  final ThemeController theme;
  final PredictionsController predictions;
  final PreseasonController preseason;
  final LeagueController league;
  _LateState({required this.theme, required this.predictions, required this.preseason, required this.league});
}
