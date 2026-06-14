class LeaderboardRow {
  final String userId;
  final String displayName;
  final int inSeasonPoints;
  final int preseasonPoints;
  final int pointsTotal;
  final int sessionsScored;
  /// Totals as of *before* the most recently scored event. Null when no
  /// in-season event has been scored yet (the trend is undefined).
  final int? prevInSeasonPoints;
  final int? prevPointsTotal;

  const LeaderboardRow({
    required this.userId,
    required this.displayName,
    required this.inSeasonPoints,
    required this.preseasonPoints,
    required this.pointsTotal,
    required this.sessionsScored,
    this.prevInSeasonPoints,
    this.prevPointsTotal,
  });

  factory LeaderboardRow.fromJson(Map<String, dynamic> j) => LeaderboardRow(
        userId: j['userId'] as String,
        displayName: j['displayName'] as String,
        inSeasonPoints: (j['inSeasonPoints'] as num).toInt(),
        preseasonPoints: (j['preseasonPoints'] as num).toInt(),
        pointsTotal: (j['pointsTotal'] as num).toInt(),
        sessionsScored: (j['sessionsScored'] as num).toInt(),
        prevInSeasonPoints: (j['prevInSeasonPoints'] as num?)?.toInt(),
        prevPointsTotal: (j['prevPointsTotal'] as num?)?.toInt(),
      );
}
