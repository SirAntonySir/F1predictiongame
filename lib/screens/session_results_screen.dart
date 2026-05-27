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
import '../components/error_view.dart';
import '../components/score_banner.dart';
import '../components/session_chip.dart';
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
// the calendar drill-down. With no picks, the ScoreBanner just reads "No picks
// for this session" and the FULL CLASSIFICATION renders normally.
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
  Future<Event>? _eventFuture;
  Future<int?>? _overallNextSessionIdFuture;
  int? _activeSessionId;
  final Map<int, Future<_SessionPayload>> _payloads = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final api = AppState.of(context).api;
    _eventFuture ??= api.event(widget.round);
    // The /predict screen always loads whichever session is *globally* next,
    // not the one the user is looking at on this page. We use this id to gate
    // the PICK/EDIT CTA so the button only appears when /predict will actually
    // open the same session the user is viewing.
    _overallNextSessionIdFuture ??= api.nextSession().then<int?>((s) => s.id).catchError((_) => null);
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
      final overallNextId = await (_overallNextSessionIdFuture ?? Future.value(null));
      return _SessionPayload(
        result: result,
        picks: picks,
        backendScore: backendScore,
        overallNextSessionId: overallNextId,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      backgroundColor: t.colorScheme.surface,
      body: SafeArea(
        child: FutureBuilder<Event>(
          future: _eventFuture,
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
                  _eventFuture = AppState.of(context).api.event(widget.round);
                  _payloads.clear();
                }),
              );
            }
            final event = snap.data!;
            final sessions = event.sessions
                .where((s) => _pickableTypes.contains(s.type))
                .toList()
              ..sort((a, b) => a.scheduledStart.compareTo(b.scheduledStart));
            if (sessions.isEmpty) {
              return _header(event, null, t);
            }
            final active = sessions.firstWhere(
              (s) => s.id == _activeSessionId,
              orElse: () => sessions.last,
            );
            return SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: Spacing.xxl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(event, active, t),
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
            );
          },
        ),
      ),
    );
  }

  Widget _header(Event event, Session? active, ThemeData t) {
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
              isGloballyNext: payload.overallNextSessionId == session.id,
            ),
          ),
        ] else ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
            child: ScoreBanner(
              label: 'Your score',
              value: '+$score',
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
  final int? overallNextSessionId;
  _SessionPayload({
    required this.result,
    required this.picks,
    this.backendScore,
    this.overallNextSessionId,
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
  /// True when this session is the *globally* next-upcoming pickable session.
  /// The /predict screen always loads the global-next session, so we only show
  /// the PICK/EDIT button when those match — otherwise the button would take
  /// the user to a different session than the one they're looking at.
  final bool isGloballyNext;
  const _FutureSessionHero({
    required this.event,
    required this.session,
    required this.picks,
    required this.isGloballyNext,
  });

  bool get _isPickable => _pickableTypes.contains(session.type);

  Session? get _nextSession {
    final now = DateTime.now();
    Session? best;
    for (final s in event.sessions) {
      if (s.scheduledStart.isBefore(now)) continue;
      if (best == null || s.scheduledStart.isBefore(best.scheduledStart)) {
        best = s;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final flag = flagFor(event.country);
    final dateLabel = DateFormat('EEE d MMM').format(session.scheduledStart);
    final timeLabel = DateFormat('HH:mm').format(session.scheduledStart);
    final typeLabel = _typeLabels[session.type] ?? session.type.name.toUpperCase();
    final inFuture = session.scheduledStart.isAfter(DateTime.now());
    final nextSession = _nextSession;

    return AppCard(
      background: t.mutedSurface,
      padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.lg, Spacing.lg, Spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  '${flag != null ? '$flag  ' : ''}${event.country.toUpperCase()} · ROUND ${event.round}',
                  style: AppText.label(10, color: t.colorScheme.onSurface.withOpacity(0.6)),
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Text(typeLabel,
                  style: AppText.label(10, color: t.colorScheme.onSurface.withOpacity(0.6))),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          Text(event.name.toUpperCase(), style: AppText.display(22)),
          const SizedBox(height: Spacing.xs),
          Text(
            '$dateLabel · $timeLabel · ${event.circuitName}',
            style: AppText.body(12, color: t.colorScheme.onSurface.withOpacity(0.7)),
          ),
          if (inFuture) ...[
            const SizedBox(height: Spacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('STARTS IN',
                    style: AppText.label(10, color: t.colorScheme.onSurface.withOpacity(0.55))),
                const SizedBox(width: 8),
                Countdown(target: session.scheduledStart, size: 22),
              ],
            ),
          ],
          const SizedBox(height: Spacing.md),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _scheduleChips(nextSession?.id),
          ),
          const SizedBox(height: Spacing.lg),
          _pickPanel(context, t),
        ],
      ),
    );
  }

  List<Widget> _scheduleChips(int? nextId) {
    // Practice sessions aren't scorable, so they don't earn a chip in this hero.
    final order = [
      SessionType.qualifying,
      SessionType.sprint_quali,
      SessionType.sprint,
      SessionType.race,
    ];
    final labels = {
      SessionType.qualifying: 'QUALI',
      SessionType.sprint_quali: 'SQ',
      SessionType.sprint: 'SPRINT',
      SessionType.race: 'RACE',
    };
    final out = <Widget>[];
    for (final type in order) {
      final s = event.sessions.firstWhere(
        (x) => x.type == type,
        orElse: () => session,
      );
      if (s.type != type) continue;
      final state = s.status == SessionStatus.finished
          ? ChipState.done
          : (s.id == nextId ? ChipState.next : ChipState.idle);
      out.add(SessionChip(label: labels[type]!, state: state));
    }
    return out;
  }

  Widget _pickPanel(BuildContext context, ThemeData t) {
    final hasPicks = picks.isNotEmpty;
    final empty = !hasPicks;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.md),
      decoration: BoxDecoration(
        color: t.colorScheme.surface,
        border: Border.all(color: t.strokeColor, width: 1.5),
        borderRadius: const BorderRadius.all(Radius.circular(10)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  empty
                      ? (_isPickable ? 'YOUR PICK · DRAFT' : 'YOUR PICK')
                      : 'YOUR PICK',
                  style: AppText.label(10, color: t.colorScheme.onSurface.withOpacity(0.6)),
                ),
                const SizedBox(height: 6),
                if (empty)
                  Text(
                    _isPickable
                        ? 'No picks yet'
                        : 'No predictions for this session',
                    style: AppText.body(12, color: t.colorScheme.onSurface.withOpacity(0.55)),
                  )
                else
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (var i = 0; i < picks.length; i++)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('P${i + 1}',
                                style: AppText.label(9,
                                    color: t.colorScheme.onSurface.withOpacity(0.5))),
                            const SizedBox(width: 4),
                            Text(picks[i],
                                style: AppText.body(13, weight: FontWeight.w800)),
                            if (i < picks.length - 1)
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: Text('·',
                                    style: AppText.body(13,
                                        color: t.colorScheme.onSurface.withOpacity(0.4))),
                              ),
                          ],
                        ),
                    ],
                  ),
              ],
            ),
          ),
          if (_isPickable && isGloballyNext) ...[
            const SizedBox(width: Spacing.sm),
            FilledButton(
              onPressed: () => context.go('/predict'),
              style: FilledButton.styleFrom(
                backgroundColor: empty ? BrandColors.accent : Colors.black,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 10),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                ),
              ),
              child: Text(empty ? 'PICK' : 'EDIT',
                  style: AppText.label(10, color: Colors.white)),
            ),
          ],
        ],
      ),
    );
  }
}
