/// One league member's picks + session score for a given session.
/// Returned by `GET /api/leagues/:id/sessions/:sessionId/predictions`.
class MemberPrediction {
  final String userId;
  final String displayName;
  final List<({int position, String driverCode})> picks;
  /// Null if the session hasn't been scored yet (or the member didn't pick).
  final int? pointsTotal;

  const MemberPrediction({
    required this.userId,
    required this.displayName,
    required this.picks,
    required this.pointsTotal,
  });

  factory MemberPrediction.fromJson(Map<String, dynamic> j) {
    final rawPicks = (j['picks'] as List? ?? const []).cast<Map<String, dynamic>>();
    return MemberPrediction(
      userId: j['userId'] as String,
      displayName: j['displayName'] as String,
      picks: rawPicks
          .map((p) => (
                position: (p['position'] as num).toInt(),
                driverCode: p['driverCode'] as String,
              ))
          .toList(),
      pointsTotal: j['pointsTotal'] == null
          ? null
          : (j['pointsTotal'] as num).toInt(),
    );
  }
}

/// Wrapper returned by the league-session-predictions endpoint.
class LeagueSessionPredictions {
  final bool sessionLocked;
  final List<MemberPrediction> predictions;
  const LeagueSessionPredictions({
    required this.sessionLocked,
    required this.predictions,
  });

  factory LeagueSessionPredictions.fromJson(Map<String, dynamic> j) =>
      LeagueSessionPredictions(
        sessionLocked: j['sessionLocked'] as bool,
        predictions: (j['predictions'] as List? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(MemberPrediction.fromJson)
            .toList(),
      );
}
