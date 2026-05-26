class LeaderboardRow {
  final String userId;
  final String displayName;
  final int pointsTotal;
  final int sessionsScored;

  const LeaderboardRow({
    required this.userId,
    required this.displayName,
    required this.pointsTotal,
    required this.sessionsScored,
  });

  factory LeaderboardRow.fromJson(Map<String, dynamic> j) => LeaderboardRow(
        userId: j['userId'] as String,
        displayName: j['displayName'] as String,
        pointsTotal: (j['pointsTotal'] as num).toInt(),
        sessionsScored: (j['sessionsScored'] as num).toInt(),
      );
}
