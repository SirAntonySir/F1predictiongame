import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:predictiongame/api/api_client.dart';
import 'package:predictiongame/api/models/me_result.dart';
import 'package:predictiongame/api/models/user.dart';
import 'package:predictiongame/api/models/user_league.dart';
import 'package:predictiongame/nav/router.dart';
import 'package:predictiongame/state/app_state.dart';
import 'package:predictiongame/avatar/avatar_config.dart';
import 'package:predictiongame/state/auth_controller.dart';
import 'package:predictiongame/state/avatar_controller.dart';
import 'package:predictiongame/state/home_cache_controller.dart';
import 'package:predictiongame/state/live_session_controller.dart';
import 'package:predictiongame/state/league_controller.dart';
import 'package:predictiongame/state/notification_settings_controller.dart';
import 'package:predictiongame/state/predictions_controller.dart';
import 'package:predictiongame/state/preseason_controller.dart';
import 'package:predictiongame/state/theme_controller.dart';
import 'package:predictiongame/state/token_storage.dart';

class _FakeApi implements ApiClient {
  @override Future<MeResult> me() async => throw UnimplementedError();
  @override noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

GoRouter _router(AuthController auth) => buildRouter(auth);

/// Wraps a router in a minimal AppState so screens that call AppState.of(context)
/// don't assert when the router navigates into the shell (e.g. /home).
Widget _withAppState({required AuthController auth, required GoRouter router}) {
  return AppState(
    api: _FakeApi(),
    auth: auth,
    avatar: AvatarController(const AvatarConfig()),
    league: LeagueController(api: _FakeApi()),
    theme: ThemeController(ThemeMode.system),
    predictions: PredictionsController(api: _FakeApi()),
    preseason: PreseasonController(api: _FakeApi()),
    notifications: NotificationSettingsController.forTesting(api: _FakeApi()),
    homeCache: HomeCacheController(
      api: _FakeApi(),
      auth: auth,
      predictions: PredictionsController(api: _FakeApi()),
    ),
    live: LiveSessionController(api: _FakeApi()),
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('unauthenticated → /login', (tester) async {
    final auth = AuthController(storage: InMemoryTokenStorage())..api = _FakeApi();
    final router = _router(auth);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(router.routerDelegate.currentConfiguration.uri.toString(), '/login');
  });

  testWidgets('authenticated + no leagues → /onboarding/league', (tester) async {
    final auth = AuthController(storage: InMemoryTokenStorage())..api = _FakeApi();
    auth.applyTestState(
      user: User(id: 'u1', email: 'a@b.com', displayName: 'A', createdAt: DateTime.utc(2026,1,1)),
      token: 'tok',
      leagues: const [],
    );
    final router = _router(auth);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(router.routerDelegate.currentConfiguration.uri.toString(), '/onboarding/league');
  });

  testWidgets('authenticated + has leagues → /home', (tester) async {
    final auth = AuthController(storage: InMemoryTokenStorage())..api = _FakeApi();
    auth.applyTestState(
      user: User(id: 'u1', email: 'a@b.com', displayName: 'A', createdAt: DateTime.utc(2026,1,1)),
      token: 'tok',
      leagues: const [UserLeague(id: 'L', name: 'Eins', role: 'member')],
    );
    final router = _router(auth);
    await tester.pumpWidget(_withAppState(auth: auth, router: router));
    await tester.pumpAndSettle();
    expect(router.routerDelegate.currentConfiguration.uri.toString(), '/home');
  });
}
