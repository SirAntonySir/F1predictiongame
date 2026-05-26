// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../api/api_client.dart';
import '../api/models/event.dart';
import '../api/models/session.dart';
import '../api/models/session_result.dart';
import '../components/app_card.dart';
import '../components/error_view.dart';
import '../components/score_banner.dart';
import '../domain/prediction.dart';
import '../domain/result_display.dart';
import '../domain/scoring.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/team_colors.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

// Sprint Quali is disabled — see predict_screen.dart. The session still exists
// in the calendar but we don't surface a results sub-tab for it because there
// were no picks to compare. Re-enable by uncommenting the sprint_quali entries.
const _pickableTypes = {
  SessionType.qualifying,
  // SessionType.sprint_quali,
  SessionType.sprint,
  SessionType.race,
};

const _typeLabels = {
  SessionType.qualifying: 'QUALI',
  // SessionType.sprint_quali: 'SPRINT QUALI',
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
  int? _activeSessionId;
  final Map<int, Future<_SessionPayload>> _payloads = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _eventFuture ??= AppState.of(context).api.event(widget.round);
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
      return _SessionPayload(result: result, picks: picks, backendScore: backendScore);
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
  final Session session;
  final _SessionPayload payload;
  const _Body({required this.session, required this.payload});

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
      // Sprint Quali disabled — see top of file.
      // case SessionType.sprint_quali:
      //   return scoreSprintQualifying(payload.picks, payload.result);
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
            child: AppCard(
              background: t.mutedSurface,
              padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.lg, vertical: Spacing.xxl),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('RESULTS NOT IN YET',
                        style: AppText.label(11,
                            color: t.colorScheme.onSurface.withOpacity(0.6))),
                    const SizedBox(height: Spacing.sm),
                    Text(
                      "Come back after the chequered flag.",
                      style: AppText.body(13,
                          color: t.colorScheme.onSurface.withOpacity(0.7)),
                    ),
                  ],
                ),
              ),
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
  _SessionPayload({required this.result, required this.picks, this.backendScore});
}
