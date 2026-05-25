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
    // visual layout: 2nd | 1st | 3rd
    const colors = [Color(0xFFCFCFCF), Color(0xFFFFD233), Color(0xFFC08350)];
    const heights = [54.0, 78.0, 36.0];
    final order = [rows[1], rows[0], rows[2]];
    const pos = [2, 1, 3];
    return AppCard(
      background: const Color(0xFFFAFAFA),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(3, (i) {
          final r = order[i];
          return Expanded(
            child: Column(
              children: [
                Text(r.player.displayName,
                    style: AppText.body(12, weight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text('${r.points}',
                    style: AppText.display(16,
                        color: i == 1 ? Colors.black : Colors.black.withAlpha(180))),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  height: heights[i],
                  color: colors[i],
                  alignment: Alignment.center,
                  child: Text('${pos[i]}', style: AppText.display(22)),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}
