import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/api_client.dart';
import 'package:predictiongame/api/models/league_view.dart';
import 'package:predictiongame/api/models/me_result.dart';
import 'package:predictiongame/api/models/user.dart';
import 'package:predictiongame/api/models/user_league.dart';
import 'package:predictiongame/screens/league_onboarding_screen.dart';
import 'package:predictiongame/state/auth_controller.dart';
import 'package:predictiongame/state/token_storage.dart';

class _FakeApi implements ApiClient {
  String? lastJoinCode;
  String? lastCreatedName;
  Object? joinError;
  Object? createError;
  LeagueView? joinReply;
  LeagueView? createReply;
  MeResult? meReply;

  @override Future<LeagueView> joinLeague({required String code, String? password}) async {
    lastJoinCode = code;
    if (joinError != null) throw joinError!;
    return joinReply!;
  }
  @override Future<LeagueView> createLeague({required String name, String? password}) async {
    lastCreatedName = name;
    if (createError != null) throw createError!;
    return createReply!;
  }
  @override Future<MeResult> me() async => meReply!;
  final renamedTo = <String>[];
  @override Future<User> patchMe({String? displayName, String? avatar}) async {
    renamedTo.add(displayName!);
    final u = User(id: 'u1', email: 'a@b.com', displayName: displayName, createdAt: DateTime.utc(2026,1,1));
    meReply = MeResult(user: u, leagues: const []);
    return u;
  }
  @override noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('join → calls joinLeague + refreshMe', (tester) async {
    final api = _FakeApi()
      ..joinReply = const LeagueView(id: 'L', name: 'Eins', role: 'member', joinCode: null, hasPassword: false, members: [])
      ..meReply = MeResult(
        user: User(id: 'u1', email: 'a@b.com', displayName: 'A', createdAt: DateTime.utc(2026,1,1)),
        leagues: const [UserLeague(id: 'L', name: 'Eins', role: 'member')],
      );
    final auth = AuthController(storage: InMemoryTokenStorage())..api = api;
    auth.applyTestState(
      user: User(id: 'u1', email: 'a@b.com', displayName: 'A', createdAt: DateTime.utc(2026,1,1)),
      token: 'tok',
      leagues: const [],
    );
    await tester.pumpWidget(MaterialApp(home: LeagueOnboardingScreen(auth: auth)));
    await tester.enterText(find.byKey(const Key('onboarding.joinCode')), 'tipp-2026');
    await tester.tap(find.byKey(const Key('onboarding.joinSubmit')));
    await tester.pumpAndSettle();
    expect(api.lastJoinCode, 'TIPP-2026');
    expect(auth.hasLeague, isTrue);
  });

  testWidgets('create → calls createLeague + refreshMe', (tester) async {
    final api = _FakeApi()
      ..createReply = const LeagueView(id: 'L', name: 'New', role: 'owner', joinCode: 'JJJJ22', hasPassword: false, members: [])
      ..meReply = MeResult(
        user: User(id: 'u1', email: 'a@b.com', displayName: 'A', createdAt: DateTime.utc(2026,1,1)),
        leagues: const [UserLeague(id: 'L', name: 'New', role: 'owner')],
      );
    final auth = AuthController(storage: InMemoryTokenStorage())..api = api;
    auth.applyTestState(
      user: User(id: 'u1', email: 'a@b.com', displayName: 'A', createdAt: DateTime.utc(2026,1,1)),
      token: 'tok',
      leagues: const [],
    );
    await tester.pumpWidget(MaterialApp(home: LeagueOnboardingScreen(auth: auth)));
    await tester.enterText(find.byKey(const Key('onboarding.createName')), 'New');
    await tester.tap(find.byKey(const Key('onboarding.createSubmit')));
    await tester.pumpAndSettle();
    expect(api.lastCreatedName, 'New');
    expect(auth.hasLeague, isTrue);
  });

  testWidgets('join NotFoundException shows "Unknown join code."', (tester) async {
    final api = _FakeApi()..joinError = const NotFoundException('Unknown join code');
    final auth = AuthController(storage: InMemoryTokenStorage())..api = api;
    auth.applyTestState(
      user: User(id: 'u1', email: 'a@b.com', displayName: 'A', createdAt: DateTime.utc(2026,1,1)),
      token: 'tok',
      leagues: const [],
    );
    await tester.pumpWidget(MaterialApp(home: LeagueOnboardingScreen(auth: auth)));
    await tester.enterText(find.byKey(const Key('onboarding.joinCode')), 'WRONG1');
    await tester.tap(find.byKey(const Key('onboarding.joinSubmit')));
    await tester.pumpAndSettle();
    expect(find.text('Unknown join code.'), findsOneWidget);
  });

  testWidgets('a display-name clash on join offers a rename right there', (tester) async {
    final api = _FakeApi()
      ..joinError = const ConflictException(
          'Another member of this league already uses that display name — change yours first.');
    final auth = AuthController(storage: InMemoryTokenStorage())..api = api;
    auth.applyTestState(
      user: User(id: 'u1', email: 'a@b.com', displayName: 'Anton', createdAt: DateTime.utc(2026,1,1)),
      token: 'tok',
      leagues: const [],
    );
    await tester.pumpWidget(MaterialApp(home: LeagueOnboardingScreen(auth: auth)));
    await tester.enterText(find.byKey(const Key('onboarding.joinCode')), 'tipp-2026');
    await tester.tap(find.byKey(const Key('onboarding.joinSubmit')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('CHANGE NAME'));
    await tester.tap(find.text('CHANGE NAME'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Anton'), 'Anton R');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(api.renamedTo, ['Anton R']);
    expect(auth.user!.displayName, 'Anton R');
    // The stale clash message is gone; the user can retry the join.
    expect(find.textContaining('already uses that display name'), findsNothing);
  });

  testWidgets('other join conflicts do not offer a rename', (tester) async {
    final api = _FakeApi()..joinError = const ConflictException('Already a member');
    final auth = AuthController(storage: InMemoryTokenStorage())..api = api;
    auth.applyTestState(
      user: User(id: 'u1', email: 'a@b.com', displayName: 'Anton', createdAt: DateTime.utc(2026,1,1)),
      token: 'tok',
      leagues: const [],
    );
    await tester.pumpWidget(MaterialApp(home: LeagueOnboardingScreen(auth: auth)));
    await tester.enterText(find.byKey(const Key('onboarding.joinCode')), 'tipp-2026');
    await tester.tap(find.byKey(const Key('onboarding.joinSubmit')));
    await tester.pumpAndSettle();

    expect(find.text('Already a member'), findsOneWidget);
    expect(find.text('CHANGE NAME'), findsNothing);
  });
}
