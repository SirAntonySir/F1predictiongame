import 'session.dart';

class Event {
  final int round;
  final String name;
  final String country;
  final String circuitName;
  final bool hasSprint;
  final List<Session> sessions;

  const Event({
    required this.round,
    required this.name,
    required this.country,
    required this.circuitName,
    required this.hasSprint,
    required this.sessions,
  });

  factory Event.fromJson(Map<String, dynamic> j) => Event(
        round: j['round'] as int,
        name: j['name'] as String,
        country: j['country'] as String,
        circuitName: j['circuitName'] as String,
        hasSprint: j['hasSprint'] as bool,
        sessions: ((j['sessions'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(Session.fromJson)
            .toList(),
      );
}
