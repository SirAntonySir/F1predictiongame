import 'package:go_router/go_router.dart';
import '../screens/calendar_screen.dart';
import '../screens/change_password_screen.dart';
import '../screens/home_screen.dart';
import '../screens/league_onboarding_screen.dart';
import '../screens/login_screen.dart';
import '../screens/predict_screen.dart';
import '../screens/preseason_screen.dart';
import '../screens/preseason_standings_screen.dart';
import '../screens/session_results_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/signup_screen.dart';
import '../screens/standings/standings_screen.dart';
import '../screens/trajectory_fullscreen_screen.dart';
import '../api/models/session_leaderboard_row.dart';
import '../state/auth_controller.dart';
import 'app_shell.dart';

GoRouter buildRouter(AuthController auth) {
  const authRoutes = {'/login', '/signup'};
  // Routes accessible regardless of auth state. /change-password is here so
  // the login screen can offer "Change password" without forcing a sign-in
  // first, while settings can also push to it for the logged-in flow.
  const openRoutes = {'/change-password'};
  const onboardingRoute = '/onboarding/league';
  return GoRouter(
    initialLocation: '/home',
    refreshListenable: auth,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      if (!auth.isLoggedIn) {
        if (authRoutes.contains(loc) || openRoutes.contains(loc)) return null;
        return '/login';
      }
      if (!auth.hasLeague) {
        return loc == onboardingRoute ? null : onboardingRoute;
      }
      if (authRoutes.contains(loc) || loc == onboardingRoute) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/login',  builder: (_, __) => LoginScreen(auth: auth)),
      GoRoute(path: '/signup', builder: (_, __) => SignupScreen(auth: auth)),
      GoRoute(
        path: '/change-password',
        builder: (_, s) => ChangePasswordScreen(
          prefilledEmail: s.uri.queryParameters['email'],
        ),
      ),
      GoRoute(path: onboardingRoute, builder: (_, __) => LeagueOnboardingScreen(auth: auth)),
      ShellRoute(
        builder: (_, __, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/home',     builder: (_, __) => const HomeScreen()),
          GoRoute(path: '/calendar', builder: (_, __) => const CalendarScreen()),
          GoRoute(
            path: '/predict',
            builder: (_, s) {
              final raw = s.uri.queryParameters['session'];
              final sid = raw == null ? null : int.tryParse(raw);
              return PredictScreen(sessionId: sid);
            },
          ),
          GoRoute(
            path: '/standings',
            builder: (_, s) => StandingsScreen(subTab: 'league', leagueSort: s.uri.queryParameters['sort']),
            routes: [
              GoRoute(path: 'league',   builder: (_, s) => StandingsScreen(subTab: 'league', leagueSort: s.uri.queryParameters['sort'])),
              GoRoute(path: 'f1',       builder: (_, __) => const StandingsScreen(subTab: 'f1')),
              GoRoute(path: 'insights', builder: (_, __) => const StandingsScreen(subTab: 'insights')),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/race/:round/:session',
        builder: (_, s) => SessionResultsScreen(
          round: int.parse(s.pathParameters['round']!),
          sessionId: int.parse(s.pathParameters['session']!),
        ),
      ),
      GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
      // Trajectory full-screen. Data arrives via `extra` (passed by the
      // insights tab); if it's missing (deep link, hot restart) we render the
      // screen with an empty session list — it falls back to a "no data" view.
      GoRoute(
        path: '/insights/trajectory',
        builder: (_, s) {
          final data = s.extra as List<SessionLeaderboardRow>?;
          return TrajectoryFullscreenScreen(sessions: data ?? const []);
        },
      ),
      GoRoute(
        path: '/preseason',
        builder: (_, __) => const PreseasonScreen(),
        routes: [
          GoRoute(
            path: 'standings/:kind',
            builder: (_, s) => PreseasonStandingsScreen(
              kind: s.pathParameters['kind'] ?? 'drivers',
            ),
          ),
        ],
      ),
    ],
  );
}
