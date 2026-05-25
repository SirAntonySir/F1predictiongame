import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/models/season.dart';
import 'package:predictiongame/api/models/event.dart';
import 'package:predictiongame/api/models/session.dart';
import 'package:predictiongame/api/models/session_result.dart';
import 'package:predictiongame/api/models/driver.dart';
import 'package:predictiongame/api/models/constructor.dart';
import 'package:predictiongame/api/models/standing.dart';

void main() {
  test('Season.fromJson', () {
    final s = Season.fromJson({'year': 2026, 'isCurrent': true});
    expect(s.year, 2026);
    expect(s.isCurrent, true);
  });

  test('Event.fromJson with sessions', () {
    final e = Event.fromJson({
      'round': 8,
      'name': 'Monaco Grand Prix',
      'country': 'Monaco',
      'circuitName': 'Circuit de Monaco',
      'hasSprint': false,
      'sessions': [
        {
          'id': 42,
          'type': 'race',
          'scheduledStart': '2026-05-26T13:00:00Z',
          'scheduledEnd': '2026-05-26T15:00:00Z',
          'status': 'scheduled',
        }
      ],
    });
    expect(e.round, 8);
    expect(e.name, 'Monaco Grand Prix');
    expect(e.hasSprint, false);
    expect(e.sessions.first.type, SessionType.race);
  });

  test('SessionType parses all enum values', () {
    for (final s in const [
      'fp1', 'fp2', 'fp3', 'qualifying', 'sprint_quali', 'sprint', 'race'
    ]) {
      expect(SessionType.values.byName(s).name, s);
    }
  });

  test('SessionResult.fromJson handles nullable fields', () {
    final r = SessionResult.fromJson({
      'position': 1,
      'driverCode': 'VER',
      'driverName': 'Max Verstappen',
      'constructorId': 'red_bull',
      'constructorName': 'Red Bull',
      'raceTime': '1:33:15',
      'status': 'Finished',
      'points': 25,
      'fastestLap': null,
    });
    expect(r.position, 1);
    expect(r.driverCode, 'VER');
    expect(r.points, 25);
    expect(r.fastestLap, isNull);
  });

  test('Driver.fromJson with image fallback', () {
    final d = Driver.fromJson({
      'code': 'VER',
      'givenName': 'Max',
      'familyName': 'Verstappen',
      'nationality': 'Dutch',
      'permanentNumber': 1,
      'image': null,
    });
    expect(d.code, 'VER');
    expect(d.image, isNull);
  });

  test('Constructor.fromJson', () {
    final c = Constructor.fromJson({
      'id': 'red_bull',
      'name': 'Red Bull',
      'nationality': 'Austrian',
      'image': 'https://example.com/rb.png',
    });
    expect(c.id, 'red_bull');
    expect(c.image, 'https://example.com/rb.png');
  });

  test('DriverStanding.fromJson', () {
    final s = DriverStanding.fromJson({
      'position': 1,
      'driverCode': 'VER',
      'driverName': 'Max Verstappen',
      'constructorId': 'red_bull',
      'points': 200,
      'wins': 6,
      'image': null,
    });
    expect(s.position, 1);
    expect(s.points, 200);
  });
}
