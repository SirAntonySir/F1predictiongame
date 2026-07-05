import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/models/leaderboard_row.dart';
import 'package:predictiongame/api/models/session_leaderboard_row.dart';
import 'package:predictiongame/components/podium/podium_data.dart';

SessionLeaderboardRow _row({
  required int sessionId,
  required DateTime start,
  required List<SessionLeaderboardMember> members,
  String type = 'race',
  int round = 9,
  String name = 'British Grand Prix',
}) =>
    SessionLeaderboardRow(
      sessionId: sessionId,
      sessionType: type,
      eventRound: round,
      eventName: name,
      scheduledStart: start,
      members: members,
    );

SessionLeaderboardMember _m(String id, int pts, [String? name]) =>
    SessionLeaderboardMember(
        userId: id, displayName: name ?? id, pointsTotal: pts);

LeaderboardRow _lb(String id, String? avatar) => LeaderboardRow(
      userId: id,
      displayName: id,
      inSeasonPoints: 0,
      preseasonPoints: 0,
      pointsTotal: 0,
      sessionsScored: 0,
      avatarConfig: avatar,
    );

void main() {
  final t0 = DateTime(2026, 7, 5, 15, 0);

  group('PodiumData.fromSession', () {
    test('ranks top 3 by points desc, tie-break on name asc', () {
      final row = _row(sessionId: 1, start: t0, members: [
        _m('u_c', 10, 'Carla'),
        _m('u_a', 24, 'Anton'),
        _m('u_b', 16, 'Lukas'),
        _m('u_d', 10, 'Bob'),
      ]);
      final data = PodiumData.fromSession(row, const [])!;
      expect(data.entries.map((e) => e.displayName).toList(),
          ['Anton', 'Lukas', 'Bob']); // 10-pt tie: Bob before Carla
      expect(data.entries.map((e) => e.rank).toList(), [1, 2, 3]);
      expect(data.entries.first.points, 24);
      expect(data.sessionLabel, 'Race');
      expect(data.round, 9);
    });

    test('returns null with fewer than three scorers', () {
      final row = _row(sessionId: 1, start: t0, members: [
        _m('u_a', 24),
        _m('u_b', 16),
      ]);
      expect(PodiumData.fromSession(row, const []), isNull);
    });

    test('joins avatar config by userId', () {
      final row = _row(sessionId: 1, start: t0, members: [
        _m('u_a', 24),
        _m('u_b', 16),
        _m('u_c', 12),
      ]);
      final data = PodiumData.fromSession(row, [
        _lb('u_a', '{"presetId":"rosso"}'),
        _lb('u_c', '{"presetId":"papaya"}'),
      ])!;
      expect(data.entries[0].avatarConfig, '{"presetId":"rosso"}');
      expect(data.entries[1].avatarConfig, isNull); // u_b not in leaderboard
      expect(data.entries[2].avatarConfig, '{"presetId":"papaya"}');
    });
  });

  group('newestUnseenScored', () {
    final scoredA = _row(sessionId: 10, start: t0, members: [_m('u_a', 5)]);
    final scoredB = _row(
        sessionId: 20,
        start: t0.add(const Duration(days: 1)),
        members: [_m('u_a', 5)]);
    final unscored = _row(
        sessionId: 30,
        start: t0.add(const Duration(days: 2)),
        members: const []);

    test('picks the newest scored session by start time', () {
      final r = newestUnseenScored([scoredA, scoredB, unscored], {});
      expect(r!.sessionId, 20);
    });

    test('ignores unscored (empty-members) sessions even if newer', () {
      final r = newestUnseenScored([scoredA, unscored], {});
      expect(r!.sessionId, 10);
    });

    test('returns null when the newest scored session is already seen', () {
      expect(newestUnseenScored([scoredA, scoredB], {20}), isNull);
    });

    test('returns null when nothing is scored', () {
      expect(newestUnseenScored([unscored], {}), isNull);
    });
  });

  test('prettySessionType maps known types and title-cases the rest', () {
    expect(prettySessionType('race'), 'Race');
    expect(prettySessionType('qualifying'), 'Qualifying');
    expect(prettySessionType('sprint_quali'), 'Sprint Quali');
    expect(prettySessionType('fp1'), 'Fp1');
  });
}
