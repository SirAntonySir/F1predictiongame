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

  @override Future<LeagueView> joinLeague({required String code}) async {
    lastJoinCode = code;
    if (joinError != null) throw joinError!;
    return joinReply!;
  }
  @override Future<LeagueView> createLeague({required String name}) async {
    lastCreatedName = name;
    if (createError != null) throw createError!;
    return createReply!;
  }
  @override Future<MeResult> me() async => meReply!;
  @override noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('join → calls joinLeague + refreshMe', (tester) async {
    final api = _FakeApi()
      ..joinReply = LeagueView(id: 'L', name: 'Eins', role: 'member', joinCode: null, members: const [])
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
      ..createReply = LeagueView(id: 'L', name: 'New', role: 'owner', joinCode: 'JJJJ22', members: const [])
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
}
