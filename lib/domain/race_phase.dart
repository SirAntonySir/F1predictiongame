import '../api/models/event.dart';

/// Display phase of a race weekend on the calendar / tiles.
enum RaceState { past, next, live, future }

/// Classifies every event into a [RaceState] for a given `now`.
///
/// Each event owns a weekend window `[min(session.start), max(session.end))`
/// (the max end is the race end, since the race is the last session):
///   - `now` inside the window            → [RaceState.live]
///   - weekend not started, earliest such → [RaceState.next]; others → [future]
///   - race ended (`now >= window.end`)   → [RaceState.past]
///
/// Because a live event's weekend has already started, it is never a `next`
/// candidate, so `next` naturally lands on the earliest not-yet-started event —
/// i.e. it moves past the live one. Keyed by `event.round`. Events with no
/// sessions are skipped. At most one event is expected to be live (weekends
/// don't overlap); if several match, the last in iteration order wins.
Map<int, RaceState> classifyCalendar(List<Event> events, DateTime now) {
  int? liveRound;
  int? nextRound;
  DateTime? nextStart;
  final windowEnd = <int, DateTime>{};
  final windowStart = <int, DateTime>{};

  for (final e in events) {
    if (e.sessions.isEmpty) continue;
    var start = e.sessions.first.scheduledStart;
    var end = e.sessions.first.scheduledEnd;
    for (final s in e.sessions) {
      if (s.scheduledStart.isBefore(start)) start = s.scheduledStart;
      if (s.scheduledEnd.isAfter(end)) end = s.scheduledEnd;
    }
    windowStart[e.round] = start;
    windowEnd[e.round] = end;

    final started = !now.isBefore(start); // now >= start
    final ended = !now.isBefore(end); // now >= end
    if (started && !ended) {
      liveRound = e.round;
    } else if (!started) {
      if (nextStart == null || start.isBefore(nextStart)) {
        nextStart = start;
        nextRound = e.round;
      }
    }
  }

  final out = <int, RaceState>{};
  for (final round in windowStart.keys) {
    if (round == liveRound) {
      out[round] = RaceState.live;
    } else if (round == nextRound) {
      out[round] = RaceState.next;
    } else if (!now.isBefore(windowEnd[round]!)) {
      out[round] = RaceState.past;
    } else {
      out[round] = RaceState.future;
    }
  }
  return out;
}
