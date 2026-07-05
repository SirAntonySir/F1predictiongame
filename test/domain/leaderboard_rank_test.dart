import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/models/leaderboard_row.dart';
import 'package:predictiongame/domain/leaderboard_rank.dart';

LeaderboardRow _row(String name, {int season = 0, int total = 0}) =>
    LeaderboardRow(
      userId: name,
      displayName: name,
      inSeasonPoints: season,
      preseasonPoints: 0,
      pointsTotal: total,
      sessionsScored: 0,
    );

void main() {
  int season(LeaderboardRow r) => r.inSeasonPoints;

  group('rankLeaderboard', () {
    test('ties share a rank (competition ranking 1,1,3)', () {
      final rows = [
        _row('Anton', season: 106, total: 162),
        _row('Simon', season: 103, total: 149),
        _row('Lukas', season: 106, total: 150),
      ];
      final ranked = rankLeaderboard(rows, season);
      // Ordered by season desc, ties broken by total desc.
      expect(ranked.map((e) => e.row.displayName), ['Anton', 'Lukas', 'Simon']);
      expect(ranked.map((e) => e.rank), [1, 1, 3]);
      expect(ranked.map((e) => e.tied), [true, true, false]);
    });

    test('deterministic: equal metric AND total falls back to name', () {
      final a = [_row('Bea', season: 50, total: 50), _row('Abe', season: 50, total: 50)];
      final b = [_row('Abe', season: 50, total: 50), _row('Bea', season: 50, total: 50)];
      expect(rankLeaderboard(a, season).map((e) => e.row.displayName),
          rankLeaderboard(b, season).map((e) => e.row.displayName));
      // Alphabetical is the final, stable key.
      expect(rankLeaderboard(a, season).map((e) => e.row.displayName),
          ['Abe', 'Bea']);
    });

    test('no ties → sequential ranks, none marked tied', () {
      final rows = [
        _row('A', season: 30),
        _row('B', season: 20),
        _row('C', season: 10),
      ];
      final ranked = rankLeaderboard(rows, season);
      expect(ranked.map((e) => e.rank), [1, 2, 3]);
      expect(ranked.every((e) => !e.tied), isTrue);
    });

    test('does not mutate the input list', () {
      final rows = [_row('A', season: 10), _row('B', season: 20)];
      rankLeaderboard(rows, season);
      expect(rows.map((r) => r.displayName), ['A', 'B']);
    });
  });
}
