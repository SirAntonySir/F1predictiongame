import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../api/models/event.dart';
import '../../api/models/session.dart';
import '../../theme/ticket_style_for_event.dart';
import 'pick_ticket.dart' show kFallbackCarAssets;
import 'ticket_capture.dart';
import 'ticket_rohling.dart';
import 'ticket_session_badge.dart';
import 'ticket_stub.dart';
import 'ticket_style.dart';

/// Shareable souvenir ticket. More decorated than [PickTicket]: always uses
/// the crossed-flags ornament regardless of preset, shows a qualitative grade
/// in addition to the raw points, and uses the long-form title.
class SouvenirTicket extends StatelessWidget {
  final Event event;
  final List<String> driverCodes;
  final String? p1ConstructorId;
  /// Optional pre-built illustration override (see [PickTicket.illustration]).
  final Widget? illustration;
  final Alignment? illustrationAlignment;
  final double? illustrationScale;
  final Widget? circuitWatermark;
  final int scorePoints;
  final TicketStyle? styleOverride;
  /// When set, a colored diagonal sash badge appears on the top-right corner
  /// flagging the session type (RACE / QUALI / SPRINT…). See [PickTicket].
  final SessionType? sessionType;
  /// 0-based pick slot indices that were exact-correct (driver landed on the
  /// finishing position they were picked for). Each matching slot in the
  /// dataRow gets a hand-drawn tick painted on top.
  final Set<int> correctSlots;
  /// Long-press handler. Defaults to sharing this ticket as a branded PNG.
  /// Pass `() {}` to disable.
  final VoidCallback? onLongPress;
  final VoidCallback? onTap;

  const SouvenirTicket({
    super.key,
    required this.event,
    required this.driverCodes,
    required this.scorePoints,
    this.p1ConstructorId,
    this.illustration,
    this.illustrationAlignment,
    this.illustrationScale,
    this.circuitWatermark,
    this.styleOverride,
    this.sessionType,
    this.correctSlots = const {},
    this.onLongPress,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final style = styleOverride ?? styleForEvent(event);
    final sessionLabel = ticketSessionLabel(sessionType);
    // Variants with a [scriptAccent] style render "Grand Prix" as italic
    // script under the title; everyone else keeps the plain " GP" suffix
    // baked into the title for back-compat with the original three paper
    // variants.
    final hasScript = tokensFor(style).scriptAccent != null;
    final title = hasScript
        ? event.name.toUpperCase()
        : '${event.name.toUpperCase()} GP';
    return TicketRohling(
      style: style,
      edgeSerial: 'PICK ${event.round.toString().padLeft(2, '0')} · ${event.name.toUpperCase()}',
      metaLeft: 'RD ${event.round.toString().padLeft(2, '0')} · ${event.name.toUpperCase()}',
      metaRight: 'SEALED',
      title: title,
      scriptAccent: hasScript ? 'Grand Prix' : null,
      subtitle: event.circuitName.toUpperCase(),
      // Watermark resolution matches [PickTicket]: caller override →
      // variant's signature artwork (TicketStyleTokens.defaultIllustrationAsset)
      // → round-keyed generic silhouette. Keeps the souvenir, pick ticket,
      // and dev preview in lockstep for any given style.
      illustration: illustration ??
          SvgPicture.asset(
            tokensFor(style).defaultIllustrationAsset ??
                kFallbackCarAssets[event.round % kFallbackCarAssets.length],
            fit: BoxFit.contain,
          ),
      // Forward overrides or null so TicketRohling's file-level defaults
      // (line ~17 of ticket_rohling.dart) actually take effect.
      illustrationAlignment: illustrationAlignment,
      illustrationScale: illustrationScale,
      secondaryIllustration: circuitWatermark,
      // Use the variant's natural ornament so each new vintage style gets
      // its signature mark (car / trophy / checkered / crown). Previously
      // hardcoded crossedFlags, which silently neutered every variant's
      // ornament choice in the wallet.
      dataRow: [
        for (var i = 0; i < driverCodes.length && i < 5; i++)
          TicketDataCell(
            label: 'P${i + 1}',
            value: driverCodes[i],
            marked: correctSlots.contains(i),
          ),
        TicketDataCell(label: 'POINTS', value: '+$scorePoints'),
      ],
      stub: TicketStub.serialCode('PICK · ${event.round}'),
      onTap: onTap,
      onLongPress: onLongPress ?? () => _shareDefault(context),
      leftEdgeSerial: sessionLabel,
    );
  }

  void _shareDefault(BuildContext context) {
    final clone = SouvenirTicket(
      event: event,
      driverCodes: driverCodes,
      scorePoints: scorePoints,
      p1ConstructorId: p1ConstructorId,
      illustration: illustration,
      illustrationAlignment: illustrationAlignment,
      illustrationScale: illustrationScale,
      circuitWatermark: circuitWatermark,
      styleOverride: styleOverride,
      sessionType: sessionType,
      correctSlots: correctSlots,
      onLongPress: () {},
    );
    shareBrandedTicket(
      context: context,
      ticket: clone,
      shareText: 'My F1 souvenir · ${event.name} · +$scorePoints',
      fileName: 'f1pg-souvenir-${event.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}.png',
    );
  }
}
