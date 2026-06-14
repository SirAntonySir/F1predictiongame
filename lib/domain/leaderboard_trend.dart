import '../api/models/leaderboard_row.dart';
import '../components/trend_badge.dart';

/// Position change vs the previous event's standings.
class PositionTrend {
  /// up = moved higher, down = moved lower, equal = no change (or no
  /// previous standings yet).
  final TrendDirection direction;
  /// Absolute number of positions moved. 0 when equal.
  final int magnitude;
  const PositionTrend({required this.direction, required this.magnitude});

  static const equal = PositionTrend(direction: TrendDirection.equal, magnitude: 0);
}

/// Builds a `userId -> PositionTrend` map from a leaderboard, by ranking the
/// rows on the `prev*Points` field and comparing each user's previous rank
/// to their current position in [sortedRows].
///
/// - [sortedRows] must be sorted in current-leaderboard order (rank 1 first).
/// - [points] is the points extractor used for the current ranking (so we
///   know which previous field to use — in-season or total).
/// - [prevPoints] is the matching previous-points extractor.
///
/// Returns an empty map when the previous-points field is null on every row
/// (no event scored yet) — callers should default to TrendDirection.equal.
Map<String, PositionTrend> computeLeaderboardTrend({
  required List<LeaderboardRow> sortedRows,
  required int? Function(LeaderboardRow) prevPoints,
}) {
  if (sortedRows.every((r) => prevPoints(r) == null)) {
    return const <String, PositionTrend>{};
  }
  // Rank by previous points, descending. Ties keep insertion order from the
  // current ranking — fine since equal points → equal old rank.
  final prevSorted = [...sortedRows]
    ..sort((a, b) {
      final pa = prevPoints(a) ?? 0;
      final pb = prevPoints(b) ?? 0;
      return pb.compareTo(pa);
    });
  final prevRankByUser = <String, int>{
    for (var i = 0; i < prevSorted.length; i++) prevSorted[i].userId: i + 1,
  };
  final out = <String, PositionTrend>{};
  for (var i = 0; i < sortedRows.length; i++) {
    final r = sortedRows[i];
    final currentRank = i + 1;
    final prevRank = prevRankByUser[r.userId];
    if (prevRank == null || prevRank == currentRank) {
      out[r.userId] = PositionTrend.equal;
      continue;
    }
    final delta = prevRank - currentRank; // >0 → moved up
    out[r.userId] = PositionTrend(
      direction: delta > 0 ? TrendDirection.up : TrendDirection.down,
      magnitude: delta.abs(),
    );
  }
  return out;
}
