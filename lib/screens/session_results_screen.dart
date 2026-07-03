// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../api/api_client.dart';
import '../api/models/event.dart';
import '../api/models/member_prediction.dart';
import '../api/models/session.dart';
import '../api/models/live_snapshot.dart';
import '../api/models/session_result.dart';
import '../api/models/session_leaderboard_row.dart';
import '../api/models/my_score.dart';
import '../components/app_card.dart';
import '../components/standings_list.dart';
import '../components/circuit_svg.dart';
import '../components/error_view.dart';
import '../components/ticket/pick_ticket.dart';
import '../components/ticket/souvenir_ticket.dart';
import '../components/ticket/weekend_souvenir_ticket.dart';
import '../domain/prediction.dart';
import '../domain/result_display.dart';
import '../domain/scoring.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/team_colors.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

// Sprint Quali is "view-only": users can no longer pick (see predict_screen.dart)
// and the backend no longer scores it, but we still surface a SPRINT QUALI tab
// on the results screen so the actual session classification stays visible from
// the calendar drill-down. With no picks, the YourScore ticket just reads
// "No picks for this session" and the FULL CLASSIFICATION renders normally.
//
// Practice sessions (FP1/FP2/FP3) follow the same view-only pattern — they
// have no picks and aren't scored, but the FP results are useful reference
// material so they get tabs here too.
const _pickableTypes = {
  SessionType.qualifying,
  SessionType.sprint_quali,
  SessionType.sprint,
  SessionType.race,
};

const _displayableTypes = {
  SessionType.fp1,
  SessionType.fp2,
  SessionType.fp3,
  SessionType.qualifying,
  SessionType.sprint_quali,
  SessionType.sprint,
  SessionType.race,
};

const _typeLabels = {
  SessionType.fp1: 'FP1',
  SessionType.fp2: 'FP2',
  SessionType.fp3: 'FP3',
  SessionType.qualifying: 'QUALI',
  SessionType.sprint_quali: 'SPRINT QUALI',
  SessionType.sprint: 'SPRINT',
  SessionType.race: 'RACE',
};

class SessionResultsScreen extends StatefulWidget {
  final int round;
  final int sessionId;

  /// Initial view mode ('events' | 'gp'). Carried through the route so that
  /// Full-GP nav can jump from one GP to the next while staying in GP mode.
  final String? initialMode;
  const SessionResultsScreen({
    super.key,
    required this.round,
    required this.sessionId,
    this.initialMode,
  });

  @override
  State<SessionResultsScreen> createState() => _SessionResultsScreenState();
}

class _SessionResultsScreenState extends State<SessionResultsScreen> {
  /// All events for the season — fed by `api.events()` once. We need the full
  /// list (not just the active round) so prev/next nav can cross event
  /// boundaries when the user reaches the first/last session of the weekend.
  Future<List<Event>>? _eventsFuture;
  int? _activeSessionId;
  final Map<int, Future<_SessionPayload>> _payloads = {};
  // 'events' = per-session view (default); 'gp' = the full-weekend view with
  // your recap + the league's cumulative weekend leaderboard. Seeded from the
  // route so Full-GP nav can cross into a new GP and stay in GP mode.
  late String _mode = widget.initialMode == 'gp' ? 'gp' : 'events';
  Future<List<SessionLeaderboardRow>>? _breakdownFuture;

  Future<List<SessionLeaderboardRow>> _breakdownFor(String leagueId) {
    return _breakdownFuture ??=
        AppState.of(context).api.leagueSessionBreakdown(leagueId);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _eventsFuture ??= AppState.of(context).api.events();
    _activeSessionId ??= widget.sessionId;
  }

