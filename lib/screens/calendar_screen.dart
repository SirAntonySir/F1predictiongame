// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../api/models/event.dart';
import '../api/models/session.dart';
import '../components/race_tile.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  Future<List<Event>>? _events;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _events ??= AppState.of(context).api.events();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        bottom: false,
        child: FutureBuilder<List<Event>>(
          future: _events,
          builder: (_, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) return Center(child: Text('${snap.error}'));
            final events = snap.data!..sort((a, b) => a.round.compareTo(b.round));
            final children = <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(Spacing.xl, Spacing.lg, Spacing.xl, Spacing.xs),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Calendar'.toUpperCase(), style: AppText.display(28)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 5),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.black, width: 1.5),
                        borderRadius: const BorderRadius.all(Radius.circular(999)),
                      ),
                      child: const Text('2026 ▾', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11)),
                    ),
                  ],
                ),
              ),
            ];
            final now = DateTime.now();
            // Find the first event that has any session in the future.
            final firstFutureRound = events
                .where((e) => e.sessions.any((s) => s.scheduledStart.isAfter(now)))
                .map((e) => e.round)
                .fold<int?>(null, (prev, r) => prev == null ? r : (r < prev ? r : prev));

            String? lastMonth;
            for (final e in events) {
              final race = e.sessions.firstWhere(
                (s) => s.type == SessionType.race,
                orElse: () => e.sessions.first,
              );
              final month = DateFormat('MMMM').format(race.scheduledStart);
              if (month != lastMonth) {
                children.add(Padding(
                  padding: const EdgeInsets.fromLTRB(Spacing.xl, Spacing.lg, Spacing.xl, Spacing.xs),
                  child: Row(children: [
                    Text(month.toUpperCase(), style: AppText.label(11)),
                    const SizedBox(width: 10),
                    Expanded(child: Container(height: 1, color: Colors.black.withOpacity(0.15))),
                  ]),
                ));
                lastMonth = month;
              }

              final RaceState raceState;
              if (race.scheduledStart.isAfter(now)) {
                raceState = e.round == firstFutureRound ? RaceState.next : RaceState.future;
              } else {
                raceState = RaceState.past;
              }

              children.add(Padding(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: 5),
                child: RaceTile(
                  round: e.round,
                  country: '${e.country} · ${e.circuitName}',
                  name: e.name.replaceAll('Grand Prix', 'GP'),
                  when: '${DateFormat('d MMM').format(e.sessions.first.scheduledStart)} – ${DateFormat('d MMM').format(race.scheduledStart)}',
                  state: raceState,
                  sprint: e.hasSprint,
                  distanceFromNow: raceState == RaceState.future ? _humanDelta(race.scheduledStart) : null,
                  onTap: () => context.push('/race/${e.round}/${race.id}'),
                ),
              ));
            }
            children.add(const SizedBox(height: Spacing.xxl));
            return SingleChildScrollView(child: Column(children: children));
          },
        ),
      ),
    );
  }

  String _humanDelta(DateTime when) {
    final d = when.difference(DateTime.now()).inDays;
    return 'in ${d}d';
  }
}
