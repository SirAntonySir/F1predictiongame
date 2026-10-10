import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/models/player_profile.dart';

Map<String, dynamic> _json({int? inSeasonRank}) => {
      'leagueRank': 4,
      if (inSeasonRank != null) 'inSeasonRank': inSeasonRank,
      'leagueSize': 6,
      'pointsTotal': 190,
      'inSeasonPoints': 142,
      'preseasonPoints': 48,
      'sessionsScored': 30,
    };

void main() {
  test('the header ranks on in-season points, like the League tab default', () {
    final s = PlayerStanding.fromJson(_json(inSeasonRank: 2));
    expect(s.headlineRank, 2);
    expect(s.headlineIsInSeason, isTrue);
    expect(s.leagueRank, 4); // total rank stays available
  });

  test('older backends without inSeasonRank fall back to the total rank', () {
    final s = PlayerStanding.fromJson(_json());
    expect(s.headlineRank, 4);
    expect(s.headlineIsInSeason, isFalse);
  });
}
