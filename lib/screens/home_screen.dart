// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../api/api_client.dart';
import '../api/models/event.dart';
import '../api/models/session.dart';
import '../api/models/session_result.dart';
import '../components/app_card.dart';
import '../components/countdown.dart';
import '../components/pod_tile.dart';
import '../components/session_chip.dart';
import '../state/app_state.dart';
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
    final events = await api.events();
    Session? next;
    try {
      next = await api.nextSession();
    } on NotFoundException {
      next = null;
    }
    next ??= _computeNextSession(events);
    if (next == null) {
      throw const NotFoundException('next-session');
    }
    final Session resolvedNext = next;
    final nextEvent = events.firstWhere(
      (e) => e.sessions.any((s) => s.id == resolvedNext.id),
      orElse: () => events.first,
    );
    final last = events.lastWhere(
      (e) => e.sessions.any((s) =>
          s.type == SessionType.race && s.status == SessionStatus.finished),
      orElse: () => events.first,
    );
    final lastRace = last.sessions.firstWhere(
      (s) => s.type == SessionType.race,
      orElse: () => last.sessions.first,
    );
    List<SessionResult> lastResult;
    try {
      lastResult = await api.sessionResults(lastRace.id);
    } on NotFoundException {
      lastResult = const [];
    }
    return _HomeData(
      events: events,
      next: resolvedNext,
      nextEvent: nextEvent,
      lastEvent: last,
      lastResult: lastResult,
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
            if (snap.hasError) return Center(child: Text('${snap.error}'));
            final d = snap.data!;
            return ListView(
              padding: const EdgeInsets.fromLTRB(0, Spacing.lg, 0, Spacing.xxl),
              children: [
                _topbar(scope.league.league.name, scope.league.league.players.length),
                const SizedBox(height: Spacing.xs),
                _hero(d, t),
                _section('Your pick', onTap: () => context.go('/predict')),
                _pickCard(d, scope, t),
                _section('Last race · ${d.lastEvent.name}', onTap: () =>
                    context.push('/race/${d.lastEvent.round}/${d.lastEvent.sessions.firstWhere((s) => s.type == SessionType.race).id}')),
                _lastCard(d, t),
                _section('${scope.league.league.name} · Standings', onTap: () => context.go('/standings/league')),
                _leagueCard(scope.league.league.players.map((p) => p.displayName).toList(), scope.auth.currentUserId, t),
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

  Widget _hero(_HomeData d, ThemeData t) {
    final flag = flagFor(d.nextEvent.country);
    final lines = _splitRaceName(d.nextEvent.name);
    final dateLabel = DateFormat('EEE d MMM').format(d.next.scheduledStart);
    final timeLabel = DateFormat('HH:mm').format(d.next.scheduledStart);
    final typeLabel = _sessionTypeLabel(d.next.type);
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
                            '${flag != null ? '$flag  ' : ''}${d.nextEvent.country.toUpperCase()} · ROUND ${d.nextEvent.round}',
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
                      '$dateLabel · $timeLabel · ${d.nextEvent.circuitName}',
                      style: AppText.body(11,
                          color: Colors.white.withOpacity(0.9)),
                    ),
                    const SizedBox(height: Spacing.md),
                    Countdown(target: d.next.scheduledStart, size: 30),
                    const SizedBox(height: Spacing.md),
                    Row(
                      children: _chips(d)
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

  List<Widget> _chips(_HomeData d) {
    final order = [SessionType.fp1, SessionType.fp2, SessionType.fp3,
      SessionType.qualifying, SessionType.sprint_quali, SessionType.sprint, SessionType.race];
    final labels = {
      SessionType.fp1:'FP1', SessionType.fp2:'FP2', SessionType.fp3:'FP3',
      SessionType.qualifying:'QUALI', SessionType.sprint_quali:'SQ',
      SessionType.sprint:'SPRINT', SessionType.race:'RACE',
    };
    return [
      for (final t in order)
        if (d.nextEvent.sessions.any((s) => s.type == t))
          SessionChip(label: labels[t]!, state: d.nextEvent.sessions
              .firstWhere((s) => s.type == t).status == SessionStatus.finished
              ? ChipState.done
              : (d.next.id == d.nextEvent.sessions.firstWhere((s) => s.type == t).id
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
    final userId = scope.auth.currentUserId ?? '';
    final picks =
        scope.predictions.picksFor(userId: userId, sessionId: d.next.id) as List<String>;
    final locked =
        scope.predictions.isLocked(userId: userId, sessionId: d.next.id) as bool;
    final empty = picks.isEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
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
                        ? 'Make your pick · ${d.next.type.name.toUpperCase()}'
                        : '${d.next.type.name.toUpperCase()} · ${locked ? 'locked' : 'draft'}',
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
    );
  }

  Widget _lastCard(_HomeData d, ThemeData t) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
        child: AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Top 3', style: AppText.label(11, color: t.colorScheme.onSurface.withOpacity(0.6))),
                ],
              ),
              const SizedBox(height: Spacing.sm),
              Row(children: [
                for (final r in d.lastResult.take(3))
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: PodTile(position: r.position, driverCode: r.driverCode, constructorId: r.constructorId),
                    ),
                  ),
              ]),
            ],
          ),
        ),
      );

  Widget _leagueCard(List<String> names, String? meId, ThemeData t) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
        child: AppCard(
          child: Column(
            children: List.generate(names.length.clamp(0, 4), (i) {
              final isMe = names[i].toLowerCase() == (meId ?? '');
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(children: [
                      SizedBox(width: 18, child: Text('${i+1}', style: AppText.display(13, color: isMe ? BrandColors.accent : t.colorScheme.onSurface))),
                      const SizedBox(width: 8),
                      Text(isMe ? '${names[i]} (you)' : names[i], style: AppText.body(13, weight: isMe ? FontWeight.w800 : FontWeight.w600)),
                    ]),
                    Text('${(200 - i * 18)}', style: AppText.display(13)),
                  ],
                ),
              );
            }),
          ),
        ),
      );
}

class _HomeData {
  final List<Event> events;
  final Session next;
  final Event nextEvent;
  final Event lastEvent;
  final List<SessionResult> lastResult;
  _HomeData({required this.events, required this.next, required this.nextEvent,
    required this.lastEvent, required this.lastResult});
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
