import 'package:flutter/material.dart';
import '../../api/models/leaderboard_row.dart';
import '../../components/app_card.dart';
import '../../components/error_view.dart';
import '../../components/league_row.dart';
import '../../components/trend_badge.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';

class LeagueTab extends StatefulWidget {
  const LeagueTab({super.key});

  @override
  State<LeagueTab> createState() => _LeagueTabState();
}

class _LeagueTabState extends State<LeagueTab> {
  Future<List<LeaderboardRow>>? _data;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _data ??= _load();
  }

  Future<List<LeaderboardRow>> _load() async {
    final scope = AppState.of(context);
    final leagues = scope.auth.leagues;
    if (leagues.isEmpty) return const [];
    return scope.api.leagueLeaderboard(leagues.first.id);
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppState.of(context);
    return FutureBuilder<List<LeaderboardRow>>(
      future: _data,
      builder: (_, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return ErrorView(
            error: snap.error!,
            stack: snap.stackTrace,
            where: 'League standings',
            onRetry: () => setState(() => _data = _load()),
          );
        }
        final rows = snap.data!;
        if (rows.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(Spacing.lg),
              child: Text('No scores yet — once a session finishes, the leaderboard fills in.'),
            ),
          );
        }
        final me = scope.auth.currentUserId;
        return ListView(
          padding: const EdgeInsets.only(bottom: Spacing.xxl),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.md, Spacing.lg, 0),
              child: _Podium(rows: rows.take(3).toList()),
            ),
            const SizedBox(height: Spacing.md),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
              child: AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: List.generate(rows.length, (i) {
                    final r = rows[i];
                    final isMe = r.userId == me;
                    return LeagueRow(
                      rank: i + 1,
                      name: isMe ? '${r.displayName} (you)' : r.displayName,
                      inSeasonPoints: r.inSeasonPoints,
                      preseasonPoints: r.preseasonPoints,
                      pointsTotal: r.pointsTotal,
                      trend: TrendDirection.equal,
                      isMe: isMe,
                    );
                  }),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Podium extends StatelessWidget {
  final List<LeaderboardRow> rows;
  const _Podium({required this.rows});

  @override
  Widget build(BuildContext context) {
    if (rows.length < 3) return const SizedBox.shrink();
    // visual layout: 2nd | 1st | 3rd
    const colors = [Color(0xFFCFCFCF), Color(0xFFFFD233), Color(0xFFC08350)];
    const heights = [54.0, 78.0, 36.0];
    final order = [rows[1], rows[0], rows[2]];
    const pos = [2, 1, 3];
    final t = Theme.of(context);
    return AppCard(
      background: t.mutedSurface,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(3, (i) {
          final r = order[i];
          return Expanded(
            child: Column(
              children: [
                Text(r.displayName,
                    style: AppText.body(12, weight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text('${r.pointsTotal}', style: AppText.display(16)),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  height: heights[i],
                  color: colors[i],
                  alignment: Alignment.center,
                  child: Text('${pos[i]}',
                      style: AppText.display(22, color: Colors.black)),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}
