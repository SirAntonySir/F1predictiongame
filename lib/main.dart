import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'api/http_api_client.dart';
import 'app.dart';
import 'screens/splash_screen.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'state/auth_controller.dart';
import 'state/league_controller.dart';
import 'services/notifications/fcm_transport.dart';
import 'services/notifications/local_display.dart';
import 'services/notifications/push_service.dart';
import 'nav/deep_link.dart';
import 'state/home_cache_controller.dart';
import 'state/live_session_controller.dart';
import 'state/notification_settings_controller.dart';
import 'state/predictions_controller.dart';
import 'state/preseason_controller.dart';
import 'state/avatar_controller.dart';
import 'state/theme_controller.dart';
import 'state/token_storage.dart';

const _apiUrl = String.fromEnvironment('API_URL',
    defaultValue: 'https://f1pg-backend.onrender.com');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // ReminderService.init() is moved to _AfterBoot._loadLate() — calling it
  // here races with native plugin registration (this app uses the new
  // FlutterImplicitEngineDelegate pattern which registers plugins AFTER main
  // starts), producing MissingPluginException on cold launch.
  final storage = SecureTokenStorage();
  final auth = AuthController(storage: storage);
  final api = HttpApiClient(
    baseUrl: _apiUrl,
    tokenProvider: () => auth.token,
    onUnauthorized: () => auth.invalidate(),
    client: http.Client(),
  );
  auth.api = api;

  // Load the saved theme choice before the first frame so the splash
  // background matches the app (a dark-theme user must never see a light
  // flash). Cheap: one SharedPreferences read.
  final theme = await ThemeController.load();

  runApp(_Boot(api: api, auth: auth, theme: theme));
}

class _Boot extends StatefulWidget {
  final HttpApiClient api;
  final AuthController auth;
  final ThemeController theme;
  const _Boot({required this.api, required this.auth, required this.theme});
  @override
  State<_Boot> createState() => _BootState();
}

