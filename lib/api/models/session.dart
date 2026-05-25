// ignore_for_file: constant_identifier_names

enum SessionType { fp1, fp2, fp3, qualifying, sprint_quali, sprint, race }

enum SessionStatus { scheduled, finished }

class Session {
  final int id;
  final SessionType type;
  final DateTime scheduledStart;
  final DateTime scheduledEnd;
  final SessionStatus status;

  const Session({
    required this.id,
    required this.type,
    required this.scheduledStart,
    required this.scheduledEnd,
    required this.status,
  });

  factory Session.fromJson(Map<String, dynamic> j) => Session(
        id: j['id'] as int,
        type: SessionType.values.byName(j['type'] as String),
        scheduledStart: DateTime.parse(j['scheduledStart'] as String).toLocal(),
        scheduledEnd: DateTime.parse(j['scheduledEnd'] as String).toLocal(),
        status: SessionStatus.values.byName(j['status'] as String),
      );
}
