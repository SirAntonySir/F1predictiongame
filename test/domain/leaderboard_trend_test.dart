import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/models/leaderboard_row.dart';
import 'package:predictiongame/components/trend_badge.dart';
import 'package:predictiongame/domain/leaderboard_trend.dart';

LeaderboardRow _row(String id, int points, int? prev) => LeaderboardRow(
      userId: id,
      displayName: id,
      inSeasonPoints: points,
      preseasonPoints: 0,
      pointsTotal: points,
      sessionsScored: 1,
      prevInSeasonPoints: prev,
      prevPointsTotal: prev,
    );

Map<String, PositionTrend> _trend(List<LeaderboardRow> sortedRows) =>
    computeLeaderboardTrend(
      sortedRows: sortedRows,
      points: (r) => r.inSeasonPoints,
      prevPoints: (r) => r.prevInSeasonPoints,
    );

void main() {
  test('moving into a shared lead counts as a gain for both co-leaders', () {
    // Before: C 120, B 110, A 100 → 1st, 2nd, 3rd. Now A and B share 1st.
    final t = _trend([_row('a', 120, 100), _row('b', 120, 110), _row('c', 100, 120)]);
    expect(t['a']!.direction, TrendDirection.up);
    expect(t['a']!.magnitude, 2);
    expect(t['b']!.direction, TrendDirection.up);
    expect(t['b']!.magnitude, 1);
    expect(t['c']!.direction, TrendDirection.down);
    expect(t['c']!.magnitude, 2);
  });

  test('dropping from a shared lead to 2nd shows a drop', () {
    // Before: A and B level on 100 (both 1st). Now A 120 (1st), B 110 (2nd).
    final t = _trend([_row('a', 120, 100), _row('b', 110, 100)]);
    expect(t['a']!.direction, TrendDirection.equal);
    expect(t['b']!.direction, TrendDirection.down);
    expect(t['b']!.magnitude, 1);
  });

  test('players still level with each other show no movement', () {
    final t = _trend([_row('a', 120, 100), _row('b', 120, 100)]);
    expect(t['a']!.direction, TrendDirection.equal);
    expect(t['b']!.direction, TrendDirection.equal);
  });

  test('no previous standings yet → no trends', () {
    expect(_trend([_row('a', 10, null), _row('b', 5, null)]), isEmpty);
  });
}
