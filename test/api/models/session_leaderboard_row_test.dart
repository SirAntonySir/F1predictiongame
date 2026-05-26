import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/models/session_leaderboard_row.dart';

void main() {
  test('SessionLeaderboardRow.fromJson parses a typical payload', () {
    final row = SessionLeaderboardRow.fromJson({
      'sessionId': 17,
      'sessionType': 'race',
      'eventRound': 3,
      'eventName': 'Australian GP',
      'scheduledStart': '2026-03-08T15:00:00Z',
      'members': [
        {'userId': 'u1', 'displayName': 'Anton', 'pointsTotal': 12},
        {'userId': 'u2', 'displayName': 'Lukas', 'pointsTotal': 4},
      ],
    });
    expect(row.sessionId, 17);
    expect(row.sessionType, 'race');
    expect(row.eventRound, 3);
    expect(row.eventName, 'Australian GP');
    expect(row.scheduledStart, DateTime.parse('2026-03-08T15:00:00Z'));
    expect(row.members.length, 2);
    expect(row.members.first.userId, 'u1');
    expect(row.members.first.displayName, 'Anton');
    expect(row.members.first.pointsTotal, 12);
  });
}
