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
  /// Optional pre-built illustration widget. Takes precedence over
  /// [p1ConstructorId] — useful in tests, dev previews, or when the caller
  /// already has the SVG resolved.
  final Widget? illustration;
  /// Watermark alignment override. Falls through to the Rohling default.
  final Alignment? illustrationAlignment;
  /// Watermark scale override. Falls through to the Rohling default.
  final double? illustrationScale;
  /// Null before the race has been scored.
  final int? scorePoints;
  /// Player name shown in the top-right meta cell (uppercased). When combined
  /// with [dayTime], the two are joined with a centre-dot separator.
  final String? playerName;
  /// Day + local time label, e.g. "SUN 12:00". Renders next to [playerName]
  /// in the top-right meta cell when set.
  final String? dayTime;
  final TicketStyle? styleOverride;
  final VoidCallback? onBodyTap;
  final VoidCallback? onStubTap;
  final VoidCallback? onTap;

  const PickTicket({
    super.key,
    required this.event,
    required this.driverCodes,
    this.p1ConstructorId,
    this.illustration,
    this.illustrationAlignment,
    this.illustrationScale,
    this.scorePoints,
    this.playerName,
    this.dayTime,
    this.styleOverride,
    this.onBodyTap,
    this.onStubTap,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final style = styleOverride ?? styleForEvent(event);
    final scored = scorePoints != null;
    final right = <String>[
      if (playerName != null && playerName!.isNotEmpty) playerName!.toUpperCase(),
      if (dayTime != null && dayTime!.isNotEmpty) dayTime!,
    ].join(' · ');
    return TicketRohling(
      style: style,
      edgeSerial: 'RD ${event.round.toString().padLeft(2, '0')} · ${event.name.toUpperCase()}',
      metaLeft: 'RD ${event.round.toString().padLeft(2, '0')} · ${event.name.toUpperCase()}',
      metaRight: right.isEmpty ? null : right,
      title: event.name.toUpperCase(),
      subtitle: event.circuitName.toUpperCase(),
      illustration: illustration ??
          (p1ConstructorId == null ? null : CarSvg(constructorId: p1ConstructorId)),
      illustrationAlignment: illustrationAlignment ?? Alignment.centerRight,
      illustrationScale: illustrationScale ?? 1.0,
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
