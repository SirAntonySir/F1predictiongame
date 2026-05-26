import 'score_breakdown.dart';
import 'session.dart';

class MyScore {
  final int sessionId;
  final SessionType sessionType;
  final int eventRound;
  final String eventName;
  final DateTime sessionScheduledStart;
  final int pointsTotal;
  final ScoreBreakdown breakdown;
  final DateTime computedAt;

  const MyScore({
    required this.sessionId,
    required this.sessionType,
    required this.eventRound,
    required this.eventName,
    required this.sessionScheduledStart,
    required this.pointsTotal,
    required this.breakdown,
    required this.computedAt,
  });

  factory MyScore.fromJson(Map<String, dynamic> j) => MyScore(
        sessionId: j['sessionId'] as int,
        sessionType: SessionType.values.byName(j['sessionType'] as String),
        eventRound: j['eventRound'] as int,
        eventName: j['eventName'] as String,
        sessionScheduledStart: DateTime.parse(j['sessionScheduledStart'] as String).toLocal(),
        pointsTotal: j['pointsTotal'] as int,
        breakdown: ScoreBreakdown.fromJson(j['breakdown'] as Map<String, dynamic>),
        computedAt: DateTime.parse(j['computedAt'] as String).toLocal(),
      );
}
