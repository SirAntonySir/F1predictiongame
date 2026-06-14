// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import '../api/models/event.dart';
import '../components/ticket/pick_ticket.dart';
import '../components/ticket/souvenir_ticket.dart';
import '../components/ticket/ticket_rohling.dart';
import '../components/ticket/ticket_style.dart';

/// Dev-only preview screen showing every ticket variant × style combination
/// against fixed sample data. Reach it at /dev/tickets.
class DevTicketsScreen extends StatelessWidget {
  const DevTicketsScreen({super.key});

  static const _picks = ['VER', 'NOR', 'LEC'];
  static const _scorePoints = 18;

  // Three sample events, each chosen to exercise a different default style
  // via styleForEvent. The lists also act as a smoke-test for the heritage
  // and night mappings.
  static const _events = <_Sample>[
    _Sample(
      label: 'Monaco GP (heritage → vintageStencil)',
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
              ),
              const SizedBox(height: 18),
            ],
            _section(context, 'Raw Rohling (all three styles, identical content)'),
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
  final Event event;
  const _Sample({required this.label, required this.event});
}
