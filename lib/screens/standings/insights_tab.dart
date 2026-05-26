// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import '../../api/models/leaderboard_row.dart';
import '../../api/models/my_score.dart';
import '../../components/app_card.dart';
import '../../components/error_view.dart';
import '../../components/fact_card.dart';
import '../../components/trajectory_chart.dart';
import '../../state/app_state.dart';
import '../../theme/colors.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';

class InsightsTab extends StatefulWidget {
  const InsightsTab({super.key});

  @override
  State<InsightsTab> createState() => _InsightsTabState();
}

class _InsightsTabState extends State<InsightsTab> {
  Future<_InsightsData>? _data;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _data ??= _load();
  }

  Future<_InsightsData> _load() async {
    final scope = AppState.of(context);
    final myUserId = scope.auth.currentUserId;
    final leagues = scope.auth.leagues;
    final scores = await scope.api.myScores();
    final leaderboard = leagues.isEmpty
        ? const <LeaderboardRow>[]
        : await scope.api.leagueLeaderboard(leagues.first.id);
    return _InsightsData(myUserId: myUserId, scores: scores, leaderboard: leaderboard);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return FutureBuilder<_InsightsData>(
      future: _data,
      builder: (_, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return ErrorView(
            error: snap.error!,
            stack: snap.stackTrace,
            where: 'Insights',
            onRetry: () => setState(() => _data = _load()),
          );
        }
        final d = snap.data!;
        final stats = _computeStats(d);
        final trajectory = _buildTrajectory(d);
        final facts = _buildFacts(d, stats);

        return ListView(
          padding: const EdgeInsets.only(bottom: Spacing.xxl),
          children: [
            _h('YOUR SEASON'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: _stat(t, 'TOTAL POINTS', '${stats.totalPoints}', stats.rankLabel, accent: true)),
                      const SizedBox(width: 6),
                      Expanded(child: _stat(t, 'AVERAGE / ROUND', stats.avgLabel, stats.leagueAvgLabel)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(child: _stat(t, 'HIT RATE', stats.hitRateLabel, stats.hitRateSub)),
                      const SizedBox(width: 6),
                      Expanded(child: _stat(t, 'BEST ROUND', stats.bestLabel, stats.bestSub)),
                    ],
                  ),
                ],
              ),
            ),
            _h('TRAJECTORY'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
              child: AppCard(
                child: trajectory == null
                    ? Padding(
                        padding: const EdgeInsets.all(Spacing.lg),
                        child: Text(
                          'No scored rounds yet.',
                          style: AppText.body(12, color: t.colorScheme.onSurface.withOpacity(0.6)),
                        ),
                      )
                    : TrajectoryChart(
                        series: [
                          ChartSeries(
                            label: 'You',
                            color: BrandColors.accent,
                            points: [for (final p in trajectory.points) p.toDouble()],
                          ),
                        ],
                        xLabels: trajectory.labels,
                      ),
              ),
            ),
            if (facts.isNotEmpty) ...[
              _h('LEAGUE GOSSIP'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
                child: Column(
                  children: [
                    for (var i = 0; i < facts.length; i++) ...[
                      if (i > 0) const SizedBox(height: 6),
                      FactCard(emblem: facts[i].emblem, text: facts[i].text),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  // -------- computation --------

  _Stats _computeStats(_InsightsData d) {
    // Aggregate scores per event (round) for the current user.
    final perEvent = <int, int>{};
    for (final s in d.scores) {
      perEvent.update(s.eventRound, (v) => v + s.pointsTotal, ifAbsent: () => s.pointsTotal);
    }
    final totalPoints = perEvent.values.fold<int>(0, (a, b) => a + b);
    final eventCount = perEvent.length;
    final avg = eventCount == 0 ? 0.0 : totalPoints / eventCount;

    // Rank within league
    final me = d.myUserId;
    int? myRank;
    if (me != null && d.leaderboard.isNotEmpty) {
      final sorted = [...d.leaderboard]..sort((a, b) => b.pointsTotal.compareTo(a.pointsTotal));
      final idx = sorted.indexWhere((r) => r.userId == me);
      if (idx >= 0) myRank = idx + 1;
    }
    final rankLabel = myRank == null
        ? '—'
        : '${_ordinal(myRank)} of ${d.leaderboard.length}';

    // League average (per round)
    String leagueAvgLabel = '—';
    if (d.leaderboard.isNotEmpty) {
      final totalLeague = d.leaderboard.fold<int>(0, (a, r) => a + r.pointsTotal);
      final totalSessions = d.leaderboard.fold<int>(0, (a, r) => a + r.sessionsScored);
      if (totalSessions > 0) {
        final lAvg = totalLeague / totalSessions;
        leagueAvgLabel = 'league avg ${lAvg.toStringAsFixed(1)}';
      }
    }

    // Hit rate: count exact picks vs total picks across all my scored sessions.
    var exactCount = 0;
    var pickCount = 0;
    for (final s in d.scores) {
      for (final p in s.breakdown.perPosition) {
        pickCount += 1;
        if (p.exact) exactCount += 1;
      }
    }
    final hitRateLabel = pickCount == 0 ? '—' : '${(100 * exactCount / pickCount).round()}%';
    final hitRateSub = pickCount == 0 ? '0 picks scored' : '$exactCount of $pickCount picks';

    // Best round
    int? bestRound;
    int bestPts = 0;
    String? bestName;
    perEvent.forEach((round, pts) {
      if (pts > bestPts) {
        bestPts = pts;
        bestRound = round;
      }
    });
    if (bestRound != null) {
      bestName = d.scores
          .firstWhere((s) => s.eventRound == bestRound, orElse: () => d.scores.first)
          .eventName;
    }
    final bestLabel = bestRound == null ? '—' : '+$bestPts';
    final bestSub = bestRound == null ? 'no scored round yet' : '$bestName · R$bestRound';

    return _Stats(
      totalPoints: totalPoints,
      avgLabel: eventCount == 0 ? '—' : avg.toStringAsFixed(1),
      rankLabel: rankLabel,
      leagueAvgLabel: leagueAvgLabel,
      hitRateLabel: hitRateLabel,
      hitRateSub: hitRateSub,
      bestLabel: bestLabel,
      bestSub: bestSub,
    );
  }

  _Trajectory? _buildTrajectory(_InsightsData d) {
    if (d.scores.isEmpty) return null;
    // Group by event round (chronological from data), accumulate cumulative.
    final byRound = <int, MyScore>{};
    final eventTotals = <int, int>{};
    for (final s in d.scores) {
      eventTotals.update(s.eventRound, (v) => v + s.pointsTotal, ifAbsent: () => s.pointsTotal);
      byRound.putIfAbsent(s.eventRound, () => s);
    }
    final rounds = byRound.keys.toList()..sort();
    final labels = [for (final r in rounds) 'R$r'];
    var cum = 0;
    final points = [for (final r in rounds) cum += eventTotals[r]!];
    return _Trajectory(labels: labels, points: points);
  }

  List<_Fact> _buildFacts(_InsightsData d, _Stats stats) {
    final facts = <_Fact>[];
    final lb = d.leaderboard;
    if (lb.isNotEmpty) {
      final sorted = [...lb]..sort((a, b) => b.pointsTotal.compareTo(a.pointsTotal));
      final leader = sorted.first;
      if (leader.pointsTotal > 0 && leader.userId != d.myUserId) {
        facts.add(_Fact('★', '${leader.displayName} leads the league with ${leader.pointsTotal} pts.'));
      } else if (leader.userId == d.myUserId && leader.pointsTotal > 0) {
        facts.add(_Fact('★', "You're leading the league with ${leader.pointsTotal} pts."));
      }
      if (sorted.length >= 2) {
        final gap = sorted[0].pointsTotal - sorted[1].pointsTotal;
        if (gap > 0) {
          facts.add(_Fact('≈', '$gap-point gap between 1st and 2nd.'));
        }
      }
    }
    if (d.scores.isEmpty) {
      facts.add(const _Fact('?', 'No scored sessions yet — once a race finishes, stats land here.'));
    }
    return facts;
  }

  String _ordinal(int n) {
    if (n % 100 >= 11 && n % 100 <= 13) return '${n}th';
    switch (n % 10) {
      case 1: return '${n}st';
      case 2: return '${n}nd';
      case 3: return '${n}rd';
      default: return '${n}th';
    }
  }

  // -------- UI helpers --------

  Widget _h(String s) => Padding(
        padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.lg, Spacing.lg, Spacing.xs),
        child: Text(s, style: AppText.label(11)),
      );

  Widget _stat(ThemeData t, String label, String value, String extra, {bool accent = false}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(Spacing.md, Spacing.sm, Spacing.md, Spacing.sm),
      decoration: BoxDecoration(
        color: accent ? BrandColors.accent : null,
        border: Border.all(color: Colors.black, width: 2),
        borderRadius: const BorderRadius.all(Radius.circular(12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppText.label(
              9,
              color: accent
                  ? Colors.white.withOpacity(0.9)
                  : t.colorScheme.onSurface.withOpacity(0.55),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: AppText.display(24, color: accent ? Colors.white : t.colorScheme.onSurface),
          ),
          Text(
            extra,
            style: AppText.body(
              10,
              color: accent
                  ? Colors.white.withOpacity(0.85)
                  : t.colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }
}

class _InsightsData {
  final String? myUserId;
  final List<MyScore> scores;
  final List<LeaderboardRow> leaderboard;
  _InsightsData({required this.myUserId, required this.scores, required this.leaderboard});
}

class _Stats {
  final int totalPoints;
  final String avgLabel;
  final String rankLabel;
  final String leagueAvgLabel;
  final String hitRateLabel;
  final String hitRateSub;
  final String bestLabel;
  final String bestSub;
  const _Stats({
    required this.totalPoints,
    required this.avgLabel,
    required this.rankLabel,
    required this.leagueAvgLabel,
    required this.hitRateLabel,
    required this.hitRateSub,
    required this.bestLabel,
    required this.bestSub,
  });
}

class _Trajectory {
  final List<String> labels;
  final List<int> points;
  const _Trajectory({required this.labels, required this.points});
}

class _Fact {
  final String emblem;
  final String text;
  const _Fact(this.emblem, this.text);
}