  Future<_SessionPayload> _payloadFor(int sessionId) {
    return _payloads.putIfAbsent(sessionId, () async {
      final scope = AppState.of(context);
      // Fetch results, the caller's prediction (controller caches it), and
      // the backend score table in parallel.
      List<SessionResult> result = const [];
      try {
        final results = await Future.wait([
          scope.api.sessionResults(sessionId).then<dynamic>((v) => v),
          scope.predictions.fetchPrediction(sessionId).then<dynamic>((v) => v),
          scope.predictions.refreshScores().then<dynamic>((_) => null),
        ]);
        result = (results[0] as List<SessionResult>);
      } on NotFoundException {
        // Results haven't published yet — still try the prediction + scores
        // so we can show picks-without-results.
        try {
          await scope.predictions.fetchPrediction(sessionId);
        } catch (_) {}
        try {
          await scope.predictions.refreshScores();
        } catch (_) {}
      }
      final picks = scope.predictions
              .prediction(sessionId)
              ?.picks
              .map((p) => p.driverCode)
              .toList() ??
          const <String>[];
      final backendScore = scope.predictions.score(sessionId)?.pointsTotal;
      // Best-effort fetch of league members' picks. Hidden if the user has
      // no league, the session hasn't started yet (backend returns
      // sessionLocked: false), or the call errors out.
      var members = const <MemberPrediction>[];
      final leagues = scope.auth.leagues;
      final selfId = scope.auth.currentUserId;
      if (leagues.isNotEmpty) {
        try {
          final res = await scope.api
              .leagueSessionPredictions(leagues.first.id, sessionId);
          members = res.sessionLocked
              ? res.predictions.where((p) => p.userId != selfId).toList()
              : const [];
          members.sort(
              (a, b) => (b.pointsTotal ?? -1).compareTo(a.pointsTotal ?? -1));
        } catch (_) {
          members = const [];
        }
      }
      return _SessionPayload(
        result: result,
        picks: picks,
        backendScore: backendScore,
        leagueMemberPredictions: members,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      backgroundColor: t.colorScheme.surface,
      body: SafeArea(
        child: FutureBuilder<List<Event>>(
          future: _eventsFuture,
          builder: (_, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const SizedBox.shrink();
            }
            if (snap.hasError) {
              return ErrorView(
                error: snap.error!,
                stack: snap.stackTrace,
                where: 'Race ${widget.round}',
                onRetry: () => setState(() {
                  _eventsFuture = AppState.of(context).api.events();
                  _payloads.clear();
                }),
              );
            }
            final allEvents = snap.data!;
            final event = allEvents.firstWhere(
              (e) => e.round == widget.round,
              orElse: () => allEvents.first,
            );
            final sessions = event.sessions
                .where((s) => _displayableTypes.contains(s.type))
                .toList()
              ..sort((a, b) => a.scheduledStart.compareTo(b.scheduledStart));
            if (sessions.isEmpty) {
              return _header(event, null, t, onPrev: null, onNext: null);
            }
            final active = sessions.firstWhere(
              (s) => s.id == _activeSessionId,
              orElse: () => sessions.last,
            );
            // Full GP is only meaningful once a weekend has started — future
            // GPs have no results/scores to aggregate.
            final hasLeague = AppState.of(context).auth.leagues.isNotEmpty;
            final gpAvailable = hasLeague && _eventHasStarted(event);
            final inGp = gpAvailable && _mode == 'gp';

            // The prev/next chevrons always switch *whole Grand Prix* —
            // within-weekend session navigation is the job of the session
            // tabs below. The only difference between modes is the set of
            // GPs we step through:
            //  • GP mode     → started GPs only (the ones with a Full-GP view),
            //    staying in GP mode across the route change.
            //  • Events mode → every GP in the season (future weekends are
            //    valid here — they show picks / countdowns).
            final navEvents = inGp
                ? _startedEvents(allEvents)
                : ([...allEvents]..sort((a, b) => a.round.compareTo(b.round)));
            final navIdx = navEvents.indexWhere((e) => e.round == event.round);
            final prevEvent = navIdx > 0 ? navEvents[navIdx - 1] : null;
            final nextEvent =
                navIdx >= 0 && navIdx < navEvents.length - 1
                    ? navEvents[navIdx + 1]
                    : null;
            final onPrev = prevEvent == null
                ? null
                : () => _navigateToEvent(prevEvent, gp: inGp);
            final onNext = nextEvent == null
                ? null
                : () => _navigateToEvent(nextEvent, gp: inGp);

            return SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: Spacing.xxl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // In GP mode the header subtitle reads just "Round X" —
                    // there's no single active session to name.
                    _header(event, inGp ? null : active, t,
                        onPrev: onPrev, onNext: onNext),
                    if (gpAvailable) _modeToggle(t),
                    if (inGp)
                      _fullGpView(event, t)
                    else ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                          Spacing.lg, Spacing.sm, Spacing.lg, Spacing.lg),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: sessions
                            .map((s) => _SessionTab(
                                  label: _typeLabels[s.type] ?? s.type.name,
                                  active: s.id == active.id,
                                  onTap: () =>
                                      setState(() => _activeSessionId = s.id),
                                ))
                            .toList(),
                      ),
                    ),
                    ListenableBuilder(
                      listenable: Listenable.merge([
                        AppState.of(context).live,
                        AppState.of(context).predictions,
                      ]),
                      builder: (_, __) {
                        final scope = AppState.of(context);
                        final live = scope.live;
                        final snap = live.snapshot;
                        if (live.isLiveFor(active.id) &&
                            snap != null &&
                            snap.state != LiveState.finalised) {
                          // Lazy + idempotent: load my picks so live rows tint.
                          // ignore: discarded_futures
                          scope.predictions.fetchPrediction(active.id);
                          final myPicks = scope.predictions
                                  .prediction(active.id)
                                  ?.picks
                                  .map((p) => p.driverCode)
                                  .toList() ??
                              const <String>[];
                          return LiveResultsBody(
                            event: event,
                            sessionType: active.type,
                            myPicks: myPicks,
                            snap: snap,
                          );
                        }
                        return FutureBuilder<_SessionPayload>(
                          future: _payloadFor(active.id),
                          builder: (_, payloadSnap) {
                            if (payloadSnap.connectionState !=
                                ConnectionState.done) {
                              return const Padding(
                                padding: EdgeInsets.all(Spacing.lg),
                                child: SizedBox.shrink(),
                              );
                            }
                            if (payloadSnap.hasError) {
                              return Padding(
                                padding: const EdgeInsets.all(Spacing.lg),
                                child: Text('${payloadSnap.error}'),
                              );
                            }
                            return _Body(
                              event: event,
                              session: active,
                              payload: payloadSnap.data!,
                            );
                          },
                        );
                      },
                    ),
                    ],
                  ],
                ),
              );
          },
        ),
      ),
    );
  }

  Widget _modeToggle(ThemeData t) => Padding(
        padding:
            const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xs, Spacing.lg, 0),
        child: Row(children: [
          _modePill('events', 'EVENTS', t),
          const SizedBox(width: 6),
          _modePill('gp', 'FULL GP', t),
        ]),
      );

  Widget _modePill(String id, String label, ThemeData t) {
    final on = _mode == id;
    return GestureDetector(
      onTap: () => setState(() => _mode = id),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: 7),
        decoration: BoxDecoration(
          color: on ? t.colorScheme.onSurface : Colors.transparent,
          border: Border.all(color: t.strokeColor, width: 1.5),
          borderRadius: const BorderRadius.all(Radius.circular(8)),
        ),
        child: Text(label,
            style: AppText.label(10,
                color: on ? t.colorScheme.surface : t.colorScheme.onSurface)),
      ),
    );
  }

  /// The full-weekend view: your cumulative weekend recap (from already-loaded
  /// MyScores for this round) on top, then the league's weekend leaderboard
  /// aggregated from the per-session breakdown.
  Widget _fullGpView(Event event, ThemeData t) {
    final scope = AppState.of(context);
    final selfId = scope.auth.currentUserId;
    final leagueId = scope.auth.leagues.first.id;
    final mine = <MyScore>[
      for (final sid in scope.predictions.allScoreIds)
        if (scope.predictions.score(sid)?.eventRound == event.round)
          scope.predictions.score(sid)!,
    ]..sort((a, b) => a.sessionScheduledStart.compareTo(b.sessionScheduledStart));
    final myTotal = mine.fold<int>(0, (s, x) => s + x.pointsTotal);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              Spacing.lg, Spacing.sm, Spacing.lg, Spacing.lg),
          child: mine.isEmpty
              ? AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('YOUR WEEKEND',
                          style: AppText.label(11,
                              color:
                                  t.colorScheme.onSurface.withOpacity(0.6))),
                      const SizedBox(height: Spacing.xs),
                      Text('No scored sessions this weekend yet.',
                          style: AppText.body(12,
                              color:
                                  t.colorScheme.onSurface.withOpacity(0.6))),
                    ],
                  ),
                )
              : WeekendSouvenirTicket(
                  event: event,
                  sessions: [
                    for (final s in mine)
                      (type: s.sessionType, points: s.pointsTotal),
                  ],
                  total: myTotal,
                  circuitWatermark: CircuitSvg(event: event),
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
              Spacing.lg, 0, Spacing.lg, Spacing.xs),
          child: Text('LEAGUE · THIS WEEKEND',
              style: AppText.label(11,
                  color: t.colorScheme.onSurface.withOpacity(0.6))),
        ),
        FutureBuilder<List<SessionLeaderboardRow>>(
          future: _breakdownFor(leagueId),
          builder: (_, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Padding(
                  padding: EdgeInsets.all(Spacing.lg), child: SizedBox.shrink());
            }
            if (snap.hasError || snap.data == null) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
                child: Text("Couldn't load league weekend points.",
                    style: AppText.body(12,
                        color: t.colorScheme.onSurface.withOpacity(0.6))),
              );
            }
            final byUser = <String, _WeekAgg>{};
            for (final row
                in snap.data!.where((r) => r.eventRound == event.round)) {
              for (final m in row.members) {
                final agg = byUser.putIfAbsent(
                    m.userId, () => _WeekAgg(m.userId, m.displayName));
                agg.points += m.pointsTotal;
              }
            }
            final entries = [
              for (final a in byUser.values)
                if (a.points > 0)
                  StandingsEntry(
                      userId: a.userId,
                      displayName: a.displayName,
                      points: a.points),
            ]..sort((x, y) => y.points.compareTo(x.points));
            if (entries.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
                child: Text('No league points scored this weekend yet.',
                    style: AppText.body(12,
                        color: t.colorScheme.onSurface.withOpacity(0.6))),
              );
            }
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
              child: StandingsList(
                entries: entries,
                meId: selfId,
                onTapRow: (uid) =>
                    context.push('/league/$leagueId/player/$uid'),
              ),
            );
          },
        ),
      ],
    );
  }

  /// Jump to another GP via the prev/next chevrons. Lands on the event's last
  /// session (the race, or the latest displayable one) so the headline result
  /// is what shows first. `gp: true` appends `?mode=gp` to keep Full-GP mode
  /// across the route change. Uses `replace` so the back button returns to
  /// wherever the user entered the race detail from (calendar / home / etc.)
  /// instead of breadcrumbing every swipe in between.
  void _navigateToEvent(Event target, {required bool gp}) {
    final sessions = target.sessions
        .where((s) => _displayableTypes.contains(s.type))
        .toList()
      ..sort((a, b) => a.scheduledStart.compareTo(b.scheduledStart));
    if (sessions.isEmpty) return;
    final suffix = gp ? '?mode=gp' : '';
    context.replace('/race/${target.round}/${sessions.last.id}$suffix');
  }

  /// A weekend counts as "started" once its earliest displayable session is in
  /// the past — i.e. the GP is current or already run.
  bool _eventHasStarted(Event e) {
    DateTime? earliest;
    for (final s in e.sessions) {
      if (!_displayableTypes.contains(s.type)) continue;
      if (earliest == null || s.scheduledStart.isBefore(earliest)) {
        earliest = s.scheduledStart;
      }
    }
    return earliest != null && earliest.isBefore(DateTime.now());
  }

  /// Started GPs in round order — the navigable set in Full-GP mode.
  List<Event> _startedEvents(List<Event> events) =>
      events.where(_eventHasStarted).toList()
        ..sort((a, b) => a.round.compareTo(b.round));

  Widget _header(
    Event event,
    Session? active,
    ThemeData t, {
    required VoidCallback? onPrev,
    required VoidCallback? onNext,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          Spacing.lg, Spacing.lg, Spacing.lg, Spacing.sm),
      child: Row(
        children: [
          IconButton(
            onPressed: () =>
                context.canPop() ? context.pop() : context.go('/calendar'),
            icon: const Icon(Icons.arrow_back_ios_new, size: 16),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event.name, style: AppText.display(20)),
                Text(
                  active == null
                      ? 'Round ${event.round}'
                      : 'Round ${event.round} · ${_typeLabels[active.type] ?? active.type.name}',
                  style: AppText.label(10,
                      color: t.colorScheme.onSurface.withOpacity(0.55)),
                ),
              ],
            ),
          ),
          // Prev / next session nav grouped on the right so the back arrow
          // on the left doesn't end up next to a near-identical chevron.
          IconButton(
            onPressed: onPrev,
            icon: const Icon(Icons.chevron_left, size: 22),
            tooltip: 'Previous',
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right, size: 22),
            tooltip: 'Next',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _SessionTab extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _SessionTab({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 7),
        decoration: BoxDecoration(
          color: active ? t.colorScheme.onSurface : Colors.transparent,
          border: Border.all(color: t.strokeColor, width: 1.5),
          borderRadius: const BorderRadius.all(Radius.circular(8)),
        ),
        child: Text(
          label,
          style: AppText.label(
            10,
            color: active ? t.colorScheme.surface : t.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final Event event;
  final Session session;
  final _SessionPayload payload;
  const _Body(
      {required this.event, required this.session, required this.payload});

  int get _topN => requiredPicks(session.type);

  int _score() {
    // Prefer the backend's authoritative score; fall back to local calculation
    // when the backend hasn't scored this session yet (results just landed,
    // rescore not run, etc.).
    final backend = payload.backendScore;
    if (backend != null) return backend;
    return scoreSession(session.type, payload.picks, payload.result);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final topN = _topN;
    final score = _score();

    // Practice sessions are view-only and have no picks → skip the score /
    // upcoming-session tickets entirely and let the classification stand
    // alone. The "Session hasn't run yet" empty state below covers FP3
    // before it starts.
    final isPickable = _pickableTypes.contains(session.type);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isPickable && payload.result.isEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
            child: _FutureSessionHero(
              event: event,
              session: session,
              picks: payload.picks,
            ),
          ),
        ] else if (isPickable) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
            child: _YourScoreTicket(
              event: event,
              sessionType: session.type,
              picks: payload.picks,
              classification: payload.result,
              score: score,
            ),
          ),
        ] else if (payload.result.isEmpty) ...[
          // Non-pickable session (FP) that hasn't been classified yet.
          // Show a quiet placeholder instead of a ticket.
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Spacing.lg, Spacing.xl, Spacing.lg, Spacing.lg),
            child: Text(
              'Session hasn\'t run yet, results appear here after the chequered flag.',
              style: AppText.label(11,
                  color: t.colorScheme.onSurface.withOpacity(0.55)),
            ),
          ),
        ],
        if (payload.result.isNotEmpty)
          _ClassificationCard(
            result: payload.result,
            picks: payload.picks,
            topN: topN,
            sessionType: session.type,
          ),
        if (isPickable) ...[
          // Hide league members who didn't pick this session — the empty
          // "NO PICKS" row was noise. Section header only renders when at
          // least one member has something to show.
          Builder(builder: (_) {
            final entered = payload.leagueMemberPredictions
                .where((m) => m.picks.isNotEmpty)
                .toList();
            if (entered.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xs),
                  child: Text('LEAGUE PICKS',
                      style: AppText.label(11,
                          color: t.colorScheme.onSurface.withOpacity(0.6))),
                ),
                for (final m in entered)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        Spacing.lg, 0, Spacing.lg, Spacing.sm),
                    child: _MemberFormCard(
                      member: m,
                      result: payload.result,
                      sessionType: session.type,
                    ),
                  ),
              ],
            );
          }),
        ],
      ],
    );
  }
}

