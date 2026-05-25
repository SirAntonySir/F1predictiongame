// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../api/models/event.dart';
import '../api/models/session_result.dart';
import '../components/app_card.dart';
import '../components/score_banner.dart';
import '../domain/scoring.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/team_colors.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

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
  Future<_RaceData>? _data;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _data ??= _load();
  }

  Future<_RaceData> _load() async {
    final scope = AppState.of(context);
    final event = await scope.api.event(widget.round);
    final result = await scope.api.sessionResults(widget.sessionId);
    final myPicks = scope.predictions.picksFor(
      userId: scope.auth.currentUserId ?? 'anton',
      sessionId: widget.sessionId,
    );
    return _RaceData(event: event, result: result, myPicks: myPicks);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      backgroundColor: t.colorScheme.surface,
      body: SafeArea(
        child: FutureBuilder<_RaceData>(
          future: _data,
          builder: (_, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) return Center(child: Text('${snap.error}'));
            final d = snap.data!;
            final score = scoreRace(d.myPicks, d.result);
            final picksHits = d.myPicks
                .asMap()
                .entries
                .map((e) => (
                      slot: e.key + 1,
                      code: e.value,
                      outcome: outcomeFor(e.value, e.key + 1, d.result, 5),
                    ))
                .toList();
            return SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: Spacing.xxl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        Spacing.lg, Spacing.lg, Spacing.lg, Spacing.sm),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => context.pop(),
                          icon: const Icon(Icons.arrow_back_ios_new, size: 16),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(d.event.name, style: AppText.display(20)),
                              Text(
                                'Round ${d.event.round} · Race',
                                style: AppText.label(
                                    10,
                                    color: t.colorScheme.onSurface
                                        .withOpacity(0.55)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: Spacing.lg),
                    child: ScoreBanner(
                      label: 'Your score',
                      value: '+$score',
                      subtitle:
                          '${picksHits.where((p) => p.outcome == PickOutcome.exact).length} exact · ${picksHits.where((p) => p.outcome == PickOutcome.inTopN).length} in top-5 · ${picksHits.where((p) => p.outcome == PickOutcome.miss).length} miss',
                    ),
                  ),
                  if (d.myPicks.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                          Spacing.lg, Spacing.lg, Spacing.lg, Spacing.xs),
                      child: Text(
                        'PICK VS RESULT',
                        style: AppText.label(11,
                            color: t.colorScheme.onSurface.withOpacity(0.6)),
                      ),
                    ),
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: Spacing.lg),
                      child: AppCard(
                        padding: EdgeInsets.zero,
                        child: Column(
                          children: picksHits.map((p) {
                            final actual = d.result.firstWhere(
                              (r) => r.position == p.slot,
                              orElse: () => d.result.first,
                            );
                            final color = switch (p.outcome) {
                              PickOutcome.exact => BrandColors.ok,
                              PickOutcome.inTopN => BrandColors.near,
                              PickOutcome.miss => Colors.black,
                            };
                            final glyph = switch (p.outcome) {
                              PickOutcome.exact => '✓',
                              PickOutcome.inTopN => '~',
                              PickOutcome.miss => '✗',
                            };
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: Spacing.md, vertical: 8),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 24,
                                    child: Text('P${p.slot}',
                                        style: AppText.display(14)),
                                  ),
                                  Expanded(
                                    child: Text(p.code,
                                        style: AppText.body(13,
                                            weight: FontWeight.w700)),
                                  ),
                                  Container(
                                    width: 22,
                                    height: 22,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                        color: color, shape: BoxShape.circle),
                                    child: Text(
                                      glyph,
                                      style: TextStyle(
                                        color: p.outcome == PickOutcome.miss
                                            ? Colors.white
                                            : Colors.black,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(actual.driverCode,
                                        textAlign: TextAlign.right,
                                        style: AppText.body(13,
                                            weight: FontWeight.w700)),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        Spacing.lg, Spacing.lg, Spacing.lg, Spacing.xs),
                    child: Text(
                      'FULL CLASSIFICATION',
                      style: AppText.label(11,
                          color: t.colorScheme.onSurface.withOpacity(0.6)),
                    ),
                  ),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: Spacing.lg),
                    child: AppCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: d.result.map((r) {
                          final mine = d.myPicks.contains(r.driverCode);
                          return Container(
                            color: mine ? t.rowHighlight : null,
                            padding: const EdgeInsets.symmetric(
                                horizontal: Spacing.md, vertical: 7),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 22,
                                  child: Text('${r.position}',
                                      style: AppText.display(13)),
                                ),
                                Container(
                                    width: 3,
                                    height: 18,
                                    color: teamColor(r.constructorId)),
                                const SizedBox(width: Spacing.sm),
                                SizedBox(
                                  width: 44,
                                  child: Text(
                                    r.driverCode,
                                    style: AppText.body(12,
                                        weight: FontWeight.w800),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    r.driverName,
                                    style: AppText.body(12,
                                        weight: FontWeight.w500),
                                  ),
                                ),
                                Text(r.raceTime ?? '',
                                    style: AppText.display(11,
                                        color: t.colorScheme.onSurface
                                            .withOpacity(0.6))),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RaceData {
  final Event event;
  final List<SessionResult> result;
  final List<String> myPicks;
  _RaceData(
      {required this.event, required this.result, required this.myPicks});
}
