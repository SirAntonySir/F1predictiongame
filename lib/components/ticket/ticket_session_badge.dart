import '../../api/models/session.dart';

/// Full-typed uppercase label for a [SessionType] — used by the ticket
/// family to stamp the session prominently down the left edge.
String? ticketSessionLabel(SessionType? type) {
  if (type == null) return null;
  switch (type) {
    case SessionType.race:
      return 'RACE';
    case SessionType.qualifying:
      return 'QUALIFYING';
    case SessionType.sprint:
      return 'SPRINT';
    case SessionType.sprint_quali:
      return 'SPRINT QUALIFYING';
    case SessionType.fp1:
      return 'FREE PRACTICE 1';
    case SessionType.fp2:
      return 'FREE PRACTICE 2';
    case SessionType.fp3:
      return 'FREE PRACTICE 3';
  }
}