class _BootState extends State<_Boot> {
  Future<void>? _bootstrap;
  Object? _bootError;
  // The app mounts UNDERNEATH the splash overlay; this flips once the first
  // routed screen (home / login) has painted its first frame.
  bool _appPainted = false;
  // The splash artwork finished + faded — remove the overlay entirely.
  bool _splashDone = false;

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
        final booted = snap.connectionState == ConnectionState.done &&
            _bootError == null;
        // The splash is an overlay: once booted, the real app builds and
        // routes BENEATH it (home screen mounts, kicks off its fetches).
        // Only when that first screen has painted does the splash finish
        // its artwork and cross-fade away — never a half-built frame.
        return Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (booted)
                _AfterBoot(
                  api: widget.api,
                  auth: widget.auth,
                  theme: widget.theme,
                  onFirstFrame: () {
                    if (!_appPainted) setState(() => _appPainted = true);
                  },
                ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                child: _splashDone
                    ? const SizedBox.shrink()
                    : SplashScreen(
                        onRetry: () async => _start(),
                        error: _bootError,
                        ready: booted && _appPainted,
                        themeMode: widget.theme.mode,
                        onAnimationDone: () =>
                            setState(() => _splashDone = true),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AfterBoot extends StatefulWidget {
  final HttpApiClient api;
  final AuthController auth;
  final ThemeController theme;

  /// Fired after the routed app (or the late-boot error screen) has painted
  /// its first frame — the splash overlay above waits for this to lift.
  final VoidCallback onFirstFrame;
  const _AfterBoot({
    required this.api,
    required this.auth,
    required this.theme,
    required this.onFirstFrame,
  });
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
    // Theme was already loaded before runApp (the splash uses it); reuse the
    // same controller so a Settings change keeps a single source of truth.
    final theme = widget.theme;
    final avatar = await AvatarController.load();
    // Backend sync: pushes on save (gated on login), and reconciles with the
    // server's stored avatar. Bootstrap already ran before this widget, so the
    // controller wasn't attached to catch it — reconcile once explicitly with
    // the avatar auth already fetched. Later logins reconcile via AuthController.
    avatar.attachSync(widget.api, () => widget.auth.isLoggedIn);
    widget.auth.attachAvatarController(avatar);
    if (widget.auth.isLoggedIn) {
      // ignore: discarded_futures
      avatar.reconcileWithServer(widget.auth.user?.avatar);
    }
    // Server-backed: the backend owns notification scheduling + preferences now.
    final notifications = NotificationSettingsController(api: widget.api);

    // Push: display foreground banners locally, register the device token with
    // the backend. All best-effort — Firebase being absent/unconfigured (no
    // native config files yet) must not block boot, so [FcmPushTransport.create]
    // returns null and push silently stays off.
    // A push tap carries a `data.route` deep link; hand it to the router (which
    // registers itself once the widget tree builds, and buffers cold-start taps).
    void onPushRoute(String route) => handlePushRoute(route);
    await LocalDisplay.instance.init(onTapPayload: onPushRoute);
    // Resolve the device's IANA zone once; the server uses it to gate quiet
    // hours. Best-effort — null just means quiet hours won't apply yet.
    String? deviceTz;
    try {
      deviceTz = (await FlutterTimezone.getLocalTimezone()).identifier;
    } catch (_) {}
    final transport = await FcmPushTransport.create();
    PushService? push;
    if (transport != null) {
      push = PushService(
        api: widget.api,
        transport: transport,
        timezoneProvider: deviceTz == null ? null : () => deviceTz!,
      );
      attachFcmHandlers(display: LocalDisplay.instance, onRoute: onPushRoute);
    }

    final preds = PredictionsController(api: widget.api);
    widget.auth.attachPredictionsController(preds);
    if (widget.auth.isLoggedIn) {
      // ignore: discarded_futures
      preds.refreshUpcoming();
      // ignore: discarded_futures
      notifications.refresh();
      // ignore: discarded_futures
      push?.start();
    }
    final league = LeagueController(api: widget.api);
    if (widget.auth.leagues.isNotEmpty) {
      await league.load(widget.auth.leagues.first.id);
    }
    // Keep the LeagueController in sync with auth.leagues so Settings and
    // Standings (which read scope.league.league directly) show the right name
    // and join code after login/logout/league-switch — without this the
    // controller only loads at app boot and stays null for everyone who
    // signs in afterwards.
    // Track previous login state so we can detect transitions (login/logout)
    // and refresh upcoming reminders accordingly. `auth.clear()` already wipes
    // predictions on logout (which cancels reminders via onUpcomingSynced=[]),
    // so we only need to re-arm on login here.
    var wasLoggedIn = widget.auth.isLoggedIn;
    widget.auth.addListener(() {
      final leagues = widget.auth.leagues;
      if (leagues.isEmpty) {
        league.clear();
      } else if (league.league?.id != leagues.first.id) {
        // ignore: discarded_futures
        league.load(leagues.first.id);
      }
      final isNow = widget.auth.isLoggedIn;
      if (isNow && !wasLoggedIn) {
        // ignore: discarded_futures
        preds.refreshUpcoming();
        // ignore: discarded_futures
        notifications.refresh();
        // ignore: discarded_futures
        push?.start();
      } else if (!isNow && wasLoggedIn) {
        // Drop this device's token so the previous user stops getting pushes.
        // ignore: discarded_futures
        push?.stop();
      }
      wasLoggedIn = isNow;
    });
    final preseason = PreseasonController(api: widget.api);
    if (widget.auth.isLoggedIn) {
      // Best-effort prefetch; screen calls refresh() on demand if it fails.
      try {
        await preseason.refresh();
      } catch (_) {}
    }
    final live = LiveSessionController(api: widget.api);
    final homeCache = HomeCacheController(
      api: widget.api,
      auth: widget.auth,
      predictions: preds,
      live: live,
    );
    // When a live session finalises (backend scored it), refresh home data
    // right away — leaderboard, souvenir and scores update without waiting
    // for the user to pull-to-refresh or re-enter the screen. The refresh
    // also re-runs live.update(), which drops the finished session from
    // "live" and swaps the hero back to the next event.
    live.onSessionFinalised = () {
      // ignore: discarded_futures
      homeCache.refresh();
    };
    // Auto-clear on logout so the next user doesn't briefly see the
    // previous user's leaderboard. Also wire to the existing auth listener
    // below for login-side prefetch.
    widget.auth.addListener(() {
      if (!widget.auth.isLoggedIn) homeCache.clear();
    });
    return _LateState(
      theme: theme,
      avatar: avatar,
      predictions: preds,
      preseason: preseason,
      league: league,
      notifications: notifications,
      homeCache: homeCache,
      live: live,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_LateState>(
      future: _late,
      builder: (_, snap) {
        if (snap.connectionState != ConnectionState.done) {
          // The splash overlay above still covers us — nothing to show yet.
          return const ColoredBox(color: Color(0xFF000000));
        }
        // FutureBuilder hands us a `done` state when the future errored *or*
        // completed normally. Guard so a thrown _loadLate() doesn't surface
        // as a cryptic null-check error. Ping the overlay so it lifts and
        // reveals the error card instead of resting on the artwork forever.
        if (snap.hasError || snap.data == null) {
          return _FirstFramePing(
            onFirstFrame: widget.onFirstFrame,
            child: SplashScreen(
              onRetry: () async {},
              error: snap.error,
              themeMode: widget.theme.mode,
            ),
          );
        }
        final s = snap.data!;
        // The routed app: its initial screen (home / login) mounts and
        // paints within this frame — the ping tells the splash overlay.
        return _FirstFramePing(
          onFirstFrame: widget.onFirstFrame,
          child: F1PgApp(
            api: widget.api,
            auth: widget.auth,
            avatar: s.avatar,
            league: s.league,
            theme: s.theme,
            predictions: s.predictions,
            preseason: s.preseason,
            notifications: s.notifications,
            homeCache: s.homeCache,
            live: s.live,
          ),
        );
      },
    );
  }
}

/// Invokes [onFirstFrame] once, after the frame in which [child] first
/// builds has been painted — i.e. the routed screen is actually on screen.
class _FirstFramePing extends StatefulWidget {
  final VoidCallback onFirstFrame;
  final Widget child;
  const _FirstFramePing({required this.onFirstFrame, required this.child});
  @override
  State<_FirstFramePing> createState() => _FirstFramePingState();
}

class _FirstFramePingState extends State<_FirstFramePing> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onFirstFrame();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _LateState {
  final ThemeController theme;
  final AvatarController avatar;
  final PredictionsController predictions;
  final PreseasonController preseason;
  final LeagueController league;
  final NotificationSettingsController notifications;
  final HomeCacheController homeCache;
  final LiveSessionController live;
  _LateState({
    required this.theme,
    required this.avatar,
    required this.predictions,
    required this.preseason,
    required this.league,
    required this.notifications,
    required this.homeCache,
    required this.live,
  });
}
