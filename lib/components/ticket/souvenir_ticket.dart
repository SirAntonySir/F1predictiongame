import 'package:flutter/material.dart';

import '../../api/models/event.dart';
import '../../theme/ticket_style_for_event.dart';
import 'car_svg.dart';
import 'ticket_ornament.dart';
import 'ticket_rohling.dart';
import 'ticket_stub.dart';
import 'ticket_style.dart';

/// Shareable souvenir ticket. More decorated than [PickTicket]: always uses
/// the crossed-flags ornament regardless of preset, shows a qualitative grade
/// in addition to the raw points, and uses the long-form title.
class SouvenirTicket extends StatelessWidget {
  final Event event;
  final List<String> driverCodes;
  final String? p1ConstructorId;
  final int scorePoints;
  final TicketStyle? styleOverride;

  const SouvenirTicket({
    super.key,
    required this.event,
    required this.driverCodes,
    required this.scorePoints,
    this.p1ConstructorId,
    this.styleOverride,
  });

  @override
  Widget build(BuildContext context) {
    final style = styleOverride ?? styleForEvent(event);
    return TicketRohling(
      style: style,
      edgeSerial: 'PICK ${event.round.toString().padLeft(2, '0')} · ${event.name.toUpperCase()}',
      metaLeft: 'RD ${event.round.toString().padLeft(2, '0')} · ${event.name.toUpperCase()}',
      metaRight: 'SEALED',
      title: '${event.name.toUpperCase()} GP',
      subtitle: event.circuitName.toUpperCase(),
      illustration: p1ConstructorId == null ? null : CarSvg(constructorId: p1ConstructorId),
      ornament: TicketOrnament.crossedFlags,
      dataRow: [
        for (var i = 0; i < driverCodes.length && i < 5; i++)
          TicketDataCell(label: 'P${i + 1}', value: driverCodes[i]),
        TicketDataCell(label: 'GRADE', value: _grade(scorePoints)),
        TicketDataCell(label: 'POINTS', value: '+$scorePoints'),
      ],
      stub: TicketStub.serialCode('PICK · ${event.round}'),
    );
  }

  String _grade(int points) {
    if (points >= 25) return 'PODIUM CALL';
    if (points >= 15) return 'SHARP';
    if (points >= 5) return 'ON IT';
    return 'OFF-PACE';
  }
}
