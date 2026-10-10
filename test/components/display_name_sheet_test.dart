import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/api_client.dart';
import 'package:predictiongame/api/models/me_result.dart';
import 'package:predictiongame/api/models/user.dart';
import 'package:predictiongame/components/display_name_sheet.dart';
import 'package:predictiongame/state/auth_controller.dart';
import 'package:predictiongame/state/token_storage.dart';

User _user(String name) => User(
    id: 'u1', email: 'a@b.com', displayName: name, createdAt: DateTime.utc(2026, 1, 1));

class _FakeApi implements ApiClient {
  String serverName = 'Anton';
  final taken = <String>{'lukas'};
  final patched = <String>[];

  @override
  Future<User> patchMe({String? displayName, String? avatar}) async {
    patched.add(displayName!);
    if (taken.contains(displayName.trim().toLowerCase())) {
      throw const ConflictException('Someone in Eins already uses that name');
    }
    serverName = displayName.trim();
    return _user(serverName);
  }

  @override
  Future<MeResult> me() async => MeResult(user: _user(serverName), leagues: const []);

  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  late _FakeApi api;
  late AuthController auth;
  bool? result;

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showDisplayNameSheet(context, auth),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  setUp(() {
    result = null;
    api = _FakeApi();
    auth = AuthController(storage: InMemoryTokenStorage())..api = api;
    auth.applyTestState(user: _user('Anton'), token: 'tok', leagues: const []);
  });

  testWidgets('saves a new name and updates the signed-in user', (tester) async {
    await open(tester);
    expect(find.widgetWithText(TextField, 'Anton'), findsOneWidget); // prefilled
    await tester.enterText(find.byType(TextField), 'Anton R');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(api.patched, ['Anton R']);
    expect(auth.user!.displayName, 'Anton R');
    expect(result, isTrue);
    expect(find.byType(TextField), findsNothing); // sheet closed
  });

  testWidgets('a name clash keeps the sheet open with the reason', (tester) async {
    await open(tester);
    await tester.enterText(find.byType(TextField), 'Lukas');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Someone in Eins already uses that name'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(auth.user!.displayName, 'Anton');
  });

  testWidgets('an empty name is rejected before calling the server', (tester) async {
    await open(tester);
    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(api.patched, isEmpty);
    expect(find.text('Enter a name'), findsOneWidget);
  });
}
