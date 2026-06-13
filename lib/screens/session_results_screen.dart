// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../api/api_client.dart';
import '../api/models/event.dart';
import '../api/models/member_prediction.dart';
import '../api/models/session.dart';
import '../api/models/live_snapshot.dart';
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
            final currentIdx =
                chronological.indexWhere((e) => e.sessionId == active.id);
            final prev = currentIdx > 0 ? chronological[currentIdx - 1] : null;
            final next =
                currentIdx >= 0 && currentIdx < chronological.length - 1
                    ? chronological[currentIdx + 1]
                    : null;

            return SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: Spacing.xxl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(event, active, t, prev: prev, next: next),
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
      if (!_displayableTypes.contains(s.type)) continue;
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
              score: score,
              subtitle: payload.picks.isEmpty
                  ? 'No picks for this session'
                  : '$exactCount exact · $nearCount in top-$topN · $missCount miss',
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
            child: Column(
              children: [
                // Column header strip — mirrors the predict-screen header
                // (FP1/FP2/BEST) so the right-side columns are named even
                // on rows where the badge/glyph happen to be empty.
                _ClassificationHeader(t: t),
                // Single outer border around the classification, internal
                // dividers between rows. Outcome tints (green = exact, amber
                // = in-topN, neutral highlight = miss) survive as row
                // backgrounds — they carry the information.
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: t.strokeColor, width: Strokes.card),
                    borderRadius: Radii.rLg,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: List.generate(payload.result.length, (i) {
                      final r = payload.result[i];
                      final isLast = i == payload.result.length - 1;
                      final slot = payload.picks.indexOf(r.driverCode);
                      final pickedSlot = slot == -1 ? null : slot + 1;
                      final outcome = pickedSlot == null
                          ? null
                          : outcomeFor(
                              r.driverCode, pickedSlot, payload.result, topN);
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
                                      color: t.strokeColor.withOpacity(0.25),
                                      width: 1),
                                ),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: _kPosCol,
                              child:
                                  Text('${r.position}', style: AppText.display(13)),
                            ),
                            const SizedBox(width: Spacing.xs),
                            // Inset team-color bar — matches the DriverSectorRow
                            // and the top P-slot anatomy.
                            Container(
                              width: 5,
                              height: 22,
                              decoration: BoxDecoration(
                                color: teamColor(r.constructorId),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: Spacing.sm),
                            SizedBox(
                              width: _kCodeCol,
                              child: Text(r.driverCode,
                                  style: AppText.body(12, weight: FontWeight.w800)),
                            ),
                            Expanded(
                              child: Text(r.driverName,
                                  style: AppText.body(12, weight: FontWeight.w500)),
                            ),
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
                                displayTime(r, session.type),
                                style: AppText.display(11,
                                    color: t.colorScheme.onSurface.withOpacity(0.6)),
                                textAlign: TextAlign.right,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (isPickable && payload.leagueMemberPredictions.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Spacing.lg, Spacing.xl, Spacing.lg, Spacing.xs),
            child: Text('LEAGUE PICKS',
                style: AppText.label(11,
                    color: t.colorScheme.onSurface.withOpacity(0.6))),
          ),
          for (final m in payload.leagueMemberPredictions)
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
      ],
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
    final typeLabel =
        _typeLabels[session.type] ?? session.type.name.toUpperCase();
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
                style:
                    AppText.label(10, color: Colors.black.withOpacity(0.65))),
          ],
        ),
        const SizedBox(height: Spacing.sm),
        Text(event.name.toUpperCase(),
            style: AppText.display(22, color: Colors.black)),
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
                  style:
                      AppText.label(10, color: Colors.black.withOpacity(0.55))),
              const SizedBox(width: 8),
              Countdown(target: session.scheduledStart, size: 22),
            ],
          ),
        ],
        const SizedBox(height: Spacing.md),
        // Inner horizontal perforation separating the event info from the picks.
        CustomPaint(
          size: const Size.fromHeight(1),
          painter: _HorizontalDashedLinePainter(
              color: Colors.black.withOpacity(0.4)),
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
            style: AppText.body(12, color: Colors.black.withOpacity(0.55))
                .copyWith(fontStyle: FontStyle.italic),
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.1),
                        borderRadius:
                            const BorderRadius.all(Radius.circular(4)),
                      ),
                      child: Text('P${i + 1}',
                          style: AppText.label(9,
                              color: Colors.black.withOpacity(0.7))),
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
      bodyPadding: const EdgeInsets.fromLTRB(
          Spacing.lg, Spacing.lg, Spacing.lg, Spacing.lg),
      stubPadding: const EdgeInsets.symmetric(
          horizontal: Spacing.sm, vertical: Spacing.md),
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
          Text('only',
              style: AppText.label(9, color: Colors.black.withOpacity(0.55))),
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
              style: AppText.label(10, color: Colors.black.withOpacity(0.7))),
          const SizedBox(height: 4),
          Text('+$score', style: AppText.display(36, color: Colors.black)),
          const SizedBox(height: 4),
          Text(subtitle,
              style: AppText.body(12, color: Colors.black.withOpacity(0.7))),
        ],
      ),
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
                  Wrap(
                    spacing: Spacing.md,
                    runSpacing: 4,
                    children: [
                      for (final p in picksSorted)
                        _MemberFormPick(
                          position: p.position,
                          driverCode: p.driverCode,
                          outcome: result.isEmpty
                              ? null
                              : outcomeFor(
                                  p.driverCode, p.position, result, topN),
                        ),
                    ],
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
  final SessionType sessionType;
  final List<String> myPicks;
  final LiveSnapshot snap;
  const LiveResultsBody({
    super.key,
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
          score: myPts ?? 0,
          subtitle: myPts == null
              ? 'No picks for this session'
              : 'projected · $badge',
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
