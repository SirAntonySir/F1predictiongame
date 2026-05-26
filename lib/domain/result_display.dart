import '../api/models/session.dart';
import '../api/models/session_result.dart';

String displayTime(SessionResult r, SessionType type) {
  switch (type) {
    case SessionType.race:
    case SessionType.sprint:
      return r.raceTime ?? '';
    case SessionType.qualifying:
    case SessionType.sprint_quali:
      return r.q3 ?? r.q2 ?? r.q1 ?? '';
    case SessionType.fp1:
    case SessionType.fp2:
    case SessionType.fp3:
      return '';
  }
}
