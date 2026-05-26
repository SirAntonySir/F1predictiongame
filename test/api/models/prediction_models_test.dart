import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/models/pick.dart';
import 'package:predictiongame/api/models/prediction_view.dart';
import 'package:predictiongame/api/models/session.dart';
import 'package:predictiongame/api/models/upcoming_prediction.dart';

void main() {
  test('Pick round-trip', () {
    final p = Pick.fromJson({'position': 1, 'driverCode': 'VER'});
    expect(p.position, 1);
    expect(p.driverCode, 'VER');
    expect(p.toJson(), {'position': 1, 'driverCode': 'VER'});
  });

  test('PredictionView with picks and locked flag', () {
    final v = PredictionView.fromJson({
      'sessionId': 42,
      'picks': [{'position': 1, 'driverCode': 'VER'}, {'position': 2, 'driverCode': 'NOR'}],
      'updatedAt': '2026-05-01T00:00:00.000Z',
      'isLocked': true,
    });
    expect(v.sessionId, 42);
    expect(v.picks.length, 2);
    expect(v.isLocked, isTrue);
    expect(v.updatedAt!.toIso8601String(), '2026-05-01T00:00:00.000Z');
  });

  test('PredictionView without updatedAt', () {
    final v = PredictionView.fromJson({
      'sessionId': 7,
      'picks': [{'position': 1, 'driverCode': 'NOR'}],
      'isLocked': false,
    });
    expect(v.updatedAt, isNull);
  });

  test('UpcomingPrediction with myPicks', () {
    final u = UpcomingPrediction.fromJson({
      'session': {'id': 10, 'type': 'qualifying'},
      'event': {'id': 1, 'round': 6, 'name': 'Monaco Grand Prix', 'country': 'Monaco'},
      'picksRequired': 2,
      'locksAt': '2026-06-06T14:00:00.000Z',
      'isLocked': false,
      'myPicks': [{'position': 1, 'driverCode': 'LEC'}, {'position': 2, 'driverCode': 'VER'}],
    });
    expect(u.sessionId, 10);
    expect(u.sessionType, SessionType.qualifying);
    expect(u.eventRound, 6);
    expect(u.picksRequired, 2);
    expect(u.isLocked, isFalse);
    expect(u.myPicks!.length, 2);
  });

  test('UpcomingPrediction without myPicks (null)', () {
    final u = UpcomingPrediction.fromJson({
      'session': {'id': 11, 'type': 'race'},
      'event': {'id': 1, 'round': 6, 'name': 'Monaco', 'country': 'MC'},
      'picksRequired': 5,
      'locksAt': '2026-06-07T13:00:00.000Z',
      'isLocked': false,
      'myPicks': null,
    });
    expect(u.myPicks, isNull);
  });
}
