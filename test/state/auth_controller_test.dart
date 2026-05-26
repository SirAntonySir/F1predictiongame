import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:predictiongame/api/api_client.dart';
import 'package:predictiongame/api/models/auth_result.dart';
import 'package:predictiongame/api/models/me_result.dart';
import 'package:predictiongame/api/models/user.dart';
import 'package:predictiongame/api/models/user_league.dart';
import 'package:predictiongame/state/auth_controller.dart';
import 'package:predictiongame/state/token_storage.dart';

class _FakeApi implements ApiClient {
  AuthResult? signupReply;
  AuthResult? loginReply;
  MeResult? meReply;
  Object? meError;
  Object? loginError;
  Object? signupError;
  int logoutCalls = 0;

  @override Future<AuthResult> signup({required String email, required String password, required String displayName}) async {
    if (signupError != null) throw signupError!;
    return signupReply!;
  }
  @override Future<AuthResult> login({required String email, required String password}) async {
    if (loginError != null) throw loginError!;
    return loginReply!;
  }
  @override Future<MeResult> me() async {
    if (meError != null) throw meError!;
    return meReply!;
  }
  @override Future<void> logout() async { logoutCalls += 1; }

  @override noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

User _u(String id) => User(id: id, email: '$id@x', displayName: id, createdAt: DateTime.utc(2026, 1, 1));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  group('AuthController.bootstrap', () {
    test('no token → unauthenticated', () async {
      final api = _FakeApi();
      final auth = AuthController(storage: InMemoryTokenStorage())..api = api;
      await auth.bootstrap();
      expect(auth.isLoggedIn, isFalse);
      expect(auth.user, isNull);
    });

    test('valid token → fetches me, sets state', () async {
      final api = _FakeApi()
        ..meReply = MeResult(user: _u('u1'), leagues: const [UserLeague(id: 'L', name: 'Eins', role: 'owner')]);
      final storage = InMemoryTokenStorage();
      await storage.write('tok');
      final auth = AuthController(storage: storage)..api = api;
      await auth.bootstrap();
      expect(auth.isLoggedIn, isTrue);
      expect(auth.user!.id, 'u1');
      expect(auth.leagues.length, 1);
      expect(auth.hasLeague, isTrue);
    });

    test('stored token returning 401 → state wiped', () async {
      final api = _FakeApi()..meError = const UnauthorizedException();
      final storage = InMemoryTokenStorage();
      await storage.write('bad');
      final auth = AuthController(storage: storage)..api = api;
      await auth.bootstrap();
      expect(auth.isLoggedIn, isFalse);
      expect(await storage.read(), isNull);
    });
  });

  group('AuthController.signup', () {
    test('happy path stores token + state', () async {
      final api = _FakeApi()
        ..signupReply = AuthResult(user: _u('u1'), token: 'tok');
      final storage = InMemoryTokenStorage();
      final auth = AuthController(storage: storage)..api = api;
      await auth.signup('a@b.com', 'hunter22x', 'A');
      expect(auth.isLoggedIn, isTrue);
      expect(await storage.read(), 'tok');
      expect(auth.leagues, isEmpty);
      expect(auth.hasLeague, isFalse);
    });
  });

  group('AuthController.login', () {
    test('happy path stores token + state + leagues from /me', () async {
      final api = _FakeApi()
        ..loginReply = AuthResult(user: _u('u1'), token: 'tok')
        ..meReply = MeResult(user: _u('u1'), leagues: const [UserLeague(id: 'L', name: 'Eins', role: 'member')]);
      final storage = InMemoryTokenStorage();
      final auth = AuthController(storage: storage)..api = api;
      await auth.login('a@b.com', 'hunter22x');
      expect(auth.isLoggedIn, isTrue);
      expect(auth.hasLeague, isTrue);
    });

    test('invalid credentials propagates UnauthorizedException', () async {
      final api = _FakeApi()..loginError = const UnauthorizedException();
      final auth = AuthController(storage: InMemoryTokenStorage())..api = api;
      expect(auth.login('a', 'b'), throwsA(isA<UnauthorizedException>()));
    });
  });

  test('logout clears storage and state', () async {
    final api = _FakeApi();
    final storage = InMemoryTokenStorage();
    await storage.write('tok');
    final auth = AuthController(storage: storage)..api = api;
    auth.applyTestState(user: _u('u1'), token: 'tok', leagues: const [UserLeague(id: 'L', name: 'Eins', role: 'owner')]);
    await auth.logout();
    expect(auth.isLoggedIn, isFalse);
    expect(await storage.read(), isNull);
    expect(api.logoutCalls, 1);
  });

  test('invalidate is idempotent', () async {
    final storage = InMemoryTokenStorage();
    await storage.write('tok');
    final auth = AuthController(storage: storage)..api = _FakeApi();
    auth.applyTestState(user: _u('u1'), token: 'tok', leagues: const []);
    auth.invalidate();
    auth.invalidate();
    // Wait for any pending _wipe futures to settle.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(auth.isLoggedIn, isFalse);
    expect(await storage.read(), isNull);
  });
}