/// The session classification list. Caps to the top 5 rows with a "see full
/// classification" expander when there are more than 5, keeping the rich
/// per-driver rows (pick-slot highlight, outcome tick, lap time).
class _ClassificationCard extends StatefulWidget {
  final List<SessionResult> result;
  final List<String> picks;
  final int topN;
  final SessionType sessionType;
  const _ClassificationCard({
    required this.result,
    required this.picks,
    required this.topN,
    required this.sessionType,
  });

  @override
  State<_ClassificationCard> createState() => _ClassificationCardState();
}

class _ClassificationCardState extends State<_ClassificationCard> {
  bool _showFull = false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final results = widget.result;
    final hasToggle = results.length > 5;
    final visible = (!_showFull && hasToggle) ? 5 : results.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              Spacing.lg, Spacing.lg, Spacing.lg, Spacing.xs),
          child: Text('CLASSIFICATION',
              style: AppText.label(11,
                  color: t.colorScheme.onSurface.withOpacity(0.6))),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
          child: Column(
            children: [
              _ClassificationHeader(t: t),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: t.strokeColor, width: Strokes.card),
                  borderRadius: Radii.rLg,
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (var i = 0; i < visible; i++)
                      _row(t, i, isLast: !hasToggle && i == visible - 1),
                    if (hasToggle) _toggleRow(t),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _toggleRow(ThemeData t) {
    final remaining = widget.result.length - 5;
    return InkWell(
      onTap: () => setState(() => _showFull = !_showFull),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: Spacing.sm, vertical: Spacing.sm),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: t.strokeColor.withOpacity(0.25), width: 1),
          ),
        ),
        child: Center(
          child: Text(
            _showFull
                ? 'SHOW TOP 5  ▴'
                : 'SEE FULL CLASSIFICATION (+$remaining)  ▾',
            style: AppText.label(10, color: BrandColors.accent),
          ),
        ),
      ),
    );
  }

  Widget _row(ThemeData t, int i, {required bool isLast}) {
    final r = widget.result[i];
    final slot = widget.picks.indexOf(r.driverCode);
    final pickedSlot = slot == -1 ? null : slot + 1;
    final outcome = pickedSlot == null
        ? null
        : outcomeFor(r.driverCode, pickedSlot, widget.result, widget.topN);
    final mine = pickedSlot != null;
    final rowBg = !mine
        ? null
        : (outcome == PickOutcome.exact
            ? BrandColors.ok.withOpacity(0.18)
            : outcome == PickOutcome.inTopN
                ? BrandColors.near.withOpacity(0.22)
                : t.rowHighlight);
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: Spacing.sm, vertical: Spacing.sm),
      decoration: BoxDecoration(
        color: rowBg,
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(
                    color: t.strokeColor.withOpacity(0.25), width: 1),
              ),
      ),
      child: Row(
        children: [
          SizedBox(
              width: _kPosCol,
              child: Text('${r.position}', style: AppText.display(13))),
          const SizedBox(width: Spacing.xs),
          Container(
            width: 5,
            height: 22,
            decoration: BoxDecoration(
                color: teamColor(r.constructorId),
                borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: Spacing.sm),
          SizedBox(
              width: _kCodeCol,
              child: Text(r.driverCode,
                  style: AppText.body(12, weight: FontWeight.w800))),
          Expanded(
              child: Text(r.driverName,
                  style: AppText.body(12, weight: FontWeight.w500))),
          SizedBox(
            width: _kPickCol,
            child: pickedSlot == null
                ? const SizedBox.shrink()
                : Center(child: _PickSlotChip(slot: pickedSlot)),
          ),
          const SizedBox(width: Spacing.xs),
          SizedBox(
            width: _kOutcomeCol,
            child: outcome == null
                ? const SizedBox.shrink()
                : Center(child: _OutcomeTag(outcome: outcome)),
          ),
          const SizedBox(width: Spacing.sm),
          SizedBox(
            width: _kTimeCol,
            child: Text(
              displayTime(r, widget.sessionType),
              style: AppText.display(11,
                  color: t.colorScheme.onSurface.withOpacity(0.6)),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

// Shared column widths so the classification header and rows align exactly.
const double _kPosCol = 22;
const double _kCodeCol = 44;
const double _kPickCol = 28;
const double _kOutcomeCol = 24;
const double _kTimeCol = 78;

class _ClassificationHeader extends StatelessWidget {
  final ThemeData t;
  const _ClassificationHeader({required this.t});

  @override
  Widget build(BuildContext context) {
    final muted = AppText.label(8, color: t.colorScheme.onSurface.withOpacity(0.55));
    return Padding(
      // Match the row's internal padding so labels sit over the right columns.
      padding: const EdgeInsets.fromLTRB(Spacing.sm, 0, Spacing.sm, Spacing.xs),
      child: Row(
        children: [
          SizedBox(width: _kPosCol, child: Text('P', style: muted)),
          const SizedBox(width: Spacing.xs),
          const SizedBox(width: 5),
          const SizedBox(width: Spacing.sm),
          SizedBox(width: _kCodeCol, child: Text('CODE', style: muted)),
          const Expanded(child: SizedBox.shrink()),
          SizedBox(width: _kPickCol, child: Text('PICK', style: muted, textAlign: TextAlign.center)),
          const SizedBox(width: Spacing.xs),
          const SizedBox(width: _kOutcomeCol),
          const SizedBox(width: Spacing.sm),
          SizedBox(width: _kTimeCol, child: Text('TIME', style: muted, textAlign: TextAlign.right)),
        ],
      ),
    );
  }
}

class _OutcomeTag extends StatelessWidget {
  final PickOutcome outcome;
  const _OutcomeTag({required this.outcome});

  @override
  Widget build(BuildContext context) {
    final (bg, glyph, fg) = switch (outcome) {
      PickOutcome.exact => (BrandColors.ok, '✓', Colors.black),
      PickOutcome.inTopN => (BrandColors.near, '~', Colors.black),
      PickOutcome.miss => (Colors.black, '✗', Colors.white),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.all(Radius.circular(4)),
      ),
      child: Text(
        glyph,
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.w900,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _PickSlotChip extends StatelessWidget {
  final int slot;
  const _PickSlotChip({required this.slot});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black, width: 1.2),
        borderRadius: const BorderRadius.all(Radius.circular(4)),
      ),
      child: Text(
        'P$slot',
        style: const TextStyle(
          color: Colors.black,
          fontWeight: FontWeight.w900,
          fontSize: 10,
        ),
      ),
    );
  }
}

/// Mutable per-member accumulator for summing a weekend's session points.
class _WeekAgg {
  final String userId;
  final String displayName;
  int points = 0;
  _WeekAgg(this.userId, this.displayName);
}

class _SessionPayload {
  final List<SessionResult> result;
  final List<String> picks;
  final int? backendScore;

  /// Every league member's picks + session score for this session. Empty when
  /// the user has no league, the session hasn't started, or the call failed.
  /// Already filtered to exclude the caller themselves.
  final List<MemberPrediction> leagueMemberPredictions;
  _SessionPayload({
    required this.result,
    required this.picks,
    this.backendScore,
    this.leagueMemberPredictions = const [],
  });
}

/// Rich placeholder shown when a session has no results yet. Replaces the old
/// "RESULTS NOT IN YET / come back after the chequered flag" empty state with
/// the information we actually have: the event's location, the session's
/// scheduled start with a live countdown, the caller's locked/draft picks (or
/// a Predict CTA), and the full session schedule for the weekend as chips.
class _FutureSessionHero extends StatelessWidget {
  final Event event;
  final Session session;
  final List<String> picks;
  const _FutureSessionHero({
    required this.event,
    required this.session,
    required this.picks,
  });

  bool get _isPickable => _pickableTypes.contains(session.type);

  static const _weekday = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

  String _dayTimeLabel() {
    final local = session.scheduledStart.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '${_weekday[local.weekday - 1]} $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final empty = picks.isEmpty;
    final typeLabel =
        _typeLabels[session.type] ?? session.type.name.toUpperCase();
    final status = empty
        ? (_isPickable ? 'NO PICKS' : 'NO ENTRY')
        : 'DRAFT';
    return PickTicket(
      event: event,
      driverCodes: picks,
      circuitWatermark: CircuitSvg(event: event),
      dayTime: '$typeLabel · ${_dayTimeLabel()}',
      statusOverride: status,
      sessionType: session.type,
      // No onBodyTap — we're already on the race screen for this session,
      // so pushing /race/{round}/{session} would loop the route stack onto
      // itself.
      onStubTap: _isPickable
          ? () => context.go('/predict?session=${session.id}')
          : null,
    );
  }
}


/// Caller's session score, rendered as a [SouvenirTicket] — same styled
/// paper as the rest of the ticket family. The P1 driver's constructor
/// (resolved from [classification]) drives the car silhouette watermark;
/// the event's circuit drives the secondary watermark.
class _YourScoreTicket extends StatelessWidget {
  final Event event;
  final SessionType sessionType;
  final List<String> picks;
  final List<SessionResult> classification;
  final int score;
  const _YourScoreTicket({
    required this.event,
    required this.sessionType,
    required this.picks,
    required this.classification,
    required this.score,
  });

  @override
  Widget build(BuildContext context) {
    String? p1ConstructorId;
    if (picks.isNotEmpty) {
      for (final r in classification) {
        if (r.driverCode == picks.first) {
          p1ConstructorId = r.constructorId;
          break;
        }
      }
    }
    // Find the driver code at each finishing position and mark our slot as
    // correct when the pick matched. `classification` is sorted by position
    // but may be partial during provisional/live; the lookup is per-position
    // so missing entries just leave the slot un-marked.
    final byPosition = <int, String>{
      for (final r in classification) r.position: r.driverCode,
    };
    final correctSlots = <int>{
      for (var i = 0; i < picks.length; i++)
        if (byPosition[i + 1] == picks[i]) i,
    };
    return SouvenirTicket(
      event: event,
      driverCodes: picks,
      correctSlots: correctSlots,
      p1ConstructorId: p1ConstructorId,
      circuitWatermark: CircuitSvg(event: event),
      scorePoints: score,
      sessionType: sessionType,
    );
  }
}

/// Compact bordered card for a league member — same anatomy as the recent-form
/// chip on the player profile screen, but full-width with the player's name
/// in the header and the picks rendered as `P# CODE` with an outcome dot per
/// slot. Replaces the older cream-stock ticket so the list reads as a
/// scannable stack instead of a horizontal scroll of slabs.
class _MemberFormCard extends StatelessWidget {
  final MemberPrediction member;
  final List<SessionResult> result;
  final SessionType sessionType;
  const _MemberFormCard({
    required this.member,
    required this.result,
    required this.sessionType,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final topN = requiredPicks(sessionType);
    final pts = member.pointsTotal;
    final empty = member.picks.isEmpty;
    final picksSorted = [...member.picks]
      ..sort((a, b) => a.position.compareTo(b.position));
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md, vertical: Spacing.sm),
      decoration: BoxDecoration(
        border: Border.all(color: t.strokeColor, width: Strokes.card),
        borderRadius: Radii.rLg,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  member.displayName.toUpperCase(),
                  style: AppText.display(16),
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                ),
                const SizedBox(height: 6),
                if (empty)
                  Text('NO PICKS',
                      style: AppText.label(9,
                          color: t.colorScheme.onSurface.withOpacity(0.55)))
                else
                  // FittedBox(scaleDown) so all picks stay on a single row —
                  // on narrow screens the whole strip shrinks uniformly
                  // instead of P5 wrapping to its own line.
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < picksSorted.length; i++) ...[
                          if (i > 0) const SizedBox(width: Spacing.md),
                          _MemberFormPick(
                            position: picksSorted[i].position,
                            driverCode: picksSorted[i].driverCode,
                            outcome: result.isEmpty
                                ? null
                                : outcomeFor(picksSorted[i].driverCode,
                                    picksSorted[i].position, result, topN),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: Spacing.md),
          Text(
            pts == null ? '—' : '+$pts',
            style: AppText.display(
              22,
              color: pts == null
                  ? t.colorScheme.onSurface.withOpacity(0.35)
                  : (pts > 0
                      ? BrandColors.accent
                      : t.colorScheme.onSurface.withOpacity(0.6)),
            ),
          ),
        ],
      ),
    );
  }
}

/// One `P# CODE ●` triplet inside a [_MemberFormCard] row. The dot color
/// encodes per-slot outcome (exact / wrongPos / miss / unknown).
class _MemberFormPick extends StatelessWidget {
  final int position;
  final String driverCode;
  final PickOutcome? outcome;
  const _MemberFormPick({
    required this.position,
    required this.driverCode,
    required this.outcome,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final dot = switch (outcome) {
      PickOutcome.exact => BrandColors.ok,
      PickOutcome.inTopN => BrandColors.near,
      PickOutcome.miss => t.colorScheme.onSurface.withOpacity(0.25),
      null => t.colorScheme.onSurface.withOpacity(0.2),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text('P$position',
            style: AppText.label(8,
                color: t.colorScheme.onSurface.withOpacity(0.55))),
        const SizedBox(width: 4),
        Text(driverCode,
            style: AppText.body(13, weight: FontWeight.w800)),
        const SizedBox(width: 4),
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
        ),
      ],
    );
  }
}

