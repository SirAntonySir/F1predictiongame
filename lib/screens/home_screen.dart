// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../api/api_client.dart';
import '../api/models/event.dart';
import '../api/models/leaderboard_row.dart';
import '../api/models/prediction_view.dart';
import '../api/models/session.dart';
import '../api/models/session_result.dart';
import '../components/app_card.dart';
import '../components/countdown.dart';
import '../components/error_view.dart';
import '../components/pod_tile.dart';
import '../components/racing_stripes.dart';
import '../components/session_chip.dart';
import '../components/ticket_card.dart';
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
    // The hero shows the chronologically next session (any type — FP1 counts).
    // The pick card needs the next *pickable* session (quali / SQ / sprint /
    // race) so it doesn't say "Make your pick · FP1". We resolve both here.
    Session? next;
    try {
      next = await api.nextSession();
    } on NotFoundException {
      next = null;
    }
    next ??= _computeNextSession(events, pickableOnly: false);
    final nextPickable = _computeNextSession(events, pickableOnly: true);
    Event? nextEvent;
    if (next != null) {
      final resolvedNext = next;
      nextEvent = events.firstWhere(
        (e) => e.sessions.any((s) => s.id == resolvedNext.id),
        orElse: () => events.first,
      );
    }
    // The pickable session can live in a later weekend than `next` (which
    // may be FP1). Resolve its event independently so the pick card's body
    // tap can deep-link to the correct race detail.
    Event? pickEvent;
    if (nextPickable != null) {
      final resolvedPick = nextPickable;
      try {
        pickEvent = events.firstWhere(
          (e) => e.sessions.any((s) => s.id == resolvedPick.id),
        );
      } catch (_) {
        pickEvent = nextEvent;
      }
    }
    if (nextPickable != null) {
      // Prime the predictions cache for the pickable session that _pickCard
      // actually renders, not the chronologically-next one (which is often FP1
      // and has no prediction).
      try {
        await scope.predictions.fetchPrediction(nextPickable.id);
      } catch (_) {
        // Non-fatal — the card just falls back to "No picks yet".
      }
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
      nextPickable: nextPickable,
      nextEvent: nextEvent,
      pickEvent: pickEvent,
      lastEvent: lastEvent,
      lastRaceSession: lastRaceSession,
      lastResult: lastResult,
      leaderboard: leaderboard,
    );
  }

  Session? _computeNextSession(List<Event> events, {required bool pickableOnly}) {
    bool isPickable(SessionType t) =>
        t == SessionType.qualifying ||
        t == SessionType.sprint_quali ||
        t == SessionType.sprint ||
        t == SessionType.race;
    final now = DateTime.now();
    Session? best;
    for (final e in events) {
      for (final s in e.sessions) {
        if (s.status != SessionStatus.scheduled) continue;
        if (!s.scheduledStart.isAfter(now)) continue;
        if (pickableOnly && !isPickable(s.type)) continue;
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
                  // Wrap pick/last cards in ListenableBuilder so changes saved
                  // on the predict screen (which mutate scope.predictions)
                  // re-render here without a full home reload.
                  ListenableBuilder(
                    listenable: scope.predictions,
                    builder: (_, __) => _pickCard(d, scope, t),
                  ),
                ],
                if (d.lastEvent != null) ...[
                  _section('Last race · ${d.lastEvent!.name}', onTap: () {
                    final race = d.lastEvent!.sessions.firstWhere(
                      (s) => s.type == SessionType.race,
                      orElse: () => d.lastEvent!.sessions.first,
                    );
                    context.push('/race/${d.lastEvent!.round}/${race.id}');
                  }),
                  ListenableBuilder(
                    listenable: scope.predictions,
                    builder: (_, __) => _lastCard(d, scope, t),
                  ),
                ],
                _section('$leagueName · In-season',
                    onTap: () => context.go('/standings/league')),
                InkWell(
                  onTap: () => context.go('/standings/league'),
                  child: _leagueCard(
                    d.leaderboard,
                    scope.auth.currentUserId,
                    t,
                    points: (r) => r.inSeasonPoints,
                  ),
                ),
                _section('$leagueName · Total',
                    onTap: () => context.go('/standings/league')),
                InkWell(
                  onTap: () => context.go('/standings/league'),
                  child: _leagueCard(
                    d.leaderboard,
                    scope.auth.currentUserId,
                    t,
                    points: (r) => r.pointsTotal,
                  ),
                ),
                const SizedBox(height: Spacing.xxl),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _topbar(String leagueName, int memberCount) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
      child: Row(
        children: [
          // F1 logo plate: invert surface so it reads as a strong badge in
          // both themes (black-on-white in light, off-white-on-black in dark)
          // instead of disappearing into the dark surface.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            color: t.colorScheme.onSurface,
            child: Text('F1',
                style: AppText.display(14, color: t.colorScheme.surface)),
          ),
          const SizedBox(width: 4),
          Text('PG', style: AppText.display(14)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 5),
            decoration: BoxDecoration(
              // strokeColor adapts per theme — matches every other pill
              // border in the app (settings, standings tabs, etc.).
              border: Border.all(color: t.strokeColor, width: 1.5),
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
  }

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
            const Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: RacingStripesPainter()),
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
    // Use the next *pickable* session — d.next can be FP1 which has no
    // prediction. Falls back to d.next for the rare case where there's no
    // upcoming scorable session at all (shouldn't normally happen).
    final pickSession = d.nextPickable ?? d.next!;
    final sessionId = pickSession.id;
    // `scope` is dynamic here (private InheritedWidget type can't appear in
    // public method signatures), so cast the prediction lookup to restore
    // static typing — otherwise `.toList()` produces List<dynamic>.
    final PredictionView? pred =
        scope.predictions.prediction(sessionId) as PredictionView?;
    final picks =
        pred?.picks.map((p) => p.driverCode).toList() ?? const <String>[];
    final locked = pred?.isLocked ?? false;
    final empty = picks.isEmpty;
    final sessionLabel = _sessionTypeLabel(pickSession.type);
    // Split tap zones: tapping the body opens the race-detail view (same
    // route the calendar uses), tapping the EDIT/PICK stub jumps straight
    // into the predict screen.
    final round = d.pickEvent?.round ?? d.nextEvent?.round;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
      child: TicketCard(
        onBodyTap: round == null
            ? null
            : () => context.push('/race/$round/$sessionId'),
        onStubTap: () => context.go('/predict?session=$sessionId'),
        stubWidth: 80,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                // Hardcoded black tones because the ticket card is cream in
                // both themes — using t.colorScheme.onSurface would render
                // white-on-cream in dark mode.
                Text(sessionLabel,
                    style: AppText.label(10,
                        color: Colors.black.withOpacity(0.6))),
                const SizedBox(width: 6),
                _statusDot(t, empty: empty, locked: locked),
                const SizedBox(width: 4),
                Text(empty ? 'no picks' : (locked ? 'locked' : 'draft'),
                    style: AppText.label(10,
                        color: Colors.black.withOpacity(0.6))),
                const Spacer(),
                Text('YOUR PICK',
                    style: AppText.label(9,
                        color: Colors.black.withOpacity(0.45))),
              ],
            ),
            const SizedBox(height: 10),
            if (empty)
              Text('Tap to make your pick',
                  style: AppText.body(13,
                      color: Colors.black.withOpacity(0.5))
                      .copyWith(fontStyle: FontStyle.italic))
            else
              Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < picks.length; i++)
                    _pickChip(t, i + 1, picks[i]),
                ],
              ),
          ],
        ),
        stub: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(empty ? 'PICK' : (locked ? 'LOCKED' : 'EDIT'),
                style: AppText.display(15,
                    color: empty ? BrandColors.accent : Colors.black)),
            const SizedBox(height: 4),
            Text(empty ? 'tap →' : (locked ? '✦' : 'tap →'),
                style: AppText.label(9,
                    color: Colors.black.withOpacity(0.55))),
          ],
        ),
      ),
    );
  }

  Widget _statusDot(ThemeData t, {required bool empty, required bool locked}) {
    final color = empty
        ? BrandColors.accent
        : (locked ? Colors.black : Colors.black.withOpacity(0.4));
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  Widget _pickChip(ThemeData t, int position, String driverCode) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.08),
            borderRadius: const BorderRadius.all(Radius.circular(4)),
          ),
          child: Text('P$position',
              style: AppText.label(9, color: Colors.black.withOpacity(0.7))),
        ),
        const SizedBox(width: 6),
        Text(driverCode,
            style: AppText.body(14, weight: FontWeight.w800, color: Colors.black)),
      ],
    );
  }

  Widget _lastCard(_HomeData d, scope, ThemeData t) {
    final lastSession = d.lastRaceSession;
    final PredictionView? pred = lastSession == null
        ? null
        : scope.predictions.prediction(lastSession.id) as PredictionView?;
    final picks =
        pred?.picks.map((p) => p.driverCode).toList() ?? const <String>[];
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

  Widget _leagueCard(
    List<LeaderboardRow> rows,
    String? meId,
    ThemeData t, {
    required int Function(LeaderboardRow) points,
  }) {
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
    final preview = [...rows]
      ..sort((a, b) => points(b).compareTo(points(a)));
    final top = preview.take(4).toList();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
      child: AppCard(
        child: Column(
          children: List.generate(top.length, (i) {
            final r = top[i];
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
                  Text('${points(r)}', style: AppText.display(13)),
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
  /// The next session that the caller can predict (qualifying / SQ / sprint /
  /// race). Differs from [next] during practice days. Used by the pick card so
  /// it doesn't render "Make your pick · FP1".
  final Session? nextPickable;
  final Event? nextEvent;
  /// Event that owns [nextPickable]. Differs from [nextEvent] when the
  /// chronologically-next session is FP-only and the next pickable session
  /// lives in a later weekend.
  final Event? pickEvent;
  final Event? lastEvent;
  final Session? lastRaceSession;
  final List<SessionResult> lastResult;
  final List<LeaderboardRow> leaderboard;
  _HomeData({
    required this.events,
    required this.next,
    required this.nextPickable,
    required this.nextEvent,
    required this.pickEvent,
    required this.lastEvent,
    required this.lastRaceSession,
    required this.lastResult,
    required this.leaderboard,
  });
}

