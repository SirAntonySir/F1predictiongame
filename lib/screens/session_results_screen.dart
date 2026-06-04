// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../api/api_client.dart';
import '../api/models/event.dart';
import '../api/models/member_prediction.dart';
import '../api/models/session.dart';
import '../api/models/session_result.dart';
import '../components/app_card.dart';
import '../components/countdown.dart';
import '../components/error_view.dart';
import '../components/ticket_card.dart' show TicketCard, TicketTear;
import '../domain/prediction.dart';
import '../domain/result_display.dart';
import '../domain/scoring.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/country_flags.dart';
import '../theme/team_colors.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

// Sprint Quali is "view-only": users can no longer pick (see predict_screen.dart)
// and the backend no longer scores it, but we still surface a SPRINT QUALI tab
// on the results screen so the actual session classification stays visible from
// the calendar drill-down. With no picks, the YourScore ticket just reads
// "No picks for this session" and the FULL CLASSIFICATION renders normally.
const _pickableTypes = {
  SessionType.qualifying,
  SessionType.sprint_quali,
  SessionType.sprint,
  SessionType.race,
};

const _typeLabels = {
  SessionType.qualifying: 'QUALI',
  SessionType.sprint_quali: 'SPRINT QUALI',
  SessionType.sprint: 'SPRINT',
  SessionType.race: 'RACE',
};

