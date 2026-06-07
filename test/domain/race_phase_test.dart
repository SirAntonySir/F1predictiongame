import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/models/event.dart';
import 'package:predictiongame/api/models/session.dart';
import 'package:predictiongame/domain/race_phase.dart';

Session _s(int id, SessionType type, String start, String end) => Session(
      id: id,
      type: type,
      scheduledStart: DateTime.parse(start),
      scheduledEnd: DateTime.parse(end),
      status: SessionStatus.scheduled,
    );

Event _ev(int round, List<Session> sessions) => Event(
      round: round,
      name: 'R$round',
      country: 'C',
      circuitName: 'C',
      hasSprint: false,
      sessions: sessions,
    );

final _canada = _ev(5, [
  _s(1, SessionType.fp1, '2026-05-22T16:30:00Z', '2026-05-22T17:30:00Z'),
  _s(2, SessionType.race, '2026-05-24T20:00:00Z', '2026-05-24T22:00:00Z'),
]);
final _monaco = _ev(6, [
  _s(3, SessionType.fp1, '2026-06-05T11:30:00Z', '2026-06-05T13:00:00Z'),
  _s(4, SessionType.qualifying, '2026-06-06T14:00:00Z', '2026-06-06T15:00:00Z'),
  _s(5, SessionType.race, '2026-06-07T13:00:00Z', '2026-06-07T15:00:00Z'),
]);
final _barca = _ev(7, [
  _s(6, SessionType.fp1, '2026-06-12T11:30:00Z', '2026-06-12T13:00:00Z'),
  _s(7, SessionType.race, '2026-06-14T13:00:00Z', '2026-06-14T15:00:00Z'),
]);
final _cal = [_canada, _monaco, _barca];

void main() {
  group('classifyCalendar', () {
    test('during the race: that event is live, following is next, prior past',
        () {
      final m = classifyCalendar(_cal, DateTime.parse('2026-06-07T13:30:00Z'));
      expect(m[6], RaceState.live);
      expect(m[7], RaceState.next);
      expect(m[5], RaceState.past);
    });

    test('whole weekend: live during Saturday quali, next already advanced', () {
      final m = classifyCalendar(_cal, DateTime.parse('2026-06-06T14:30:00Z'));
      expect(m[6], RaceState.live);
      expect(m[7], RaceState.next);
      expect(m[5], RaceState.past);
    });

    test('before the weekend: that event is next, nothing live', () {
      final m = classifyCalendar(_cal, DateTime.parse('2026-06-04T12:00:00Z'));
      expect(m.values, isNot(contains(RaceState.live)));
      expect(m[6], RaceState.next);
      expect(m[7], RaceState.future);
      expect(m[5], RaceState.past);
    });

    test('after the race, before next weekend: past + following next', () {
      final m = classifyCalendar(_cal, DateTime.parse('2026-06-09T12:00:00Z'));
      expect(m[6], RaceState.past);
      expect(m[7], RaceState.next);
    });

    test('all in the future: earliest is next, rest future, none live', () {
      final m = classifyCalendar(_cal, DateTime.parse('2026-01-01T00:00:00Z'));
      expect(m[5], RaceState.next);
      expect(m[6], RaceState.future);
      expect(m[7], RaceState.future);
      expect(m.values, isNot(contains(RaceState.live)));
    });
  });
}
