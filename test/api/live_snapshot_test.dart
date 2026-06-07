import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/models/live_snapshot.dart';

void main() {
  test('LiveSnapshot.fromJson parses state, order (incl. teamColour), projections', () {
    final j = {
      'sessionId': 5,
      'state': 'live',
      'asOf': '2026-06-07T13:30:00Z',
      'order': [
        {
          'position': 1,
          'driverCode': 'VER',
          'driverName': 'Max Verstappen',
          'constructorId': 'red_bull_racing',
          'constructorName': 'Red Bull Racing',
          'teamColour': '3671c6',
        }
      ],
      'myProjected': {'pointsTotal': 8},
      'leagueProjected': [
        {
          'userId': 'u2',
          'displayName': 'Lukas',
          'picks': [
            {'position': 1, 'driverCode': 'LEC'}
          ],
          'pointsTotal': 3
        }
      ]
    };
    final s = LiveSnapshot.fromJson(j);
    expect(s.state, LiveState.live);
    expect(s.order.single.driverCode, 'VER');
    expect(s.order.single.teamColour, '3671c6');
    expect(s.myPointsTotal, 8);
    expect(s.league.single.displayName, 'Lukas');
    expect(s.league.single.pointsTotal, 3);
  });

  test('unknown state falls back to unavailable; null projection tolerated', () {
    final s = LiveSnapshot.fromJson({
      'sessionId': 1,
      'state': 'weird',
      'asOf': '2026-06-07T13:30:00Z',
      'order': [],
      'myProjected': {'pointsTotal': null},
      'leagueProjected': []
    });
    expect(s.state, LiveState.unavailable);
    expect(s.myPointsTotal, isNull);
    expect(s.order, isEmpty);
  });

  test('final state maps from backend "final"', () {
    final s = LiveSnapshot.fromJson({
      'sessionId': 1,
      'state': 'final',
      'order': [],
      'myProjected': null,
      'leagueProjected': []
    });
    expect(s.state, LiveState.finalised);
    expect(s.asOf, isNull);
    expect(s.myPointsTotal, isNull);
  });
}
