class SessionLeaderboardMember {
  final String userId;
  final String displayName;
  final int pointsTotal;
  const SessionLeaderboardMember({
    required this.userId,
    required this.displayName,
    required this.pointsTotal,
  });
  factory SessionLeaderboardMember.fromJson(Map<String, dynamic> j) =>
      SessionLeaderboardMember(
        userId: j['userId'] as String,
        displayName: j['displayName'] as String,
        pointsTotal: (j['pointsTotal'] as num).toInt(),
      );
}

class SessionLeaderboardRow {
  final int sessionId;
  final String sessionType;
  final int eventRound;
  final String eventName;
  final DateTime scheduledStart;
  final List<SessionLeaderboardMember> members;
  const SessionLeaderboardRow({
    required this.sessionId,
    required this.sessionType,
    required this.eventRound,
    required this.eventName,
    required this.scheduledStart,
    required this.members,
  });
  factory SessionLeaderboardRow.fromJson(Map<String, dynamic> j) => SessionLeaderboardRow(
        sessionId: (j['sessionId'] as num).toInt(),
        sessionType: j['sessionType'] as String,
        eventRound: (j['eventRound'] as num).toInt(),
        eventName: j['eventName'] as String,
        scheduledStart: DateTime.parse(j['scheduledStart'] as String),
        members: ((j['members'] as List).cast<Map<String, dynamic>>())
            .map(SessionLeaderboardMember.fromJson)
            .toList(),
      );
}
