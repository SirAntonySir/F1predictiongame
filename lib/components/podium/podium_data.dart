import '../../api/models/leaderboard_row.dart';
import '../../api/models/session_leaderboard_row.dart';

/// One ranked step on the results podium (1 = winner).
class PodiumEntry {
  final int rank;
  final String displayName;
  final int points;

  /// Avatar config JSON for this member; null renders the default livery.
  final String? avatarConfig;

  const PodiumEntry({
    required this.rank,
    required this.displayName,
    required this.points,
    required this.avatarConfig,
  });
}

/// Everything the results podium sheet renders for one scored session.
class PodiumData {
  final String eventName;

  /// Human session label, e.g. "Race", "Qualifying", "Sprint".
  final String sessionLabel;
  final int round;
  final int sessionId;

  /// Ranked top-3 (index 0 = winner). Always length 3 when built via
  /// [fromSession]; [sample] and tests may vary.
  final List<PodiumEntry> entries;

  const PodiumData({
    required this.eventName,
    required this.sessionLabel,
    required this.round,
    required this.sessionId,
    required this.entries,
  });

  /// Builds podium data from a scored session row, joining each member to the
  /// season [leaderboard] for their avatar (by userId). Members are ranked by
  /// points (desc), ties broken by display name (asc). Returns null when fewer
  /// than three members scored — the podium requires a full set.
  static PodiumData? fromSession(
    SessionLeaderboardRow row,
    List<LeaderboardRow> leaderboard,
  ) {
    final avatarByUser = <String, String?>{
      for (final r in leaderboard) r.userId: r.avatarConfig,
    };
    final members = [...row.members]..sort((a, b) {
        final byPoints = b.pointsTotal.compareTo(a.pointsTotal);
        return byPoints != 0
            ? byPoints
            : a.displayName.compareTo(b.displayName);
      });
    if (members.length < 3) return null;
    final top = members.take(3).toList();
    return PodiumData(
      eventName: row.eventName,
      sessionLabel: prettySessionType(row.sessionType),
      round: row.eventRound,
      sessionId: row.sessionId,
      entries: [
        for (var i = 0; i < top.length; i++)
          PodiumEntry(
            rank: i + 1,
            displayName: top[i].displayName,
            points: top[i].pointsTotal,
            avatarConfig: avatarByUser[top[i].userId],
          ),
      ],
    );
  }

  /// Synthetic data for the dev preview and widget tests (no avatars → the
  /// default livery renders for all three steps).
  factory PodiumData.sample() => const PodiumData(
        eventName: 'British Grand Prix',
        sessionLabel: 'Race',
        round: 9,
        sessionId: -1,
        entries: [
          PodiumEntry(rank: 1, displayName: 'Anton', points: 24, avatarConfig: null),
          PodiumEntry(rank: 2, displayName: 'Lukas', points: 16, avatarConfig: null),
          PodiumEntry(rank: 3, displayName: 'Simon', points: 12, avatarConfig: null),
        ],
      );
}

/// Pure detection: the newest scored session (by scheduledStart) that hasn't
/// been celebrated yet, or null if there's nothing new. A "scored" session is
/// one whose members list is non-empty.
SessionLeaderboardRow? newestUnseenScored(
  List<SessionLeaderboardRow> breakdown,
  Set<int> seen,
) {
  final scored = scoredSessions(breakdown);
  if (scored.isEmpty) return null;
  final newest = scored.first;
  return seen.contains(newest.sessionId) ? null : newest;
}

/// Scored sessions (members present), newest first by scheduledStart.
List<SessionLeaderboardRow> scoredSessions(
    List<SessionLeaderboardRow> breakdown) {
  return breakdown.where((r) => r.members.isNotEmpty).toList()
    ..sort((a, b) => b.scheduledStart.compareTo(a.scheduledStart));
}

/// Maps the API's session-type string to a display label.
String prettySessionType(String raw) {
  switch (raw.toLowerCase()) {
    case 'race':
      return 'Race';
    case 'qualifying':
      return 'Qualifying';
    case 'sprint':
      return 'Sprint';
    case 'sprint_quali':
    case 'sprint_qualifying':
      return 'Sprint Quali';
    default:
      return raw.isEmpty ? 'Session' : raw[0].toUpperCase() + raw.substring(1);
  }
}