class SessionResultsScreen extends StatefulWidget {
  final int round;
  final int sessionId;
  const SessionResultsScreen({
    super.key,
    required this.round,
    required this.sessionId,
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
        try { await scope.predictions.fetchPrediction(sessionId); } catch (_) {}
        try { await scope.predictions.refreshScores(); } catch (_) {}
      }
      final picks = scope.predictions.prediction(sessionId)
              ?.picks.map((p) => p.driverCode).toList() ??
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
          final res = await scope.api.leagueSessionPredictions(
              leagues.first.id, sessionId);
          members = res.sessionLocked
              ? res.predictions.where((p) => p.userId != selfId).toList()
              : const [];
          members.sort((a, b) =>
              (b.pointsTotal ?? -1).compareTo(a.pointsTotal ?? -1));
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
                .where((s) => _pickableTypes.contains(s.type))
                .toList()
              ..sort((a, b) => a.scheduledStart.compareTo(b.scheduledStart));
            if (sessions.isEmpty) {
              return _header(event, null, t, prev: null, next: null);
            }
            final active = sessions.firstWhere(
              (s) => s.id == _activeSessionId,
              orElse: () => sessions.last,
            );
            // Chronological list of *all* pickable sessions across the season,
            // used to advance past the last sub-tab of one event into the
            // first sub-tab of the next.
            final chronological = _allPickableSessions(allEvents);
            final currentIdx = chronological.indexWhere((e) => e.sessionId == active.id);
            final prev = currentIdx > 0 ? chronological[currentIdx - 1] : null;
            final next = currentIdx >= 0 && currentIdx < chronological.length - 1
                ? chronological[currentIdx + 1]
                : null;

            return GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragEnd: (details) {
                // Velocity unit: logical pixels per second. 250 ≈ a deliberate
                // flick; below that we ignore so vertical scroll isn't hijacked.
                final v = details.primaryVelocity ?? 0;
                if (v.abs() < 250) return;
                final target = v < 0 ? next : prev;
                if (target == null) return;
                _navigateTo(target);
              },
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: Spacing.xxl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(event, active, t, prev: prev, next: next),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                          Spacing.lg, Spacing.sm, Spacing.lg, Spacing.xs),
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
                    FutureBuilder<_SessionPayload>(
                      future: _payloadFor(active.id),
                      builder: (_, payloadSnap) {
                        if (payloadSnap.connectionState != ConnectionState.done) {
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
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _navigateTo(_PickableSessionRef target) {
    if (target.eventRound == widget.round) {
      setState(() => _activeSessionId = target.sessionId);
    } else {
      // Different event → URL changes. Use replace so the back button
      // returns to wherever the user originally entered the race detail
      // from (calendar / home / etc.) instead of breadcrumbing every
      // swipe in between.
      context.replace('/race/${target.eventRound}/${target.sessionId}');
    }
  }

  Widget _header(
    Event event,
    Session? active,
    ThemeData t, {
    required _PickableSessionRef? prev,
    required _PickableSessionRef? next,
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
            onPressed: prev == null ? null : () => _navigateTo(prev),
            icon: const Icon(Icons.chevron_left, size: 22),
            tooltip: 'Previous session',
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            onPressed: next == null ? null : () => _navigateTo(next),
            icon: const Icon(Icons.chevron_right, size: 22),
            tooltip: 'Next session',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

/// Minimal reference into the chronological session list; lets nav decide
/// whether to update internal state (same event) or change the URL (cross
/// event) without dragging the entire Session/Event payload around.
class _PickableSessionRef {
  final int sessionId;
  final int eventRound;
  final SessionType type;
  final DateTime scheduledStart;
  const _PickableSessionRef({
    required this.sessionId,
    required this.eventRound,
    required this.type,
    required this.scheduledStart,
  });
}

List<_PickableSessionRef> _allPickableSessions(List<Event> events) {
  final out = <_PickableSessionRef>[];
  for (final e in events) {
    for (final s in e.sessions) {
      if (!_pickableTypes.contains(s.type)) continue;
      out.add(_PickableSessionRef(
        sessionId: s.id,
        eventRound: e.round,
        type: s.type,
        scheduledStart: s.scheduledStart,
      ));
    }
  }
  out.sort((a, b) => a.scheduledStart.compareTo(b.scheduledStart));
  return out;
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
        padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 7),
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
  const _Body({required this.event, required this.session, required this.payload});

  int get _topN => requiredPicks(session.type);

  int _score() {
    // Prefer the backend's authoritative score; fall back to local calculation
    // when the backend hasn't scored this session yet (results just landed,
    // rescore not run, etc.).
    final backend = payload.backendScore;
    if (backend != null) return backend;
    switch (session.type) {
      case SessionType.qualifying:
        return scoreQualifying(payload.picks, payload.result);
      case SessionType.sprint_quali:
        return scoreSprintQualifying(payload.picks, payload.result);
      case SessionType.sprint:
        return scoreSprint(payload.picks, payload.result);
      case SessionType.race:
        return scoreRace(payload.picks, payload.result);
      default:
        return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final topN = _topN;
    final picksHits = payload.picks
        .asMap()
        .entries
        .map((e) => (
              slot: e.key + 1,
              code: e.value,
              outcome: outcomeFor(e.value, e.key + 1, payload.result, topN),
            ))
        .toList();
    final score = _score();
    final exactCount =
        picksHits.where((p) => p.outcome == PickOutcome.exact).length;
    final nearCount =
        picksHits.where((p) => p.outcome == PickOutcome.inTopN).length;
    final missCount =
        picksHits.where((p) => p.outcome == PickOutcome.miss).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (payload.result.isEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
            child: _FutureSessionHero(
              event: event,
              session: session,
              picks: payload.picks,
            ),
          ),
        ] else ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
            child: _YourScoreTicket(
              score: score,
              subtitle: payload.picks.isEmpty
                  ? 'No picks for this session'
                  : '$exactCount exact · $nearCount in top-$topN · $missCount miss',
            ),
          ),
        ],
        if (payload.result.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Spacing.lg, Spacing.lg, Spacing.lg, Spacing.xs),
            child: Text('FULL CLASSIFICATION',
                style: AppText.label(11,
                    color: t.colorScheme.onSurface.withOpacity(0.6))),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
            child: AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: payload.result.map((r) {
                  final slot = payload.picks.indexOf(r.driverCode);
                  final pickedSlot = slot == -1 ? null : slot + 1;
                  final outcome = pickedSlot == null
                      ? null
                      : outcomeFor(
                          r.driverCode, pickedSlot, payload.result, topN);
                  final mine = pickedSlot != null;
                  // Tint row by outcome — picks I got *exactly* right are
                  // green-tinted, picks that landed in my top-N but at a
                  // different slot are amber-tinted, picks that flat-out
                  // missed get the neutral row highlight, and rows that
                  // weren't my pick at all get no background.
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
                    child: Row(
                      children: [
                        SizedBox(
                          width: 22,
                          child:
                              Text('${r.position}', style: AppText.display(13)),
                        ),
                        Container(
                            width: 3,
                            height: 18,
                            color: teamColor(r.constructorId)),
                        const SizedBox(width: Spacing.sm),
                        SizedBox(
                          width: 44,
                          child: Text(r.driverCode,
                              style:
                                  AppText.body(12, weight: FontWeight.w800)),
                        ),
                        Expanded(
                          child: Text(r.driverName,
                              style:
                                  AppText.body(12, weight: FontWeight.w500)),
                        ),
                        if (pickedSlot != null) ...[
                          _PickSlotChip(slot: pickedSlot),
                          const SizedBox(width: 6),
                        ],
                        if (outcome != null) ...[
                          _OutcomeTag(outcome: outcome),
                          const SizedBox(width: Spacing.sm),
                        ],
                        Text(displayTime(r, session.type),
                            style: AppText.display(11,
                                color:
                                    t.colorScheme.onSurface.withOpacity(0.6))),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
        if (payload.leagueMemberPredictions.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xs),
            child: Text('LEAGUE PICKS',
                style: AppText.label(11,
                    color: t.colorScheme.onSurface.withOpacity(0.6))),
          ),
          // Responsive layout: on phones each ticket spans the row (one per
          // member, stacked). On iPad-wide viewports pair them up so we use
          // the horizontal real estate instead of stretching each ticket to
          // an awkward slab.
          LayoutBuilder(
            builder: (ctx, constraints) {
              final twoCol = constraints.maxWidth >= 640;
              final members = payload.leagueMemberPredictions;
              if (!twoCol) {
                return Column(
                  children: [
                    for (final m in members)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                            Spacing.lg, 0, Spacing.lg, Spacing.sm),
                        child: _MemberPickTicket(member: m),
                      ),
                  ],
                );
              }
              final rows = <Widget>[];
              for (var i = 0; i < members.length; i += 2) {
                final left = members[i];
                final right = i + 1 < members.length ? members[i + 1] : null;
                rows.add(Padding(
                  padding: const EdgeInsets.fromLTRB(
                      Spacing.lg, 0, Spacing.lg, Spacing.sm),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _MemberPickTicket(member: left)),
                      const SizedBox(width: Spacing.sm),
                      Expanded(
                        child: right == null
                            ? const SizedBox.shrink()
                            : _MemberPickTicket(member: right),
                      ),
                    ],
                  ),
                ));
              }
              return Column(children: rows);
            },
          ),
        ],
      ],
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

