import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../api/models/event.dart';
import '../../api/models/session.dart';
import '../../theme/ticket_style_for_event.dart';
import 'pick_ticket.dart' show kFallbackCarAssets;
import 'ticket_actions_sheet.dart';
import 'ticket_capture.dart';
import 'ticket_rohling.dart';
import 'ticket_stub.dart';
import 'ticket_style.dart';

/// A full-weekend souvenir: the same branded shell as [SouvenirTicket] but the
/// data row summarises each scored session's points (Q +8 · RACE +10) plus a
/// weekend TOTAL, instead of the driver picks. [sessions] is expected in
/// chronological order.
class WeekendSouvenirTicket extends StatelessWidget {
  final Event event;
  final List<({SessionType type, int points})> sessions;
  final int total;
  final Widget? circuitWatermark;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const WeekendSouvenirTicket({
    super.key,
    required this.event,
    required this.sessions,
    required this.total,
    this.circuitWatermark,
    this.onTap,
    this.onLongPress,
  });

  static String _shortLabel(SessionType t) {
    switch (t) {
      case SessionType.qualifying:
        return 'Q';
      case SessionType.sprint_quali:
        return 'SQ';
      case SessionType.sprint:
        return 'SPRINT';
      case SessionType.race:
        return 'RACE';
      case SessionType.fp1:
      case SessionType.fp2:
      case SessionType.fp3:
        return t.name.toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = styleForEvent(event);
    final hasScript = tokensFor(style).scriptAccent != null;
    final title = hasScript
        ? event.name.toUpperCase()
        : '${event.name.toUpperCase()} GP';
    return TicketRohling(
      style: style,
      edgeSerial:
          'WKND ${event.round.toString().padLeft(2, '0')} · ${event.name.toUpperCase()}',
      metaLeft:
          'RD ${event.round.toString().padLeft(2, '0')} · ${event.name.toUpperCase()}',
      metaRight: 'SEALED',
      title: title,
      scriptAccent: hasScript ? 'Grand Prix' : null,
      subtitle: event.circuitName.toUpperCase(),
      illustration: SvgPicture.asset(
        tokensFor(style).defaultIllustrationAsset ??
            kFallbackCarAssets[event.round % kFallbackCarAssets.length],
        fit: BoxFit.contain,
      ),
      secondaryIllustration: circuitWatermark,
      dataRow: [
        for (final s in sessions)
          TicketDataCell(label: _shortLabel(s.type), value: '+${s.points}'),
        TicketDataCell(label: 'TOTAL', value: '+$total'),
      ],
      stub: TicketStub.serialCode('WKND · ${event.round}'),
      // A single tap opens the actions menu (which carries open-details +
      // share); long-press is dropped.
      onTap: () => _showActions(context),
      onLongPress: null,
      leftEdgeSerial: 'WEEKEND',
    );
  }

  void _showActions(BuildContext context) {
    final actions = <TicketAction>[
      if (onTap != null)
        TicketAction(label: 'Open race details', onTap: onTap!),
      TicketAction(
        label: 'Share ticket',
        isShare: true,
        onTap: () => _shareDefault(context),
      ),
    ];
    // ignore: discarded_futures
    showTicketActionsSheet(context, title: event.name, actions: actions);
  }

  void _shareDefault(BuildContext context) {
    final clone = WeekendSouvenirTicket(
      event: event,
      sessions: sessions,
      total: total,
      circuitWatermark: circuitWatermark,
      onLongPress: () {},
    );
    shareBrandedTicket(
      context: context,
      ticket: clone,
      shareText: 'My F1 weekend · ${event.name} · +$total',
      fileName:
          'undercut-weekend-${event.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}.png',
    );
  }
}
