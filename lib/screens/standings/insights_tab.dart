// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import '../../api/models/leaderboard_row.dart';
import '../../api/models/my_score.dart';
import '../../api/models/session_leaderboard_row.dart';
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
    final leagueId = leagues.isEmpty ? null : leagues.first.id;
    final leaderboard = leagueId == null
        ? const <LeaderboardRow>[]
        : await scope.api.leagueLeaderboard(leagueId);
    final sessions = leagueId == null
        ? const <SessionLeaderboardRow>[]
        : await scope.api.leagueSessionBreakdown(leagueId);
    return _InsightsData(
        myUserId: myUserId, scores: scores, leaderboard: leaderboard, sessions: sessions);
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
        final trajectorySeries = _buildTrajectorySeries(d);
        final trajectoryLabels = _trajectoryXLabels(d);
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
                child: trajectorySeries.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(Spacing.lg),
                        child: Text(
                          'No scored rounds yet.',
                          style: AppText.body(12, color: t.colorScheme.onSurface.withOpacity(0.6)),
                        ),
                      )
                    : TrajectoryChart(
                        series: trajectorySeries,
                        xLabels: trajectoryLabels,
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

  List<ChartSeries> _buildTrajectorySeries(_InsightsData d) {
    // Backend returns desc by scheduledStart; flip to ascending for chronological plotting.
    final sessions = [...d.sessions]..sort((a, b) => a.scheduledStart.compareTo(b.scheduledStart));
    if (sessions.isEmpty) return const [];

    final pointsByMemberPerSession = <Map<String, int>>[
      for (final s in sessions) { for (final m in s.members) m.userId: m.pointsTotal },
    ];
    final names = <String, String>{};
    for (final s in sessions) {
      for (final m in s.members) {
        names.putIfAbsent(m.userId, () => m.displayName);
      }
    }

    // Selection: top 3 of current leaderboard + me + (if I'm not in the top 3)
    // my immediate neighbors above & below me in the standings.
    final leaderboard = [...d.leaderboard]..sort((a, b) => b.pointsTotal.compareTo(a.pointsTotal));
    final selected = <String>{};
    for (var i = 0; i < leaderboard.length && i < 3; i++) {
      selected.add(leaderboard[i].userId);
    }
    if (d.myUserId != null) {
      selected.add(d.myUserId!);
      final myIdx = leaderboard.indexWhere((r) => r.userId == d.myUserId);
      if (myIdx >= 3) {
        if (myIdx - 1 >= 0) selected.add(leaderboard[myIdx - 1].userId);
        if (myIdx + 1 < leaderboard.length) selected.add(leaderboard[myIdx + 1].userId);
      }
    }

    // Plot order: caller first (accent), then everyone else in leaderboard rank order.
    final ordered = [
      if (d.myUserId != null && selected.contains(d.myUserId)) d.myUserId!,
      ...leaderboard
          .map((r) => r.userId)
          .where((id) => selected.contains(id) && id != d.myUserId),
    ];

    const palette = [
      BrandColors.accent,
      Color(0xFF6B6F76),
      Color(0xFFB58A3A),
      Color(0xFF4A7B8C),
      Color(0xFF8E5A7B),
      Color(0xFF5C8C4A),
      Color(0xFF8C5A4A),
    ];
    return [
      for (var i = 0; i < ordered.length; i++)
        ChartSeries(
          label: ordered[i] == d.myUserId ? 'You' : (names[ordered[i]] ?? '—'),
          color: palette[i % palette.length],
          points: _cumulativePoints(pointsByMemberPerSession, ordered[i]),
        ),
    ];
  }

  List<double> _cumulativePoints(List<Map<String, int>> perSession, String userId) {
    var cum = 0.0;
    return [
      for (final m in perSession) cum += (m[userId] ?? 0).toDouble(),
    ];
  }

  List<String> _trajectoryXLabels(_InsightsData d) {
    final sessions = [...d.sessions]..sort((a, b) => a.scheduledStart.compareTo(b.scheduledStart));
    return [
      for (final s in sessions) 'R${s.eventRound}·${_typeAbbrev(s.sessionType)}',
    ];
  }

  String _typeAbbrev(String t) {
    switch (t) {
      case 'race':         return 'R';
      case 'qualifying':   return 'Q';
      case 'sprint':       return 'S';
      case 'sprint_quali': return 'SQ';
      default:             return t.toUpperCase().substring(0, t.length < 2 ? 1 : 2);
    }
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
  final List<SessionLeaderboardRow> sessions;
  _InsightsData({
    required this.myUserId,
    required this.scores,
    required this.leaderboard,
    required this.sessions,
  });
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

class _Fact {
  final String emblem;
  final String text;
  const _Fact(this.emblem, this.text);
}
