// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../api/models/event.dart';
import '../components/ticket/pick_ticket.dart';
import '../components/ticket/souvenir_ticket.dart';
import '../components/ticket/ticket_rohling.dart';
import '../components/ticket/ticket_style.dart';

/// Dev-only preview screen showing every ticket variant × style combination
/// against fixed sample data. Reach it at /dev/tickets.
class DevTicketsScreen extends StatelessWidget {
  const DevTicketsScreen({super.key});

  static const _picks = ['VER', 'NOR', 'LEC', 'HAM', 'PIA'];
  static const _scorePoints = 18;

  // Three sample events, each chosen to exercise a different default style
  // via styleForEvent. The lists also act as a smoke-test for the heritage
  // and night mappings.
  static const _events = <_Sample>[
    _Sample(
      label: 'Monaco GP (heritage → vintageStencil)',
      style: TicketStyle.vintageStencil,
      event: Event(
        round: 7,
        name: 'Monaco',
        country: 'Monaco',
        circuitName: 'Circuit de Monaco',
        hasSprint: false,
        sessions: [],
      ),
    ),
    _Sample(
      label: 'Bahrain GP (default → posterSprint)',
      style: TicketStyle.posterSprint,
      event: Event(
        round: 1,
        name: 'Bahrain',
        country: 'Bahrain',
        circuitName: 'Bahrain International Circuit',
        hasSprint: false,
        sessions: [],
      ),
    ),
    _Sample(
      label: 'Las Vegas GP (night → darkBoardingPass)',
      style: TicketStyle.darkBoardingPass,
      event: Event(
        round: 22,
        name: 'Las Vegas',
        country: 'USA',
        circuitName: 'Las Vegas Strip Circuit',
        hasSprint: false,
        sessions: [],
      ),
    ),
  ];

  /// Tinted SVG widget for the watermark slot. Each style preset picks a
  /// different sample car so the dev screen also doubles as a "do all three
  /// SVGs render correctly" smoke test.
  Widget _sampleCar(TicketStyle style) {
    final ink = style == TicketStyle.darkBoardingPass
        ? const Color(0xFFF1DD95)
        : const Color(0xFF1B1206);
    final asset = switch (style) {
      TicketStyle.vintageStencil   => 'assets/dev_car_b.svg',       // vintage open-wheel
      TicketStyle.posterSprint     => 'assets/dev_car_outline.svg', // modern silhouette
      TicketStyle.darkBoardingPass => 'assets/dev_car_c.svg',       // alt silhouette
    };
    return SvgPicture.asset(
      asset,
      fit: BoxFit.contain,
      colorFilter: ColorFilter.mode(ink, BlendMode.srcIn),
    );
  }

  /// Default watermark alignment per preset — keeps the silhouette out of the
  /// title's reading column while feeling intentional to each style.
  Alignment _alignFor(TicketStyle style) => switch (style) {
        TicketStyle.vintageStencil => Alignment.centerRight,
        TicketStyle.posterSprint => Alignment.bottomLeft,
        TicketStyle.darkBoardingPass => Alignment.center,
      };

  /// Per-preset scale tweaks: tighter crop on vintage so the car reads as
  /// detailed; bigger bleed on dark so the silhouette dominates.
  double _scaleFor(TicketStyle style) => switch (style) {
        TicketStyle.vintageStencil => 0.95,
        TicketStyle.posterSprint => 1.1,
        TicketStyle.darkBoardingPass => 1.3,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ticket preview')),
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _section(context, 'Style presets · PickTicket (pre-race)'),
            for (final s in _events) ...[
              _label(context, '${s.label} · PickTicket pre-race'),
              const SizedBox(height: 6),
              PickTicket(
                event: s.event,
                driverCodes: _picks,
                illustration: _sampleCar(s.style),
                illustrationAlignment: _alignFor(s.style),
                illustrationScale: _scaleFor(s.style),
              ),
              const SizedBox(height: 18),
            ],
            _section(context, 'PickTicket (post-race, scored)'),
            for (final s in _events) ...[
              _label(context, '${s.label} · PickTicket scored'),
              const SizedBox(height: 6),
              PickTicket(
                event: s.event,
                driverCodes: _picks,
                scorePoints: _scorePoints,
                illustration: _sampleCar(s.style),
                illustrationAlignment: _alignFor(s.style),
                illustrationScale: _scaleFor(s.style),
              ),
              const SizedBox(height: 18),
            ],
            _section(context, 'SouvenirTicket'),
            for (final s in _events) ...[
              _label(context, '${s.label} · Souvenir (28 pts)'),
              const SizedBox(height: 6),
              SouvenirTicket(
                event: s.event,
                driverCodes: _picks,
                scorePoints: 28,
                illustration: _sampleCar(s.style),
                illustrationAlignment: _alignFor(s.style),
                illustrationScale: _scaleFor(s.style),
              ),
              const SizedBox(height: 18),
            ],
            _section(context, 'Alignment matrix · poster preset, three positions'),
            for (final pos in const <(String, Alignment)>[
              ('centerLeft', Alignment.centerLeft),
              ('center', Alignment.center),
              ('centerRight', Alignment.centerRight),
            ]) ...[
              _label(context, 'alignment: ${pos.$1}'),
              const SizedBox(height: 6),
              TicketRohling(
                style: TicketStyle.posterSprint,
                edgeSerial: 'RD 07 · MONACO',
                metaLeft: 'RD 07 · MONACO',
                metaRight: 'SUN 12:00',
                title: 'MONACO',
                subtitle: 'CIRCUIT DE MONACO',
                illustration: _sampleCar(TicketStyle.posterSprint),
                illustrationAlignment: pos.$2,
                illustrationScale: 1.1,
                dataRow: const [
                  TicketDataCell(label: 'P1', value: 'VER'),
                  TicketDataCell(label: 'P2', value: 'NOR'),
                  TicketDataCell(label: 'STATUS', value: 'LOCKED'),
                ],
                stub: tokensFor(TicketStyle.posterSprint).defaultStub,
              ),
              const SizedBox(height: 18),
            ],
            _section(context, 'Raw Rohling (all three styles, per-preset car + alignment)'),
            for (final style in TicketStyle.values) ...[
              _label(context, style.name),
              const SizedBox(height: 6),
              TicketRohling(
                style: style,
                edgeSerial: 'RD 07 · MONACO',
                metaLeft: 'RD 07 · MONACO',
                metaRight: 'SUN 12:00',
                title: 'MONACO',
                subtitle: 'CIRCUIT DE MONACO',
                illustration: _sampleCar(style),
                illustrationAlignment: _alignFor(style),
                illustrationScale: _scaleFor(style),
                dataRow: const [
                  TicketDataCell(label: 'P1', value: 'VER'),
                  TicketDataCell(label: 'P2', value: 'NOR'),
                  TicketDataCell(label: 'STATUS', value: 'LOCKED'),
                ],
                stub: tokensFor(style).defaultStub,
              ),
              const SizedBox(height: 18),
            ],
          ],
        ),
      ),
    );
  }

  Widget _section(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 12),
        child: Text(
          text,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
        ),
      );

  Widget _label(BuildContext context, String text) => Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
      );
}

class _Sample {
  final String label;
  final TicketStyle style;
  final Event event;
  const _Sample({required this.label, required this.style, required this.event});
}
