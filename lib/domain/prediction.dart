import '../api/models/event.dart';
import '../api/models/session.dart';

class PredictionEntry {
  final int sessionId;
  final String userId;
  final List<String> picks;
  final DateTime? lockedAt;

  const PredictionEntry({
    required this.sessionId,
    required this.userId,
    required this.picks,
    this.lockedAt,
  });

  String get key => '$userId:$sessionId';
  bool get isLocked => lockedAt != null;

  PredictionEntry copyWith({List<String>? picks, DateTime? lockedAt}) =>
      PredictionEntry(
        sessionId: sessionId,
        userId: userId,
        picks: picks ?? this.picks,
        lockedAt: lockedAt ?? this.lockedAt,
      );

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'userId': userId,
        'picks': picks,
        'lockedAt': lockedAt?.toIso8601String(),
      };

  factory PredictionEntry.fromJson(Map<String, dynamic> j) => PredictionEntry(
        sessionId: j['sessionId'] as int,
        userId: j['userId'] as String,
        picks: (j['picks'] as List).cast<String>(),
        lockedAt: j['lockedAt'] == null
            ? null
            : DateTime.parse(j['lockedAt'] as String),
      );
}

int requiredPicks(SessionType t) {
  switch (t) {
    case SessionType.qualifying:
      return 2;
    case SessionType.race:
      return 5;
    case SessionType.sprint_quali:
      return 1;
    case SessionType.sprint:
      return 3;
    case SessionType.fp1:
    case SessionType.fp2:
    case SessionType.fp3:
      return 0;
  }
}

/// The most recent finished *scorable* session (race / qualifying / sprint /
/// sprint-quali — anything with [requiredPicks] > 0) across [events], chosen by
/// latest [Session.scheduledStart]. Finished practice sessions are ignored.
/// Returns null when no scorable session has finished yet.
({Event event, Session session})? selectLastScorableSession(
    List<Event> events) {
  Event? bestEvent;
  Session? best;
  for (final e in events) {
    for (final s in e.sessions) {
      if (s.status != SessionStatus.finished) continue;
      if (requiredPicks(s.type) <= 0) continue;
      if (best == null || s.scheduledStart.isAfter(best.scheduledStart)) {
        best = s;
        bestEvent = e;
      }
    }
  }
  if (best == null || bestEvent == null) return null;
  return (event: bestEvent, session: best);
}
