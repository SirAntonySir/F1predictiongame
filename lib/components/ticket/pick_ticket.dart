import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../api/models/event.dart';
import '../../api/models/session.dart';
import '../../theme/ticket_style_for_event.dart';
import 'ticket_actions_sheet.dart';
import 'ticket_capture.dart';
import 'ticket_rohling.dart';
import 'ticket_session_badge.dart';
import 'ticket_stub.dart';
import 'ticket_style.dart';

/// Event-keyed fallback car silhouettes — used when no [p1ConstructorId] is
/// known yet (pre-pick). Different events get different shapes so a wall of
/// fresh tickets isn't a single repeated silhouette.
const kFallbackCarAssets = <String>[
  'assets/dev_car_outline.svg',
  'assets/dev_car_b.svg',
  'assets/dev_car_c.svg',
];

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

  /// Optional circuit-outline widget layered behind [illustration].
  final Widget? circuitWatermark;

  /// Null before the race has been scored.
  final int? scorePoints;

  /// Player name shown in the top-right meta cell (uppercased). When combined
  /// with [dayTime], the two are joined with a centre-dot separator.
  final String? playerName;

  /// Day + local time label, e.g. "SUN 12:00". Renders next to [playerName]
  /// in the top-right meta cell when set.
  final String? dayTime;

  /// Replaces the default `STATUS = LOCKED` cell when set. Used to render
  /// `DRAFT`, `NO PICKS`, `OPEN`, etc. when the ticket isn't yet locked or
  /// scored. Ignored once [scorePoints] is set — the score takes priority.
  final String? statusOverride;
  final TicketStyle? styleOverride;
  /// When set, a colored diagonal sash badge appears on the top-right corner
  /// flagging the session type (RACE / QUALI / SPRINT…). Lets the ticket
  /// identify the session at a glance without stealing space from the body.
  final SessionType? sessionType;
  final VoidCallback? onBodyTap;
  final VoidCallback? onStubTap;
  final VoidCallback? onTap;

  /// Long-press handler. When omitted, defaults to sharing this ticket as a
  /// branded PNG via [shareBrandedTicket]. Pass `() {}` (a no-op) to disable
  /// the default share without providing an alternative.
  final VoidCallback? onLongPress;

  const PickTicket({
    super.key,
    required this.event,
    required this.driverCodes,
    this.p1ConstructorId,
    this.illustration,
    this.illustrationAlignment,
    this.illustrationScale,
    this.circuitWatermark,
    this.scorePoints,
    this.playerName,
    this.dayTime,
    this.statusOverride,
    this.styleOverride,
    this.sessionType,
    this.onBodyTap,
    this.onStubTap,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final style = styleOverride ?? styleForEvent(event);
    final scored = scorePoints != null;
    final sessionLabel = ticketSessionLabel(sessionType);
    final hasScript = tokensFor(style).scriptAccent != null;
    final right = <String>[
      if (playerName != null && playerName!.isNotEmpty)
        playerName!.toUpperCase(),
      if (dayTime != null && dayTime!.isNotEmpty) dayTime!,
    ].join(' · ');
    return TicketRohling(
      style: style,
      edgeSerial:
          'RD ${event.round.toString().padLeft(2, '0')} · ${event.name.toUpperCase()}',
      metaLeft:
          'RD ${event.round.toString().padLeft(2, '0')} · ${event.name.toUpperCase()}',
      metaRight: right.isEmpty ? null : right,
      title: event.name.toUpperCase(),
      scriptAccent: hasScript ? 'Grand Prix' : null,
      subtitle: event.circuitName.toUpperCase(),
      // Illustration resolution (in priority order):
      //   1. Caller-supplied [illustration] (dev preview, tests, future
      //      constructor-car-svg backed override).
      //   2. The active style's signature watermark from
      //      [TicketStyleTokens.defaultIllustrationAsset] — e.g. the car for
      //      Mustard City Cup, checkered flag for Olive State Cup, crown for
      //      Rose Championship. Keeps the variant readable across souvenir
      //      wallet, home pick card, and dev preview.
      //   3. Round-keyed fallback silhouette so consecutive rounds don't
      //      repeat and the styles with no signature artwork still get one.
      illustration: illustration ??
          SvgPicture.asset(
            tokensFor(style).defaultIllustrationAsset ??
                kFallbackCarAssets[event.round % kFallbackCarAssets.length],
            fit: BoxFit.contain,
          ),
      // Forward overrides or null so editing TicketRohling's defaults
      // actually changes the rendered ticket. Rohling resolves null to its
      // own defaults inside build().
      illustrationAlignment: illustrationAlignment,
      illustrationScale: illustrationScale,
      secondaryIllustration: circuitWatermark,
      dataRow: [
        for (var i = 0; i < driverCodes.length && i < 5; i++)
          TicketDataCell(label: 'P${i + 1}', value: driverCodes[i]),
        TicketDataCell(
          label: 'STATUS',
          value: scored ? '+${scorePoints!}' : (statusOverride ?? 'LOCKED'),
        ),
      ],
      stub: scored
          ? TicketStub.serialCode('PICK · ${event.round}')
          : tokensFor(style).defaultStub,
      onTap: onTap,
      onBodyTap: onBodyTap,
      onStubTap: onStubTap,
      onLongPress: onLongPress ?? () => _showActions(context),
      leftEdgeSerial: sessionLabel,
    );
  }

  /// Long-press menu: the navigation rows the call site wired up (open race
  /// details / edit pick), plus the branded-PNG share. Only callbacks that were
  /// actually provided become rows, so e.g. the results screen (stub-tap only)
  /// shows just "Edit pick" + "Share ticket".
  void _showActions(BuildContext context) {
    final actions = <TicketAction>[
      if (onBodyTap != null)
        TicketAction(label: 'Open race details', onTap: onBodyTap!)
      else if (onTap != null)
        TicketAction(label: 'Open race details', onTap: onTap!),
      if (onStubTap != null)
        TicketAction(label: 'Edit pick', onTap: onStubTap!),
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
    // Rebuild a tap-less clone so the captured image doesn't carry ink-well
    // highlights from a press in flight, and so a long-press inside the
    // captured overlay can't recurse into another share. The visual props
    // (style, watermarks, picks, status) all carry through.
    final clone = PickTicket(
      event: event,
      driverCodes: driverCodes,
      p1ConstructorId: p1ConstructorId,
      illustration: illustration,
      illustrationAlignment: illustrationAlignment,
      illustrationScale: illustrationScale,
      circuitWatermark: circuitWatermark,
      scorePoints: scorePoints,
      playerName: playerName,
      dayTime: dayTime,
      statusOverride: statusOverride,
      styleOverride: styleOverride,
      sessionType: sessionType,
      onLongPress: () {},
    );
    shareBrandedTicket(
      context: context,
      ticket: clone,
      shareText: 'My F1 prediction · ${event.name}',
      fileName:
          'f1pg-${event.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}.png',
    );
  }
}
