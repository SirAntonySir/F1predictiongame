import '../api/models/leaderboard_row.dart';
import '../api/models/session_leaderboard_row.dart';
import 'leaderboard_rank.dart';

/// The Insights "YOUR SEASON" headline. Every number is in-season (session
/// points, no preseason projection), so the tile, its rank and both averages
/// measure the same thing as the League tab's IN-SEASON view — the old tile
/// paired in-season points with a rank on the preseason-inclusive total.
class SeasonHeadline {
  final int points;

  /// Competition rank among all members (ties share it); null when the caller
  /// isn't on the leaderboard.
  final int? rank;
  final bool tied;
  final int memberCount;

  /// Points per round held — rounds with any scored session in the league —
  /// for the caller and for the league, so the two compare like for like.
  /// Null until a round has been scored.
  final double? avgPerRound;
  final double? leagueAvgPerRound;

  const SeasonHeadline({
    required this.points,
    required this.rank,
    required this.tied,
    required this.memberCount,
    required this.avgPerRound,
    required this.leagueAvgPerRound,
  });
}

SeasonHeadline seasonHeadline({
  required String? myUserId,
  required List<LeaderboardRow> leaderboard,
  required List<SessionLeaderboardRow> sessions,
}) {
  RankedRow? me;
  for (final r in rankLeaderboard(leaderboard, (r) => r.inSeasonPoints)) {
    if (r.row.userId == myUserId) me = r;
  }
  final points = me?.row.inSeasonPoints ?? 0;
  final rounds = {
    for (final s in sessions)
      if (s.members.isNotEmpty) s.eventRound,
  }.length;
  final leaguePoints =
      leaderboard.fold<int>(0, (sum, r) => sum + r.inSeasonPoints);
  return SeasonHeadline(
    points: points,
    rank: me?.rank,
    tied: me?.tied ?? false,
    memberCount: leaderboard.length,
    avgPerRound: rounds == 0 || me == null ? null : points / rounds,
    leagueAvgPerRound: rounds == 0 || leaderboard.isEmpty
        ? null
        : leaguePoints / (leaderboard.length * rounds),
  );
}
