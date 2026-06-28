import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/models/event.dart';
import 'package:predictiongame/components/ticket/pick_ticket.dart';
import 'package:predictiongame/components/ticket/souvenir_ticket.dart';

const _event = Event(
  round: 9,
  name: 'British Grand Prix',
  country: 'UK',
  circuitName: 'Silverstone',
  hasSprint: false,
  sessions: [],
);

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: Center(child: child)),
  ));
}

void main() {
  testWidgets(
      'long-press on a PickTicket opens a sheet with the wired nav rows + Share',
      (tester) async {
    var opened = 0;
    var edited = 0;
    await _pump(
      tester,
      PickTicket(
        event: _event,
        driverCodes: const ['VER', 'NOR'],
        illustration: const SizedBox(),
        onBodyTap: () => opened++,
        onStubTap: () => edited++,
      ),
    );

    await tester.longPress(find.byType(PickTicket));
    await tester.pumpAndSettle();

    expect(find.text('Open race details'), findsOneWidget);
    expect(find.text('Edit pick'), findsOneWidget);
    expect(find.text('Share ticket'), findsOneWidget);

    await tester.tap(find.text('Edit pick'));
    await tester.pumpAndSettle();
    expect(edited, 1);
    expect(opened, 0);
  });

  testWidgets(
      'PickTicket sheet omits nav rows whose callback was not wired up',
      (tester) async {
    await _pump(
      tester,
      PickTicket(
        event: _event,
        driverCodes: const ['VER'],
        illustration: const SizedBox(),
        onStubTap: () {},
        // no onBodyTap / onTap
      ),
    );

    await tester.longPress(find.byType(PickTicket));
    await tester.pumpAndSettle();

    expect(find.text('Open race details'), findsNothing);
    expect(find.text('Edit pick'), findsOneWidget);
    expect(find.text('Share ticket'), findsOneWidget);
  });

  testWidgets(
      'long-press on a SouvenirTicket opens a sheet with Open + Share',
      (tester) async {
    var opened = 0;
    await _pump(
      tester,
      SouvenirTicket(
        event: _event,
        driverCodes: const ['VER', 'NOR'],
        scorePoints: 12,
        illustration: const SizedBox(),
        onTap: () => opened++,
      ),
    );

    await tester.longPress(find.byType(SouvenirTicket));
    await tester.pumpAndSettle();

    expect(find.text('Open race details'), findsOneWidget);
    expect(find.text('Share ticket'), findsOneWidget);

    await tester.tap(find.text('Open race details'));
    await tester.pumpAndSettle();
    expect(opened, 1);
  });
}
