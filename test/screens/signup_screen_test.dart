import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/api_client.dart';
import 'package:predictiongame/api/models/auth_result.dart';
import 'package:predictiongame/api/models/me_result.dart';
import 'package:predictiongame/api/models/user.dart';
import 'package:predictiongame/screens/signup_screen.dart';
import 'package:predictiongame/state/auth_controller.dart';
import 'package:predictiongame/state/token_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApi implements ApiClient {
  AuthResult? signupReply;
  Object? signupError;
  MeResult? meReply;
  String? lastEmail;
  String? lastPassword;
  String? lastDisplay;
  @override Future<AuthResult> signup({required String email, required String password, required String displayName}) async {
    lastEmail = email; lastPassword = password; lastDisplay = displayName;
    if (signupError != null) throw signupError!;
    return signupReply!;
  }
  @override Future<MeResult> me() async => meReply!;
  @override noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  testWidgets('happy path calls signup and logs in', (tester) async {
    final api = _FakeApi()
      ..signupReply = AuthResult(user: User(id: 'u1', email: 'a@b.com', displayName: 'A', createdAt: DateTime.utc(2026,1,1)), token: 'tok');
    final auth = AuthController(storage: InMemoryTokenStorage())..api = api;
    await tester.pumpWidget(MaterialApp(home: SignupScreen(auth: auth)));
    await tester.enterText(find.byKey(const Key('signup.email')), 'a@b.com');
    await tester.enterText(find.byKey(const Key('signup.password')), 'hunter22x');
    await tester.enterText(find.byKey(const Key('signup.displayName')), 'A');
    await tester.tap(find.byKey(const Key('signup.submit')));
    await tester.pumpAndSettle();
    expect(api.lastEmail, 'a@b.com');
    expect(api.lastPassword, 'hunter22x');
    expect(api.lastDisplay, 'A');
    expect(auth.isLoggedIn, isTrue);
  });

  testWidgets('ConflictException shows "Email already registered"', (tester) async {
    final api = _FakeApi()..signupError = const ConflictException('Email already registered');
    final auth = AuthController(storage: InMemoryTokenStorage())..api = api;
    await tester.pumpWidget(MaterialApp(home: SignupScreen(auth: auth)));
    await tester.enterText(find.byKey(const Key('signup.email')), 'taken@x.com');
    await tester.enterText(find.byKey(const Key('signup.password')), 'hunter22x');
    await tester.enterText(find.byKey(const Key('signup.displayName')), 'A');
    await tester.tap(find.byKey(const Key('signup.submit')));
    await tester.pumpAndSettle();
    expect(find.text('Email already registered'), findsOneWidget);
  });
}
