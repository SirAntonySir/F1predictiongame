import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/models/leaderboard_row.dart';
import 'package:predictiongame/api/models/session_leaderboard_row.dart';
import 'package:predictiongame/domain/season_headline.dart';

LeaderboardRow _row(String id, {required int inSeason, int pre = 0}) =>
    LeaderboardRow(
      userId: id,
      displayName: id,
      inSeasonPoints: inSeason,
      preseasonPoints: pre,
      pointsTotal: inSeason + pre,
      sessionsScored: 0,
    );

SessionLeaderboardRow _scored(int sessionId, int round) => SessionLeaderboardRow(
      sessionId: sessionId,
      sessionType: 'race',
      eventRound: round,
      eventName: 'R$round',
      scheduledStart: DateTime.utc(2026, 1, round),
      members: const [
        SessionLeaderboardMember(userId: 'me', displayName: 'me', pointsTotal: 1),
      ],
    );

void main() {
  test('points and rank are in-season, even when preseason flips the total order', () {
    final h = seasonHeadline(myUserId: 'me', leaderboard: [
      _row('me', inSeason: 142, pre: 48), // total 190 — 1st on total
      _row('lukas', inSeason: 150, pre: 20), // total 170 — 1st in-season
      _row('simon', inSeason: 100),
    ], sessions: const []);
    expect(h.points, 142);
    expect(h.rank, 2);
    expect(h.tied, isFalse);
    expect(h.memberCount, 3);
  });

  test('players level on in-season points share the rank', () {
    final h = seasonHeadline(myUserId: 'me', leaderboard: [
      _row('lukas', inSeason: 120),
      _row('me', inSeason: 120),
      _row('simon', inSeason: 100),
    ], sessions: const []);
    expect(h.rank, 1);
    expect(h.tied, isTrue);
  });

  test('both averages are in-season points per round held, preseason excluded', () {
    final h = seasonHeadline(myUserId: 'me', leaderboard: [
      _row('me', inSeason: 30, pre: 40),
      _row('lukas', inSeason: 50, pre: 0),
    ], sessions: [
      _scored(1, 1), _scored(2, 1), // quali + race of round 1 count once
      _scored(3, 2),
    ]);
    expect(h.avgPerRound, 15.0); // 30 / 2 rounds
    expect(h.leagueAvgPerRound, 20.0); // (30 + 50) / (2 players × 2 rounds)
  });

  test('no averages before any round is scored', () {
    final h = seasonHeadline(
        myUserId: 'me', leaderboard: [_row('me', inSeason: 0)], sessions: const []);
    expect(h.avgPerRound, isNull);
    expect(h.leagueAvgPerRound, isNull);
  });

  test('no rank when the caller is not on the leaderboard', () {
    final h = seasonHeadline(
        myUserId: 'me', leaderboard: [_row('lukas', inSeason: 10)], sessions: const []);
    expect(h.rank, isNull);
    expect(h.points, 0);
  });
}
