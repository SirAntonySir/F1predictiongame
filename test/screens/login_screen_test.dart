import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/api_client.dart';
import 'package:predictiongame/api/models/auth_result.dart';
import 'package:predictiongame/api/models/me_result.dart';
import 'package:predictiongame/api/models/user.dart';
import 'package:predictiongame/screens/login_screen.dart';
import 'package:predictiongame/state/auth_controller.dart';
import 'package:predictiongame/state/token_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApi implements ApiClient {
  AuthResult? loginReply;
  MeResult? meReply;
  Object? loginError;
  String? lastEmail;
  String? lastPassword;
  @override Future<AuthResult> login({required String email, required String password}) async {
    lastEmail = email; lastPassword = password;
    if (loginError != null) throw loginError!;
    return loginReply!;
  }
  @override Future<MeResult> me() async => meReply!;
  @override noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  testWidgets('empty submit shows validation errors', (tester) async {
    final auth = AuthController(storage: InMemoryTokenStorage())..api = _FakeApi();
    await tester.pumpWidget(MaterialApp(home: LoginScreen(auth: auth)));
    await tester.tap(find.text('Log in'));
    await tester.pump();
    expect(find.text('Required'), findsAtLeastNWidgets(1));
  });

  testWidgets('Calls auth.login with entered values', (tester) async {
    final api = _FakeApi()
      ..loginReply = AuthResult(user: User(id: 'u1', email: 'a@b.com', displayName: 'A', createdAt: DateTime.utc(2026,1,1)), token: 'tok')
      ..meReply = MeResult(user: User(id: 'u1', email: 'a@b.com', displayName: 'A', createdAt: DateTime.utc(2026,1,1)), leagues: const []);
    final auth = AuthController(storage: InMemoryTokenStorage())..api = api;
    await tester.pumpWidget(MaterialApp(home: LoginScreen(auth: auth)));
    await tester.enterText(find.byKey(const Key('login.email')), 'a@b.com');
    await tester.enterText(find.byKey(const Key('login.password')), 'hunter22x');
    await tester.tap(find.text('Log in'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(api.lastEmail, 'a@b.com');
    expect(api.lastPassword, 'hunter22x');
    expect(auth.isLoggedIn, isTrue);
  });

  testWidgets('UnauthorizedException shows "Invalid email or password"', (tester) async {
    final api = _FakeApi()..loginError = const UnauthorizedException();
    final auth = AuthController(storage: InMemoryTokenStorage())..api = api;
    await tester.pumpWidget(MaterialApp(home: LoginScreen(auth: auth)));
    await tester.enterText(find.byKey(const Key('login.email')), 'a@b.com');
    await tester.enterText(find.byKey(const Key('login.password')), 'bad');
    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();
    expect(find.text('Invalid email or password'), findsOneWidget);
  });
}
