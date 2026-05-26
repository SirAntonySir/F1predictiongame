import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:predictiongame/api/api_client.dart';
import 'package:predictiongame/api/models/me_result.dart';
import 'package:predictiongame/api/models/user.dart';
import 'package:predictiongame/api/models/user_league.dart';
import 'package:predictiongame/domain/league.dart';
import 'package:predictiongame/nav/router.dart';
import 'package:predictiongame/state/app_state.dart';
import 'package:predictiongame/state/auth_controller.dart';
import 'package:predictiongame/state/league_controller.dart';
import 'package:predictiongame/state/predictions_store.dart';
import 'package:predictiongame/state/preseason_store.dart';
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
    league: LeagueController(league: const League(id: 'L', name: 'Eins', players: [])),
    theme: ThemeController(ThemeMode.system),
    predictions: PredictionsStore(const {}),
    preseason: PreseasonStore(const {}),
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
