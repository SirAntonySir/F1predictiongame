import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/models/league_preseason_view.dart';
import 'package:predictiongame/domain/preseason.dart';

void main() {
  test('LeaguePreseasonView.fromJson parses categories, standings, leaderboard', () {
    final v = LeaguePreseasonView.fromJson({
      'seasonYear': 2026,
      'isLocked': false,
      'me': {
        'categories': [
          {
            'category': 'wdc_wcc',
            'myPick': {'driverCode': 'VER', 'constructorId': 'red_bull'},
            'projectedTruth': {'driverCode': 'VER', 'constructorId': 'red_bull'},
            'projectedPoints': 8,
            'max': 8,
          },
          {
            'category': 'surprise',
            'myPick': {'driverCode': null, 'constructorId': null},
            'projectedTruth': null,
            'projectedPoints': 0,
            'max': 8,
          },
        ],
        'standings': {
          'myDriverPicks': [{'position': 1, 'driverCode': 'VER'}],
          'myConstructorPicks': [{'position': 1, 'constructorId': 'red_bull'}],
          'projectedDriverOrder': ['VER', 'HAM'],
          'projectedConstructorOrder': ['red_bull', 'mercedes'],
          'projectedPoints': 3,
          'max': 60,
        },
        'projectedPointsTotal': 11,
      },
      'leaderboard': [
        {'userId': 'u1', 'displayName': 'Me',    'preseasonPointsProjected': 11},
        {'userId': 'u2', 'displayName': 'Other', 'preseasonPointsProjected': 0},
      ],
    });
    expect(v.seasonYear, 2026);
    expect(v.isLocked, false);
    expect(v.me.categories.length, 2);
    expect(v.me.categories.first.category, PreseasonCategory.wdc_wcc);
    expect(v.me.categories.first.projectedTruth?.driverCode, 'VER');
    expect(v.me.categories[1].projectedTruth, isNull);
    expect(v.me.standings.projectedDriverOrder.first, 'VER');
    expect(v.me.standings.myDriverPicks.first.driverCode, 'VER');
    expect(v.me.projectedPointsTotal, 11);
    expect(v.leaderboard.first.displayName, 'Me');
    expect(v.leaderboard.first.preseasonPointsProjected, 11);
  });
}
