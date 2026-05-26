// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../api/api_client.dart';
import '../api/models/event.dart';
import '../api/models/leaderboard_row.dart';
import '../api/models/session.dart';
import '../api/models/session_result.dart';
import '../components/app_card.dart';
import '../components/countdown.dart';
import '../components/error_view.dart';
import '../components/pod_tile.dart';
import '../components/session_chip.dart';
import '../domain/scoring.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/country_flags.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Future<_HomeData>? _data;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _data ??= _load(AppState.of(context).api);
  }

  Future<_HomeData> _load(ApiClient api) async {
    final scope = AppState.of(context);
    final events = await api.events();
    final leagues = scope.auth.leagues;
    List<LeaderboardRow> leaderboard = const [];
    if (leagues.isNotEmpty) {
      try {
        leaderboard = await api.leagueLeaderboard(leagues.first.id);
      } catch (_) {
        leaderboard = const [];
      }
    }
    Session? next;
    try {
      next = await api.nextSession();
    } on NotFoundException {
      next = null;
    }
    next ??= _computeNextSession(events);
    Event? nextEvent;
    if (next != null) {
      final resolvedNext = next;
      nextEvent = events.firstWhere(
        (e) => e.sessions.any((s) => s.id == resolvedNext.id),
        orElse: () => events.first,
      );
    }
    final finishedRace = events.lastWhere(
      (e) => e.sessions.any((s) =>
          s.type == SessionType.race && s.status == SessionStatus.finished),
      orElse: () => const Event(
        round: 0,
        name: '',
        country: '',
        circuitName: '',
        hasSprint: false,
        sessions: [],
      ),
    );
    Event? lastEvent;
    Session? lastRaceSession;
    List<SessionResult> lastResult = const [];
    if (finishedRace.sessions.isNotEmpty) {
      lastEvent = finishedRace;
      lastRaceSession = finishedRace.sessions.firstWhere(
        (s) => s.type == SessionType.race,
        orElse: () => finishedRace.sessions.first,
      );
      try {
        lastResult = await api.sessionResults(lastRaceSession.id);
      } on NotFoundException {
        lastResult = const [];
      }
    }
    return _HomeData(
      events: events,
      next: next,
      nextEvent: nextEvent,
      lastEvent: lastEvent,
      lastRaceSession: lastRaceSession,
      lastResult: lastResult,
      leaderboard: leaderboard,
    );
  }

  Session? _computeNextSession(List<Event> events) {
    final now = DateTime.now();
    Session? best;
    for (final e in events) {
      for (final s in e.sessions) {
        if (s.status != SessionStatus.scheduled) continue;
        if (!s.scheduledStart.isAfter(now)) continue;
        if (best == null || s.scheduledStart.isBefore(best.scheduledStart)) {
          best = s;
        }
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final scope = AppState.of(context);
    return Scaffold(
      backgroundColor: t.colorScheme.surface,
      body: SafeArea(
        bottom: false,
        child: FutureBuilder<_HomeData>(
          future: _data,
          builder: (_, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return ErrorView(
                error: snap.error!,
                stack: snap.stackTrace,
                where: 'Home',
                onRetry: () {
                  setState(() {
                    _data = _load(AppState.of(context).api);
                  });
                },
              );
            }
            final d = snap.data!;
            final leagueName = scope.league.league?.name ??
                (scope.auth.leagues.isNotEmpty ? scope.auth.leagues.first.name : 'No league');
            final memberCount = scope.league.league?.members.length ??
                d.leaderboard.length;
            return ListView(
              padding: const EdgeInsets.fromLTRB(0, Spacing.lg, 0, Spacing.xxl),
              children: [
                _topbar(leagueName, memberCount),
                const SizedBox(height: Spacing.xs),
                if (d.next != null && d.nextEvent != null)
                  _hero(d.next!, d.nextEvent!, t)
                else
                  _noNextHero(t),
                if (d.next != null) ...[
                  _section('Your pick',
                      onTap: () => context.go('/predict')),
                  _pickCard(d, scope, t),
                ],
                if (d.lastEvent != null) ...[
                  _section('Last race · ${d.lastEvent!.name}', onTap: () {
                    final race = d.lastEvent!.sessions.firstWhere(
                      (s) => s.type == SessionType.race,
                      orElse: () => d.lastEvent!.sessions.first,
                    );
                    context.push('/race/${d.lastEvent!.round}/${race.id}');
                  }),
                  _lastCard(d, scope, t),
                ],
                _section('$leagueName · Standings',
                    onTap: () => context.go('/standings/league')),
                InkWell(
                  onTap: () => context.go('/standings/league'),
                  child: _leagueCard(d.leaderboard, scope.auth.currentUserId, t),
                ),
                const SizedBox(height: Spacing.xxl),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _topbar(String leagueName, int memberCount) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
        child: Row(
          children: [
            Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3), color: Colors.black,
              child: Text('F1', style: AppText.display(14, color: Colors.white))),
            const SizedBox(width: 4),
            Text('PG', style: AppText.display(14)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 5),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black, width: 1.5),
                borderRadius: const BorderRadius.all(Radius.circular(999)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 8, height: 8, decoration: const BoxDecoration(color: BrandColors.accent, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text('$leagueName · $memberCount', style: AppText.label(11)),
              ]),
            ),
            const SizedBox(width: Spacing.sm),
            IconButton(onPressed: () => context.push('/settings'), icon: const Icon(Icons.settings_outlined)),
          ],
        ),
      );

  Widget _noNextHero(ThemeData t) => Padding(
        padding: const EdgeInsets.fromLTRB(
            Spacing.lg, Spacing.xs, Spacing.lg, 0),
        child: AppCard(
          background: t.mutedSurface,
          padding: const EdgeInsets.symmetric(
              horizontal: Spacing.lg, vertical: Spacing.xxl),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('NO UPCOMING SESSION', style: AppText.label(11)),
                const SizedBox(height: Spacing.sm),
                Text("Season's done — or the schedule hasn't been published.",
                    textAlign: TextAlign.center,
                    style: AppText.body(13,
                        color:
                            t.colorScheme.onSurface.withOpacity(0.7))),
              ],
            ),
          ),
        ),
      );

  Widget _hero(Session next, Event nextEvent, ThemeData t) {
    final flag = flagFor(nextEvent.country);
    final lines = _splitRaceName(nextEvent.name);
    final dateLabel = DateFormat('EEE d MMM').format(next.scheduledStart);
    final timeLabel = DateFormat('HH:mm').format(next.scheduledStart);
    final typeLabel = _sessionTypeLabel(next.type);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xs, Spacing.lg, 0),
      child: AppCard(
        background: BrandColors.accent,
        padding: EdgeInsets.zero,
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _StripesPainter()),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Spacing.xl, Spacing.xl, Spacing.xl, Spacing.xl),
              child: DefaultTextStyle.merge(
                style: const TextStyle(color: Colors.white),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            '${flag != null ? '$flag  ' : ''}${nextEvent.country.toUpperCase()} · ROUND ${nextEvent.round}',
                            style: AppText.label(10,
                                color: Colors.white.withOpacity(0.85)),
                          ),
                        ),
                        const SizedBox(width: Spacing.sm),
                        Text(typeLabel,
                            style: AppText.label(10,
                                color: Colors.white.withOpacity(0.85))),
                      ],
                    ),
                    const SizedBox(height: Spacing.sm),
                    for (final line in lines)
                      Text(line.toUpperCase(),
                          style: AppText.display(30, color: Colors.white)),
                    const SizedBox(height: Spacing.xs),
                    Text(
                      '$dateLabel · $timeLabel · ${nextEvent.circuitName}',
                      style: AppText.body(11,
                          color: Colors.white.withOpacity(0.9)),
                    ),
                    const SizedBox(height: Spacing.md),
                    Countdown(target: next.scheduledStart, size: 30),
                    const SizedBox(height: Spacing.md),
                    Row(
                      children: _chips(next, nextEvent)
                          .map((c) => Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: c))
                          .toList(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<String> _splitRaceName(String name) {
    const tail = ' Grand Prix';
    if (name.endsWith(tail)) {
      return [name.substring(0, name.length - tail.length), 'Grand Prix'];
    }
    return [name];
  }

  String _sessionTypeLabel(SessionType type) {
    switch (type) {
      case SessionType.race:
        return 'RACE';
      case SessionType.qualifying:
        return 'QUALI';
      case SessionType.sprint_quali:
        return 'SPRINT QUALI';
      case SessionType.sprint:
        return 'SPRINT';
      case SessionType.fp1:
      case SessionType.fp2:
      case SessionType.fp3:
        return type.name.toUpperCase();
    }
  }

  List<Widget> _chips(Session next, Event nextEvent) {
    final order = [SessionType.fp1, SessionType.fp2, SessionType.fp3,
      SessionType.qualifying, SessionType.sprint_quali, SessionType.sprint, SessionType.race];
    final labels = {
      SessionType.fp1:'FP1', SessionType.fp2:'FP2', SessionType.fp3:'FP3',
      SessionType.qualifying:'QUALI', SessionType.sprint_quali:'SQ',
      SessionType.sprint:'SPRINT', SessionType.race:'RACE',
    };
    return [
      for (final t in order)
        if (nextEvent.sessions.any((s) => s.type == t))
          SessionChip(label: labels[t]!, state: nextEvent.sessions
              .firstWhere((s) => s.type == t).status == SessionStatus.finished
              ? ChipState.done
              : (next.id == nextEvent.sessions.firstWhere((s) => s.type == t).id
                  ? ChipState.next : ChipState.idle))
    ];
  }

  Widget _section(String title, {VoidCallback? onTap}) => Padding(
        padding: const EdgeInsets.fromLTRB(Spacing.xl, Spacing.xl, Spacing.xl, Spacing.xs),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title.toUpperCase(), style: AppText.label(11)),
            if (onTap != null)
              GestureDetector(onTap: onTap, child: Text('All ›', style: AppText.label(11, color: Colors.black.withOpacity(0.5)))),
          ],
        ),
      );

  Widget _pickCard(_HomeData d, scope, ThemeData t) {
    final sessionId = d.next!.id;
    final picks = scope.predictions.prediction(sessionId)
            ?.picks.map((p) => p.driverCode).toList() ??
        const <String>[];
    final locked = scope.predictions.prediction(sessionId)?.isLocked ?? false;
    final empty = picks.isEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
      child: InkWell(
        onTap: () => context.go('/predict'),
        borderRadius: const BorderRadius.all(Radius.circular(14)),
        child: AppCard(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    empty
                        ? 'Make your pick · ${d.next!.type.name.toUpperCase()}'
                        : '${d.next!.type.name.toUpperCase()} · ${locked ? 'locked' : 'draft'}',
                    style: AppText.label(11, color: t.colorScheme.onSurface.withOpacity(0.6)),
                  ),
                  const SizedBox(height: 6),
                  if (empty)
                    Text('No picks yet', style: AppText.body(13, color: t.colorScheme.onSurface.withOpacity(0.5)))
                  else
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final code in picks)
                          Text(code, style: AppText.body(13, weight: FontWeight.w800)),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(width: Spacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: empty
                    ? BrandColors.accent
                    : (locked ? Colors.black : Colors.transparent),
                border: Border.all(color: Colors.black, width: 1.5),
                borderRadius: const BorderRadius.all(Radius.circular(6)),
              ),
              child: Text(
                empty ? 'PICK' : (locked ? 'LOCKED' : 'EDIT'),
                style: AppText.label(
                  10,
                  color: empty || locked ? Colors.white : Colors.black,
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _lastCard(_HomeData d, scope, ThemeData t) {
    final lastSession = d.lastRaceSession;
    final picks = lastSession == null
        ? const <String>[]
        : scope.predictions.prediction(lastSession.id)
              ?.picks.map((p) => p.driverCode).toList() ??
          const <String>[];
    int score = 0;
    int exactHits = 0;
    if (picks.isNotEmpty && d.lastResult.isNotEmpty) {
      score = scoreRace(picks, d.lastResult);
      for (var i = 0; i < picks.length; i++) {
        if (outcomeFor(picks[i], i + 1, d.lastResult, 5) ==
            PickOutcome.exact) {
          exactHits++;
        }
      }
    }
    final route = lastSession == null || d.lastEvent == null
        ? null
        : '/race/${d.lastEvent!.round}/${lastSession.id}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
      child: InkWell(
        onTap: route == null ? null : () => context.push(route),
        borderRadius: const BorderRadius.all(Radius.circular(14)),
        child: AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Top 3',
                      style: AppText.label(11,
                          color: t.colorScheme.onSurface.withOpacity(0.6))),
                  if (picks.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: const BoxDecoration(
                        color: BrandColors.ok,
                        borderRadius: BorderRadius.all(Radius.circular(6)),
                      ),
                      child: Text('+$score pts · $exactHits exact',
                          style: AppText.label(9, color: Colors.black)),
                    ),
                ],
              ),
              const SizedBox(height: Spacing.sm),
              Row(children: [
                for (final r in d.lastResult.take(3))
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: PodTile(
                        position: r.position,
                        driverCode: r.driverCode,
                        constructorId: r.constructorId,
                        mark: _markFor(picks, r),
                      ),
                    ),
                  ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  PodMark _markFor(List<String> picks, SessionResult r) {
    if (picks.isEmpty) return PodMark.none;
    final slotIndex = r.position - 1;
    if (slotIndex >= picks.length) return PodMark.none;
    return picks[slotIndex] == r.driverCode ? PodMark.exact : PodMark.miss;
  }

  Widget _leagueCard(List<LeaderboardRow> rows, String? meId, ThemeData t) {
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
        child: AppCard(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Spacing.md),
            child: Text(
              'Leaderboard will fill in as sessions finish.',
              style: AppText.body(12, color: t.colorScheme.onSurface.withOpacity(0.6)),
            ),
          ),
        ),
      );
    }
    final preview = rows.take(4).toList();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
      child: AppCard(
        child: Column(
          children: List.generate(preview.length, (i) {
            final r = preview[i];
            final isMe = r.userId == meId;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(children: [
                    SizedBox(width: 18, child: Text('${i + 1}', style: AppText.display(13, color: isMe ? BrandColors.accent : t.colorScheme.onSurface))),
                    const SizedBox(width: 8),
                    Text(isMe ? '${r.displayName} (you)' : r.displayName, style: AppText.body(13, weight: isMe ? FontWeight.w800 : FontWeight.w600)),
                  ]),
                  Text('${r.pointsTotal}', style: AppText.display(13)),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _HomeData {
  final List<Event> events;
  final Session? next;
  final Event? nextEvent;
  final Event? lastEvent;
  final Session? lastRaceSession;
  final List<SessionResult> lastResult;
  final List<LeaderboardRow> leaderboard;
  _HomeData({
    required this.events,
    required this.next,
    required this.nextEvent,
    required this.lastEvent,
    required this.lastRaceSession,
    required this.lastResult,
    required this.leaderboard,
  });
}

class _StripesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withOpacity(0.13);
    const stripe = 6.0;
    const gap = 10.0;
    const step = stripe + gap;
    final diagonal = size.width + size.height;
    for (var d = -size.height; d < diagonal; d += step) {
      final path = Path()
        ..moveTo(d, 0)
        ..lineTo(d + stripe, 0)
        ..lineTo(d + stripe + size.height, size.height)
        ..lineTo(d + size.height, size.height)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_StripesPainter old) => false;
}