/// Live/provisional rendering of a session's results screen body. Mirrors the
/// finished-session layout but fed a live order + backend-projected points.
/// Row tinting uses the position-based [outcomeFor]; point totals come from the
/// backend (no on-device scoring). Team colours fall back to OpenF1's hex.
class LiveResultsBody extends StatelessWidget {
  final Event event;
  final SessionType sessionType;
  final List<String> myPicks;
  final LiveSnapshot snap;
  const LiveResultsBody({
    super.key,
    required this.event,
    required this.sessionType,
    required this.myPicks,
    required this.snap,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final topN = requiredPicks(sessionType);
    final order = snap.order;
    final badge = snap.state == LiveState.provisional
        ? 'PROVISIONAL · OFFICIAL PENDING'
        : 'LIVE';
    final myPts = snap.myPointsTotal;
    final members = [...snap.league]
      ..sort((a, b) => (b.pointsTotal ?? -1).compareTo(a.pointsTotal ?? -1));

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
        child: _YourScoreTicket(
          event: event,
          sessionType: sessionType,
          picks: myPicks,
          classification: snap.order,
          score: myPts ?? 0,
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(
            Spacing.lg, Spacing.lg, Spacing.lg, Spacing.xs),
        child: Row(children: [
          Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                  color: BrandColors.accent, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(badge, style: AppText.label(11, color: BrandColors.accent)),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
        child: AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: order.map((r) {
              final slot = myPicks.indexOf(r.driverCode);
              final pickedSlot = slot == -1 ? null : slot + 1;
              final outcome = pickedSlot == null
                  ? null
                  : outcomeFor(r.driverCode, pickedSlot, order, topN);
              final mine = pickedSlot != null;
              final rowBg = !mine
                  ? null
                  : (outcome == PickOutcome.exact
                      ? BrandColors.ok.withOpacity(0.18)
                      : outcome == PickOutcome.inTopN
                          ? BrandColors.near.withOpacity(0.22)
                          : t.rowHighlight);
              return Container(
                color: rowBg,
                padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.md, vertical: 7),
                child: Row(children: [
                  SizedBox(
                      width: 22,
                      child: Text('${r.position}', style: AppText.display(13))),
                  Container(
                      width: 3,
                      height: 18,
                      color: teamColor(r.constructorId,
                          fallbackHex: r.teamColour)),
                  const SizedBox(width: Spacing.sm),
                  SizedBox(
                      width: 44,
                      child: Text(r.driverCode,
                          style: AppText.body(12, weight: FontWeight.w800))),
                  Expanded(
                      child: Text(r.driverName,
                          style: AppText.body(12, weight: FontWeight.w500))),
                  if (pickedSlot != null) ...[
                    _PickSlotChip(slot: pickedSlot),
                    const SizedBox(width: 6),
                  ],
                  if (outcome != null) _OutcomeTag(outcome: outcome),
                ]),
              );
            }).toList(),
          ),
        ),
      ),
      if (members.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(
              Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xs),
          child: Text('LEAGUE · PROJECTED',
              style: AppText.label(11,
                  color: t.colorScheme.onSurface.withOpacity(0.6))),
        ),
        for (final m in members)
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Spacing.lg, 0, Spacing.lg, Spacing.sm),
            child: _MemberFormCard(
              member: m,
              result: order,
              sessionType: sessionType,
            ),
          ),
      ],
    ]);
  }
}