  @override
  Widget build(BuildContext context) {
    final flag = flagFor(event.country);
    final dateLabel = DateFormat('EEE d MMM').format(session.scheduledStart);
    final timeLabel = DateFormat('HH:mm').format(session.scheduledStart);
    final typeLabel = _typeLabels[session.type] ?? session.type.name.toUpperCase();
    final inFuture = session.scheduledStart.isAfter(DateTime.now());
    final empty = picks.isEmpty;

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                '${flag != null ? '$flag  ' : ''}${event.country.toUpperCase()} · ROUND ${event.round}',
                style: AppText.label(10, color: Colors.black.withOpacity(0.65)),
              ),
            ),
            const SizedBox(width: Spacing.sm),
            Text(typeLabel,
                style: AppText.label(10, color: Colors.black.withOpacity(0.65))),
          ],
        ),
        const SizedBox(height: Spacing.sm),
        Text(event.name.toUpperCase(), style: AppText.display(22, color: Colors.black)),
        const SizedBox(height: Spacing.xs),
        Text(
          '$dateLabel · $timeLabel · ${event.circuitName}',
          style: AppText.body(12, color: Colors.black.withOpacity(0.7)),
        ),
        if (inFuture) ...[
          const SizedBox(height: Spacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('STARTS IN',
                  style: AppText.label(10, color: Colors.black.withOpacity(0.55))),
              const SizedBox(width: 8),
              Countdown(target: session.scheduledStart, size: 22),
            ],
          ),
        ],
        const SizedBox(height: Spacing.md),
        // Inner horizontal perforation separating the event info from the picks.
        CustomPaint(
          size: const Size.fromHeight(1),
          painter: _HorizontalDashedLinePainter(color: Colors.black.withOpacity(0.4)),
        ),
        const SizedBox(height: Spacing.md),
        Text(empty ? 'YOUR PICKS · DRAFT' : 'YOUR PICKS',
            style: AppText.label(10, color: Colors.black.withOpacity(0.55))),
        const SizedBox(height: 8),
        if (empty)
          Text(
            _isPickable
                ? 'No picks yet — tap → to start'
                : 'No predictions for this session',
            style: AppText.body(12,
                color: Colors.black.withOpacity(0.55)).copyWith(fontStyle: FontStyle.italic),
          )
        else
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              for (var i = 0; i < picks.length; i++)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.1),
                        borderRadius: const BorderRadius.all(Radius.circular(4)),
                      ),
                      child: Text('P${i + 1}',
                          style: AppText.label(9, color: Colors.black.withOpacity(0.7))),
                    ),
                    const SizedBox(width: 6),
                    Text(picks[i],
                        style: AppText.body(14,
                            weight: FontWeight.w800, color: Colors.black)),
                  ],
                ),
            ],
          ),
      ],
    );

    return TicketCard(
      stubWidth: 76,
      bodyPadding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.lg, Spacing.lg, Spacing.lg),
      stubPadding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: Spacing.md),
      body: body,
      stub: _isPickable ? _stub(context, empty: empty) : _viewOnlyStub(),
    );
  }

  Widget _stub(BuildContext context, {required bool empty}) {
    return InkWell(
      onTap: () => context.go('/predict?session=${session.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(empty ? 'PICK' : 'EDIT',
                style: AppText.display(18, color: Colors.black)),
            const SizedBox(height: 4),
            Text('tap →',
                style: AppText.label(9, color: Colors.black.withOpacity(0.55))),
          ],
        ),
      ),
    );
  }

  Widget _viewOnlyStub() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('VIEW', style: AppText.display(14, color: Colors.black)),
          const SizedBox(height: 4),
          Text('only', style: AppText.label(9, color: Colors.black.withOpacity(0.55))),
        ],
      ),
    );
  }
}

