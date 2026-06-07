import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/models/event.dart';
import 'package:predictiongame/api/models/session.dart';
import 'package:predictiongame/domain/prediction.dart';

Session _s(int id, SessionType type, String startIso,
        {SessionStatus status = SessionStatus.finished}) =>
    Session(
      id: id,
      type: type,
      scheduledStart: DateTime.parse(startIso),
      scheduledEnd: DateTime.parse(startIso),
      status: status,
    );

Event _ev(int round, String name, List<Session> sessions) => Event(
      round: round,
      name: name,
      country: name,
      circuitName: name,
      hasSprint: false,
      sessions: sessions,
    );

void main() {
  group('selectLastScorableSession', () {
    test('prefers the most recent finished scorable session '
        '(Monaco quali over the earlier Canada race)', () {
      final canada = _ev(5, 'Canadian Grand Prix', [
        _s(25, SessionType.race, '2026-05-24T20:00:00Z'),
      ]);
      final monaco = _ev(6, 'Monaco Grand Prix', [
        _s(29, SessionType.qualifying, '2026-06-06T14:00:00Z'),
        _s(30, SessionType.race, '2026-06-07T13:00:00Z',
            status: SessionStatus.scheduled),
      ]);

      final pick = selectLastScorableSession([canada, monaco]);

      expect(pick, isNotNull);
      expect(pick!.session.id, 29);
      expect(pick.session.type, SessionType.qualifying);
      expect(pick.event.round, 6);
    });

    test('falls back to the last finished race when nothing later has run', () {
      final canada = _ev(5, 'Canadian Grand Prix', [
        _s(25, SessionType.race, '2026-05-24T20:00:00Z'),
      ]);
      final monaco = _ev(6, 'Monaco Grand Prix', [
        _s(29, SessionType.qualifying, '2026-06-06T14:00:00Z',
            status: SessionStatus.scheduled),
        _s(30, SessionType.race, '2026-06-07T13:00:00Z',
            status: SessionStatus.scheduled),
      ]);

      final pick = selectLastScorableSession([canada, monaco]);

      expect(pick!.session.id, 25);
      expect(pick.session.type, SessionType.race);
    });

    test('ignores finished practice sessions (Friday of a race weekend)', () {
      final canada = _ev(5, 'Canadian Grand Prix', [
        _s(25, SessionType.race, '2026-05-24T20:00:00Z'),
      ]);
      // Monaco FP1 has run (later than the Canada race) but is not scorable,
      // so the card should still show the Canada race.
      final monaco = _ev(6, 'Monaco Grand Prix', [
        _s(26, SessionType.fp1, '2026-06-05T11:30:00Z'),
        _s(29, SessionType.qualifying, '2026-06-06T14:00:00Z',
            status: SessionStatus.scheduled),
        _s(30, SessionType.race, '2026-06-07T13:00:00Z',
            status: SessionStatus.scheduled),
      ]);

      final pick = selectLastScorableSession([canada, monaco]);

      expect(pick!.session.id, 25);
      expect(pick.session.type, SessionType.race);
    });

    test('returns null when nothing has finished', () {
      final monaco = _ev(6, 'Monaco Grand Prix', [
        _s(30, SessionType.race, '2026-06-07T13:00:00Z',
            status: SessionStatus.scheduled),
      ]);

      expect(selectLastScorableSession([monaco]), isNull);
    });
  });
}
