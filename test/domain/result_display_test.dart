import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/models/session.dart';
import 'package:predictiongame/api/models/session_result.dart';
import 'package:predictiongame/domain/result_display.dart';

SessionResult _row({
  String? raceTime,
  String? q1,
  String? q2,
  String? q3,
}) =>
    SessionResult(
      position: 1,
      driverCode: 'XXX',
      driverName: 'X',
      constructorId: 'x',
      constructorName: 'X',
      raceTime: raceTime,
      q1: q1,
      q2: q2,
      q3: q3,
    );

void main() {
  group('displayTime — race & sprint', () {
    test('race uses raceTime', () {
      expect(
        displayTime(_row(raceTime: '+0.521'), SessionType.race),
        '+0.521',
      );
    });
    test('sprint uses raceTime', () {
      expect(
        displayTime(_row(raceTime: '1:23.456'), SessionType.sprint),
        '1:23.456',
      );
    });
    test('race with null raceTime → empty string', () {
      expect(displayTime(_row(), SessionType.race), '');
    });
    test('race ignores q1/q2/q3 even if they happen to be set', () {
      expect(
        displayTime(
          _row(raceTime: '+1.000', q3: '1:18.000'),
          SessionType.race,
        ),
        '+1.000',
      );
    });
  });

  group('displayTime — qualifying & sprint_quali', () {
    test('qualifying prefers q3 when set', () {
      expect(
        displayTime(
          _row(q1: '1:19.5', q2: '1:18.9', q3: '1:18.5'),
          SessionType.qualifying,
        ),
        '1:18.5',
      );
    });
    test('qualifying falls back to q2 when q3 is null (eliminated in Q2)', () {
      expect(
        displayTime(_row(q1: '1:19.5', q2: '1:18.9'), SessionType.qualifying),
        '1:18.9',
      );
    });
    test('qualifying falls back to q1 when q2 and q3 null (eliminated in Q1)', () {
      expect(
        displayTime(_row(q1: '1:19.5'), SessionType.qualifying),
        '1:19.5',
      );
    });
    test('qualifying with no lap times → empty string', () {
      expect(displayTime(_row(), SessionType.qualifying), '');
    });
    test('sprint_quali uses same fallback as qualifying', () {
      expect(
        displayTime(_row(q1: '1:30.0', q2: '1:29.0'), SessionType.sprint_quali),
        '1:29.0',
      );
    });
    test('qualifying ignores raceTime even if set', () {
      expect(
        displayTime(
          _row(raceTime: '1:23:45.6', q3: '1:18.5'),
          SessionType.qualifying,
        ),
        '1:18.5',
      );
    });
  });

  group('displayTime — non-result session types', () {
    test('fp1 returns empty string', () {
      expect(
        displayTime(_row(raceTime: '+0.1', q3: '1:18.0'), SessionType.fp1),
        '',
      );
    });
  });
}
