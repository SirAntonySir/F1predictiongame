import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/models/my_score.dart';
import 'package:predictiongame/api/models/score_breakdown.dart';
import 'package:predictiongame/api/models/session.dart';

void main() {
  test('ScoreBreakdown round-trip', () {
    final b = ScoreBreakdown.fromJson({
      'perPosition': [
        {'position': 1, 'exact': true,  'wrongPos': false, 'points': 3},
        {'position': 2, 'exact': false, 'wrongPos': true,  'points': 1},
      ],
      'teamBonus': {'applied': true, 'points': 2},
      'rule': 'race-v1',
    });
    expect(b.perPosition.length, 2);
    expect(b.perPosition[0].exact, isTrue);
    expect(b.teamBonus.applied, isTrue);
    expect(b.teamBonus.points, 2);
    expect(b.rule, 'race-v1');
  });

  test('MyScore round-trip', () {
    final s = MyScore.fromJson({
      'sessionId': 1,
      'sessionType': 'race',
      'eventRound': 1,
      'eventName': 'Australian Grand Prix',
      'sessionScheduledStart': '2026-03-08T04:00:00.000Z',
      'pointsTotal': 15,
      'breakdown': {
        'perPosition': [{'position': 1, 'exact': true, 'wrongPos': false, 'points': 3}],
        'teamBonus': {'applied': false, 'points': 0},
        'rule': 'race-v1',
      },
      'computedAt': '2026-05-26T20:00:00.000Z',
    });
    expect(s.sessionId, 1);
    expect(s.sessionType, SessionType.race);
    expect(s.pointsTotal, 15);
    expect(s.eventName, 'Australian Grand Prix');
    expect(s.breakdown.rule, 'race-v1');
  });
}
