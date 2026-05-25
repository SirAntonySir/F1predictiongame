// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../api/api_client.dart';
import '../api/models/event.dart';
import '../api/models/session.dart';
import '../api/models/session_result.dart';
import '../components/error_view.dart';
import '../components/race_tile.dart';
import '../domain/scoring.dart';
import '../state/app_state.dart';
import '../theme/country_flags.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  Future<_CalData>? _data;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _data ??= _load();
  }

  Future<_CalData> _load() async {
    final scope = AppState.of(context);
    final events = await scope.api.events();
    events.sort((a, b) => a.round.compareTo(b.round));
    final userId = scope.auth.currentUserId ?? '';
    final points = <int, int>{};
    for (final e in events) {
      final raceFinished = e.sessions.any(
          (s) => s.type == SessionType.race && s.status == SessionStatus.finished);
      if (!raceFinished) continue;
      int total = 0;
      for (final s in e.sessions) {
        if (s.status != SessionStatus.finished) continue;
        final picks =
            scope.predictions.picksFor(userId: userId, sessionId: s.id);
        if (picks.isEmpty) continue;
        try {
          final r = await scope.api.sessionResults(s.id);
          total += _scoreFor(s.type, picks, r);
        } on NotFoundException {
          // no results published yet — skip
        }
      }
      points[e.round] = total;
    }
    return _CalData(events: events, pointsByRound: points);
  }

  int _scoreFor(
      SessionType type, List<String> picks, List<SessionResult> result) {
    switch (type) {
      case SessionType.qualifying:
        return scoreQualifying(picks, result);
      case SessionType.sprint_quali:
        return scoreSprintQualifying(picks, result);
      case SessionType.sprint:
        return scoreSprint(picks, result);
      case SessionType.race:
        return scoreRace(picks, result);
      default:
        return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        bottom: false,
        child: FutureBuilder<_CalData>(
          future: _data,
          builder: (_, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const SizedBox.shrink();
            }
            if (snap.hasError) {
              return ErrorView(
                error: snap.error!,
                stack: snap.stackTrace,
                where: 'Calendar',
                onRetry: () {
                  setState(() {
                    _data = _load();
                  });
                },
              );
            }
            final data = snap.data!;
            final events = data.events;
            final children = <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    Spacing.xl, Spacing.lg, Spacing.xl, Spacing.xs),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Calendar'.toUpperCase(),
                        style: AppText.display(28)),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: Spacing.md, vertical: 5),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.black, width: 1.5),
                        borderRadius:
                            const BorderRadius.all(Radius.circular(999)),
                      ),
                      child: const Text('2026 ▾',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 11)),
                    ),
                  ],
                ),
              ),
            ];
            final now = DateTime.now();
            final firstFutureRound = events
                .where(
                    (e) => e.sessions.any((s) => s.scheduledStart.isAfter(now)))
                .map((e) => e.round)
                .fold<int?>(null,
                    (prev, r) => prev == null ? r : (r < prev ? r : prev));

            String? lastMonth;
            for (final e in events) {
              final race = e.sessions.firstWhere(
                (s) => s.type == SessionType.race,
                orElse: () => e.sessions.first,
              );
              final month = DateFormat('MMMM').format(race.scheduledStart);
              if (month != lastMonth) {
                children.add(Padding(
                  padding: const EdgeInsets.fromLTRB(
                      Spacing.xl, Spacing.lg, Spacing.xl, Spacing.xs),
                  child: Row(children: [
                    Text(month.toUpperCase(), style: AppText.label(11)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Container(
                            height: 1, color: Colors.black.withOpacity(0.15))),
                  ]),
                ));
                lastMonth = month;
              }

              final RaceState raceState;
              if (race.scheduledStart.isAfter(now)) {
                raceState = e.round == firstFutureRound
                    ? RaceState.next
                    : RaceState.future;
              } else {
                raceState = RaceState.past;
              }

              final pts = raceState == RaceState.past
                  ? (data.pointsByRound[e.round] ?? 0)
                  : null;

              children.add(Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.lg, vertical: 5),
                child: RaceTile(
                  round: e.round,
                  country: () {
                    final flag = flagFor(e.country);
                    return '${flag != null ? '$flag  ' : ''}${e.country} · ${e.circuitName}';
                  }(),
                  name: e.name.replaceAll('Grand Prix', 'GP'),
                  when:
                      '${DateFormat('d MMM').format(e.sessions.first.scheduledStart)} – ${DateFormat('d MMM').format(race.scheduledStart)}',
                  state: raceState,
                  sprint: e.hasSprint,
                  pointsScored: pts,
                  distanceFromNow: raceState == RaceState.future
                      ? _humanDelta(race.scheduledStart)
                      : null,
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

class _CalData {
  final List<Event> events;
  final Map<int, int> pointsByRound;
  _CalData({required this.events, required this.pointsByRound});
}
