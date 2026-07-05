import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/models/event.dart';
import 'package:predictiongame/components/ticket/pick_ticket.dart';
import 'package:predictiongame/components/ticket/ticket_style.dart';

const _event = Event(
  round: 9,
  name: 'British Grand Prix',
  country: 'UK',
  circuitName: 'Silverstone',
  hasSprint: false,
  sessions: [],
);

void main() {
  for (final style in const [
    TicketStyle.nightCarbon,
    TicketStyle.pitWallTelemetry,
    TicketStyle.asphaltStencil,
  ]) {
    testWidgets('dark ticket $style paints without error', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: SizedBox(
              width: 360,
              child: PickTicket(
                event: _event,
                driverCodes: const ['ANT', 'HAM', 'RUS', 'LEC', 'NOR'],
                styleOverride: style,
                statusOverride: 'DRAFT',
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
