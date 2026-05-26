import 'pick.dart';
import 'session.dart';

class UpcomingPrediction {
  final int sessionId;
  final SessionType sessionType;
  final int eventId;
  final int eventRound;
  final String eventName;
  final String eventCountry;
  final int picksRequired;
  final DateTime locksAt;
  final bool isLocked;
  final List<Pick>? myPicks;

  const UpcomingPrediction({
    required this.sessionId,
    required this.sessionType,
    required this.eventId,
    required this.eventRound,
    required this.eventName,
    required this.eventCountry,
    required this.picksRequired,
    required this.locksAt,
    required this.isLocked,
    required this.myPicks,
  });

  factory UpcomingPrediction.fromJson(Map<String, dynamic> j) {
    final s = j['session'] as Map<String, dynamic>;
    final e = j['event'] as Map<String, dynamic>;
    final mp = j['myPicks'];
    return UpcomingPrediction(
      sessionId: s['id'] as int,
      sessionType: SessionType.values.byName(s['type'] as String),
      eventId: e['id'] as int,
      eventRound: e['round'] as int,
      eventName: e['name'] as String,
      eventCountry: e['country'] as String,
      picksRequired: j['picksRequired'] as int,
      locksAt: DateTime.parse(j['locksAt'] as String).toLocal(),
      isLocked: j['isLocked'] as bool,
      myPicks: mp == null
          ? null
          : (mp as List).cast<Map<String, dynamic>>().map(Pick.fromJson).toList(),
    );
  }
}
