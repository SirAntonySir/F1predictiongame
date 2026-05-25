import 'package:flutter/material.dart';
import '../../components/app_card.dart';
import '../../components/league_row.dart';
import '../../components/trend_badge.dart';
import '../../state/app_state.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';

class LeagueTab extends StatelessWidget {
  const LeagueTab({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppState.of(context);
    final players = scope.league.league.players;
    // Mock cumulative points per player (deterministic ordering for visual)
    final rows = List.generate(players.length, (i) => (
      player: players[i],
      points: 200 - i * 18,
    ));
    rows.sort((a, b) => b.points.compareTo(a.points));
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
                final me = r.player.id == scope.auth.currentUserId;
                return LeagueRow(
                  rank: i + 1,
                  initials: r.player.initials,
                  name: me ? '${r.player.displayName} (you)' : r.player.displayName,
                  points: r.points,
                  trend: TrendDirection.equal,
                  isMe: me,
                );
              }),
            ),
          ),
        ),
      ],
    );
  }
}

class _Podium extends StatelessWidget {
  final List<dynamic> rows;
  const _Podium({required this.rows});

  @override
  Widget build(BuildContext context) {
    if (rows.length < 3) return const SizedBox.shrink();
    final colors = [const Color(0xFFFFD233), const Color(0xFFCFCFCF), const Color(0xFFC08350)];
    final heights = [60.0, 42.0, 30.0];
    final order = [rows[1], rows[0], rows[2]]; // visual: 2-1-3
    final pos = [2, 1, 3];
    return AppCard(
      background: const Color(0xFFFAFAFA),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(3, (i) {
          final r = order[i];
          final p = pos[i];
          return Expanded(
            child: Column(
              children: [
                CircleAvatar(
                  backgroundColor: p == 1 ? const Color(0xFFFFD233) : Colors.black,
                  child: Text(
                    r.player.initials,
                    style: AppText.display(14, color: p == 1 ? Colors.black : Colors.white),
                  ),
                ),
                const SizedBox(height: 6),
                Text(r.player.displayName, style: AppText.label(11)),
                Text('${r.points}', style: AppText.display(13)),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  height: heights[i],
                  color: colors[i],
                  alignment: Alignment.center,
                  child: Text('$p', style: AppText.display(18)),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}
