import '../api/models/leaderboard_row.dart';

/// A leaderboard row with its competition rank. Equal-metric players share a
/// rank ([tied] = true) — e.g. two players level on points are both rank 1 and
/// the next is rank 3.
class RankedRow {
  final LeaderboardRow row;
  final int rank;
  final bool tied;
  const RankedRow({required this.row, required this.rank, required this.tied});
}

/// Order [rows] for display and assign competition ranks.
///
/// Sort: the active [metric] descending, then — so equal-metric players never
/// flip between refreshes — total points descending, then name. Ranks use
/// competition ranking (1, 1, 3): players level on [metric] share a rank, and
/// the position after a tie skips accordingly. [tied] marks any row whose
/// metric equals a neighbour's.
List<RankedRow> rankLeaderboard(
    List<LeaderboardRow> rows, int Function(LeaderboardRow) metric) {
  final sorted = [...rows]..sort((a, b) {
      final byMetric = metric(b).compareTo(metric(a));
      if (byMetric != 0) return byMetric;
      final byTotal = b.pointsTotal.compareTo(a.pointsTotal);
      if (byTotal != 0) return byTotal;
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });

  final out = <RankedRow>[];
  for (var i = 0; i < sorted.length; i++) {
    final samePrev = i > 0 && metric(sorted[i]) == metric(sorted[i - 1]);
    final sameNext =
        i < sorted.length - 1 && metric(sorted[i]) == metric(sorted[i + 1]);
    // Competition ranking: a tie carries the earlier row's rank forward,
    // otherwise the rank is this row's 1-indexed position.
    final rank = samePrev ? out[i - 1].rank : i + 1;
    out.add(RankedRow(row: sorted[i], rank: rank, tied: samePrev || sameNext));
  }
  return out;
}
