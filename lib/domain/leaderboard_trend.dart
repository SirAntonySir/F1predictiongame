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

/// Builds a `userId -> PositionTrend` map by comparing each user's
/// competition rank now (on [points]) with their competition rank on the
/// matching `prev*Points` field — the same shared-rank rule the tables print
/// (1, 1, 3), so tied players never get contradictory arrows.
///
/// - [sortedRows] are the rows the caller displays (any order).
/// - [points] is the metric the table ranks on (in-season or total).
/// - [prevPoints] is the matching previous-points extractor.
///
/// Returns an empty map when the previous-points field is null on every row
/// (no event scored yet) — callers should default to TrendDirection.equal.
Map<String, PositionTrend> computeLeaderboardTrend({
  required List<LeaderboardRow> sortedRows,
  required int Function(LeaderboardRow) points,
  required int? Function(LeaderboardRow) prevPoints,
}) {
  if (sortedRows.every((r) => prevPoints(r) == null)) {
    return const <String, PositionTrend>{};
  }
  // Competition rank = 1 + players strictly ahead.
  int rankOf(LeaderboardRow r, int Function(LeaderboardRow) metric) =>
      1 + sortedRows.where((o) => metric(o) > metric(r)).length;
  final out = <String, PositionTrend>{};
  for (final r in sortedRows) {
    final delta = rankOf(r, (x) => prevPoints(x) ?? 0) - rankOf(r, points);
    out[r.userId] = delta == 0
        ? PositionTrend.equal
        : PositionTrend(
            direction: delta > 0 ? TrendDirection.up : TrendDirection.down,
            magnitude: delta.abs(),
          );
  }
  return out;
}
