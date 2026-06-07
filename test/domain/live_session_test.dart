import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/models/event.dart';
import 'package:predictiongame/api/models/session.dart';
import 'package:predictiongame/domain/live_session.dart';

Session _s(int id, SessionType type, DateTime start, DateTime end,
        SessionStatus status) =>
    Session(
        id: id,
        type: type,
        scheduledStart: start,
        scheduledEnd: end,
        status: status);

void main() {
  final now = DateTime.utc(2026, 6, 7, 13, 30);

  test('a scorable session that has started and is not finished is live', () {
    final s = _s(1, SessionType.race, now.subtract(const Duration(hours: 1)),
        now.add(const Duration(hours: 1)), SessionStatus.scheduled);
    expect(isSessionLive(s, now), isTrue);
  });

  test('finished, not-yet-started, non-scorable, and long-past are not live', () {
    expect(
        isSessionLive(
            _s(1, SessionType.race, now.subtract(const Duration(hours: 1)),
                now.add(const Duration(hours: 1)), SessionStatus.finished),
            now),
        isFalse);
    expect(
        isSessionLive(
            _s(1, SessionType.race, now.add(const Duration(hours: 1)),
                now.add(const Duration(hours: 3)), SessionStatus.scheduled),
            now),
        isFalse);
    expect(
        isSessionLive(
            _s(1, SessionType.fp1, now.subtract(const Duration(hours: 1)),
                now.add(const Duration(hours: 1)), SessionStatus.scheduled),
            now),
        isFalse);
    // ended >6h ago but still flagged scheduled (crawler missed it) → not live
    expect(
        isSessionLive(
            _s(1, SessionType.race, now.subtract(const Duration(hours: 9)),
                now.subtract(const Duration(hours: 7)), SessionStatus.scheduled),
            now),
        isFalse);
  });

  test('provisional window (just past end, still scheduled) is live', () {
    final s = _s(1, SessionType.race, now.subtract(const Duration(hours: 3)),
        now.subtract(const Duration(minutes: 10)), SessionStatus.scheduled);
    expect(isSessionLive(s, now), isTrue);
  });

  test('findLiveSession returns the live one across events', () {
    final events = [
      Event(round: 1, name: 'A', country: 'X', circuitName: 'c', hasSprint: false, sessions: [
        _s(10, SessionType.race, now.subtract(const Duration(hours: 1)),
            now.add(const Duration(hours: 1)), SessionStatus.scheduled),
      ]),
    ];
    expect(findLiveSession(events, now)?.id, 10);
    expect(findLiveSession(const [], now), isNull);
  });
}
