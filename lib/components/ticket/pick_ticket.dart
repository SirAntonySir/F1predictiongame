import 'package:flutter/material.dart';

import '../../api/models/event.dart';
import '../../theme/ticket_style_for_event.dart';
import 'car_svg.dart';
import 'ticket_rohling.dart';
import 'ticket_stub.dart';
import 'ticket_style.dart';

/// Locked-prediction ticket. Pre-race: shows picks with STATUS=LOCKED and the
/// preset's default stub. Post-race: stub flips to a serial code and STATUS
/// shows the points earned.
class PickTicket extends StatelessWidget {
  final Event event;
  final List<String> driverCodes;
  /// Optional team id for the illustration slot (typically the P1 pick's
  /// constructor). Null means no car illustration is rendered.
  final String? p1ConstructorId;
  /// Null before the race has been scored.
  final int? scorePoints;
  /// Optional caller-friendly meta (e.g. "FRI · 17:00"). Null falls through
  /// to a default round / weekday label.
  final String? metaRight;
  final TicketStyle? styleOverride;
  final VoidCallback? onBodyTap;
  final VoidCallback? onStubTap;
  final VoidCallback? onTap;

  const PickTicket({
    super.key,
    required this.event,
    required this.driverCodes,
    this.p1ConstructorId,
    this.scorePoints,
    this.metaRight,
    this.styleOverride,
    this.onBodyTap,
    this.onStubTap,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final style = styleOverride ?? styleForEvent(event);
    final scored = scorePoints != null;
    return TicketRohling(
      style: style,
      edgeSerial: 'RD ${event.round.toString().padLeft(2, '0')} · ${event.name.toUpperCase()}',
      metaLeft: 'RD ${event.round.toString().padLeft(2, '0')} · ${event.name.toUpperCase()}',
      metaRight: metaRight ?? 'YOUR PICK',
      title: event.name.toUpperCase(),
      subtitle: event.circuitName.toUpperCase(),
      illustration: p1ConstructorId == null ? null : CarSvg(constructorId: p1ConstructorId),
      dataRow: [
        for (var i = 0; i < driverCodes.length && i < 5; i++)
          TicketDataCell(label: 'P${i + 1}', value: driverCodes[i]),
        TicketDataCell(label: 'STATUS', value: scored ? '+${scorePoints!}' : 'LOCKED'),
      ],
      stub: scored ? TicketStub.serialCode('PICK · ${event.round}') : tokensFor(style).defaultStub,
      onTap: onTap,
      onBodyTap: onBodyTap,
      onStubTap: onStubTap,
    );
  }
}