class _HorizontalDashedLinePainter extends CustomPainter {
  final Color color;
  _HorizontalDashedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const dashLen = 4.0;
    const gapLen = 4.0;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + dashLen, 0), paint);
      x += dashLen + gapLen;
    }
  }

  @override
  bool shouldRepaint(_HorizontalDashedLinePainter old) => old.color != color;
}

/// Caller's session score, presented in the same torn cream stock as the
/// member tickets below — just so it reads as part of the same visual
/// family. Wording matches the old red ScoreBanner: small caps label, big
/// `+score`, exact/in-top-N/miss breakdown subtitle.
class _YourScoreTicket extends StatelessWidget {
  final int score;
  final String subtitle;
  const _YourScoreTicket({required this.score, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return TicketCard(
      tear: TicketTear.ghosted,
      bodyPadding: const EdgeInsets.fromLTRB(
          Spacing.lg, Spacing.md, Spacing.xl, Spacing.md),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('YOUR SCORE',
              style: AppText.label(10,
                  color: Colors.black.withOpacity(0.7))),
          const SizedBox(height: 4),
          Text('+$score',
              style: AppText.display(36, color: Colors.black)),
          const SizedBox(height: 4),
          Text(subtitle,
              style: AppText.body(12,
                  color: Colors.black.withOpacity(0.7))),
        ],
      ),
    );
  }
}

/// Ticket showing one league member's picks for this session. Cream stock
/// with the stub torn off — they no longer get to edit, but you can see
/// what they played.
class _MemberPickTicket extends StatelessWidget {
  final MemberPrediction member;
  const _MemberPickTicket({required this.member});

  @override
  Widget build(BuildContext context) {
    final empty = member.picks.isEmpty;
    final pts = member.pointsTotal;
    return TicketCard(
      tear: TicketTear.ghosted,
      bodyPadding: const EdgeInsets.fromLTRB(
          Spacing.lg, Spacing.md, Spacing.xl, Spacing.md),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(member.displayName.toUpperCase(),
                    overflow: TextOverflow.ellipsis,
                    style: AppText.display(15, color: Colors.black)),
              ),
              if (pts != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: pts > 0 ? BrandColors.ok : Colors.black,
                    borderRadius:
                        const BorderRadius.all(Radius.circular(6)),
                  ),
                  child: Text('+$pts',
                      style: AppText.label(9,
                          color: pts > 0 ? Colors.black : Colors.white)),
                ),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          if (empty)
            Text('No picks for this session',
                style: AppText.body(12,
                    color: Colors.black.withOpacity(0.55))
                    .copyWith(fontStyle: FontStyle.italic))
          else
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                for (final p in member.picks)
                  _MemberPickChip(position: p.position, driverCode: p.driverCode),
              ],
            ),
        ],
      ),
    );
  }
}

class _MemberPickChip extends StatelessWidget {
  final int position;
  final String driverCode;
  const _MemberPickChip({required this.position, required this.driverCode});

  @override
  Widget build(BuildContext context) {
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
}
