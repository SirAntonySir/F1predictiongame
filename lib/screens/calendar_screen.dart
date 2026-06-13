// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:skeletonizer/skeletonizer.dart';
import '../api/models/event.dart';
import '../api/models/session.dart';
import '../domain/race_phase.dart';
import '../components/cached_view.dart';
import '../components/race_tile.dart';
import '../state/app_state.dart';
import '../state/async_cache.dart';
import '../theme/country_flags.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late final AsyncCache<_CalData> _cache = AsyncCache<_CalData>(_fetch);
  final ScrollController _scroll = ScrollController();
  // GlobalKey attached to the live tile (or the next race when nothing is
  // live) so we can jump-scroll to it on first load.
  final GlobalKey _nextRaceKey = GlobalKey();
  bool _scrolledToNext = false;
  bool _kickedOffRefresh = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_kickedOffRefresh) {
      _kickedOffRefresh = true;
      // ignore: discarded_futures
      _cache.refresh();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _cache.dispose();
    super.dispose();
  }

  Future<_CalData> _fetch() async {
    final scope = AppState.of(context);
    final events = await scope.api.events();
    events.sort((a, b) => a.round.compareTo(b.round));
    // Pull the backend's authoritative scores for the caller, then aggregate
    // per event round. Single round-trip; no per-session prediction fetches.
    await scope.predictions.refreshScores();
    final points = <int, int>{};
    for (final sid in scope.predictions.allScoreIds) {
      final s = scope.predictions.score(sid);
      if (s == null) continue;
      points.update(s.eventRound, (v) => v + s.pointsTotal, ifAbsent: () => s.pointsTotal);
    }
    return _CalData(events: events, pointsByRound: points);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        bottom: false,
        child: CachedView<_CalData>(
          cache: _cache,
          placeholder: _CalData.placeholder(),
          where: 'Calendar',
          builder: (_, data) {
            final events = data.events;
            final children = <Widget>[
              // Header is purely structural — keep visible during skeleton
              // so the user has a stable anchor while data loads.
              Skeleton.keep(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                      Spacing.xl, Spacing.lg, Spacing.xl, Spacing.xs),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Calendar'.toUpperCase(),
                          style: AppText.display(28)),
                      // Static season label — only 2026 exists, so no dropdown
                      // affordance. Bring back the chevron + tap handler if/when
                      // a second season ships.
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: Spacing.md, vertical: 5),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.black, width: 1.5),
                          borderRadius:
                              const BorderRadius.all(Radius.circular(999)),
                        ),
                        child: const Text('2026',
                            style: TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 11)),
                      ),
                    ],
                  ),
                ),
              ),
            ];
            final now = DateTime.now();
            final phases = classifyCalendar(events, now);
            // Scroll target: the live event if there is one, otherwise the next
            // race — derived from the same classification the tiles render.
            int? liveRound;
            int? nextRound;
            phases.forEach((round, st) {
              if (st == RaceState.live) liveRound = round;
              if (st == RaceState.next) nextRound = round;
            });
            final scrollRound = liveRound ?? nextRound;

            // Bucket events by month so the layout builder can pair tiles
            // within each month on wide viewports (iPad → 2-up rows).
            final monthOrder = <String>[];
            final byMonth = <String, List<Widget>>{};
            for (final e in events) {
              final race = e.sessions.firstWhere(
                (s) => s.type == SessionType.race,
                orElse: () => e.sessions.first,
              );
              final month = DateFormat('MMMM').format(race.scheduledStart);
              if (!byMonth.containsKey(month)) {
                monthOrder.add(month);
                byMonth[month] = <Widget>[];
              }

              final raceState = phases[e.round] ?? RaceState.future;

              final pts = raceState == RaceState.past
                  ? (data.pointsByRound[e.round] ?? 0)
                  : null;

              byMonth[month]!.add(RaceTile(
                // Tag the next race's tile so the post-frame callback below
                // can scroll the list to it.
                key: e.round == scrollRound ? _nextRaceKey : null,
                round: e.round,
                event: e,
                flag: flagFor(e.country),
                country: '${e.country} · ${e.circuitName}',
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
              ));
            }

            Widget monthDivider(String month) => Padding(
                  padding: const EdgeInsets.fromLTRB(
                      Spacing.xl, Spacing.lg, Spacing.xl, Spacing.xs),
                  child: Row(children: [
                    Text(month.toUpperCase(), style: AppText.label(11)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Container(
                            height: 1, color: Colors.black.withOpacity(0.15))),
                  ]),
                );

            children.add(LayoutBuilder(
              builder: (ctx, constraints) {
                final twoCol = constraints.maxWidth >= 700;
                final items = <Widget>[];
                for (final month in monthOrder) {
                  items.add(monthDivider(month));
                  final tiles = byMonth[month]!;
                  if (!twoCol) {
                    for (final tile in tiles) {
                      items.add(Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: Spacing.lg, vertical: 5),
                        child: tile,
                      ));
                    }
                  } else {
                    for (var i = 0; i < tiles.length; i += 2) {
                      final left = tiles[i];
                      final right = i + 1 < tiles.length ? tiles[i + 1] : null;
                      items.add(Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: Spacing.lg, vertical: 5),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: left),
                            const SizedBox(width: Spacing.sm),
                            Expanded(
                              child: right ?? const SizedBox.shrink(),
                            ),
                          ],
                        ),
                      ));
                    }
                  }
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: items,
                );
              },
            ));
            children.add(const SizedBox(height: Spacing.xxl));
            // Auto-scroll to the "next" race on first build. Runs once per
            // mount; subsequent rebuilds (e.g. on scroll) skip the jump so
            // the user can scroll freely past it. Skipped while we're still
            // showing the placeholder data — would scroll to fake content.
            if (!_scrolledToNext && scrollRound != null && _cache.data != null) {
              _scrolledToNext = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                final ctx = _nextRaceKey.currentContext;
                if (ctx == null || !_scroll.hasClients) return;
                Scrollable.ensureVisible(
                  ctx,
                  // 0.1 puts the next-race tile just below the header
                  // instead of pinned to the very top of the viewport.
                  alignment: 0.1,
                  duration: const Duration(milliseconds: 350),
                );
              });
            }
            return SingleChildScrollView(
              controller: _scroll,
              child: Column(children: children),
            );
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

  /// Synthetic 8-race calendar across the next few months — enough rows to
  /// fill the scrollview with skeleton tiles. Real values get replaced once
  /// [AsyncCache] hands us the live payload.
  factory _CalData.placeholder() {
    final now = DateTime.now();
    final events = <Event>[];
    for (var i = 0; i < 8; i++) {
      final start = DateTime(now.year, now.month + i ~/ 2, 1 + (i % 2) * 14, 14);
      events.add(Event(
        round: i + 1,
        name: 'Loading Grand Prix',
        country: 'XX',
        circuitName: 'Loading Circuit',
        hasSprint: i.isEven,
        sessions: [
          Session(
            id: i * 5,
            type: SessionType.race,
            scheduledStart: start.add(const Duration(days: 2)),
            scheduledEnd: start.add(const Duration(days: 2, hours: 2)),
            status: SessionStatus.scheduled,
          ),
          Session(
            id: i * 5 + 1,
            type: SessionType.qualifying,
            scheduledStart: start.add(const Duration(days: 1)),
            scheduledEnd: start.add(const Duration(days: 1, hours: 1)),
            status: SessionStatus.scheduled,
          ),
        ],
      ));
    }
    return _CalData(events: events, pointsByRound: const {});
  }
}
