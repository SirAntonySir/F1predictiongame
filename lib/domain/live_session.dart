import '../api/models/event.dart';
import '../api/models/session.dart';
import 'prediction.dart';

/// Safety cap so a session the crawler never scored doesn't read "live" forever.
const _maxProvisional = Duration(hours: 6);

/// A scorable session that has started (locked) and isn't finished yet — spans
/// the running phase AND the post-end "provisional" gap until the backend marks
/// it finished, bounded by [_maxProvisional] past its scheduled end.
bool isSessionLive(Session s, DateTime now) {
  if (requiredPicks(s.type) <= 0) return false;
  if (s.status == SessionStatus.finished) return false;
  if (now.isBefore(s.scheduledStart)) return false;
  if (now.isAfter(s.scheduledEnd.add(_maxProvisional))) return false;
  return true;
}

/// The single live scorable session across [events], or null. (F1 weekends
/// don't overlap, so at most one is expected; first match wins.)
Session? findLiveSession(List<Event> events, DateTime now) {
  for (final e in events) {
    for (final s in e.sessions) {
      if (isSessionLive(s, now)) return s;
    }
  }
  return null;
}
