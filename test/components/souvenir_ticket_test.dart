import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/models/event.dart';
import 'package:predictiongame/components/ticket/souvenir_ticket.dart';
import 'package:predictiongame/components/ticket/ticket_style.dart';

const _event = Event(
  round: 8,
  name: 'Monaco Grand Prix',
  country: 'Monaco',
  circuitName: 'Circuit de Monaco',
  hasSprint: false,
  sessions: [],
);

Future<void> _pump(WidgetTester tester, SouvenirTicket ticket) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: Center(child: SizedBox(width: 360, child: ticket))),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an unscored session shows a dash, not +0', (tester) async {
    await _pump(
        tester,
        const SouvenirTicket(
          event: _event,
          driverCodes: ['VER', 'NOR'],
          scorePoints: null,
          styleOverride: TicketStyle.nightCarbon,
        ));
    expect(find.text('—'), findsOneWidget);
    expect(find.text('+0'), findsNothing);
    expect(find.text('SCORING…'), findsOneWidget);
    expect(find.text('SEALED'), findsNothing);
  });

  testWidgets('a provisional score is not presented as sealed', (tester) async {
    await _pump(
        tester,
        const SouvenirTicket(
          event: _event,
          driverCodes: ['VER', 'NOR'],
          scorePoints: 4,
          provisional: true,
          styleOverride: TicketStyle.nightCarbon,
        ));
    expect(find.text('+4'), findsOneWidget);
    expect(find.text('PROVISIONAL'), findsOneWidget);
    expect(find.text('SEALED'), findsNothing);
  });

  testWidgets('an official score is sealed', (tester) async {
    await _pump(
        tester,
        const SouvenirTicket(
          event: _event,
          driverCodes: ['VER', 'NOR'],
          scorePoints: 4,
          styleOverride: TicketStyle.nightCarbon,
        ));
    expect(find.text('SEALED'), findsOneWidget);
  });

  testWidgets('the title does not double "Grand Prix"', (tester) async {
    await _pump(
        tester,
        const SouvenirTicket(
          event: _event,
          driverCodes: ['VER'],
          scorePoints: 4,
          styleOverride: TicketStyle.nightCarbon,
        ));
    expect(find.text('MONACO GP'), findsOneWidget);
    expect(find.textContaining('GRAND PRIX GP'), findsNothing);
  });
}
