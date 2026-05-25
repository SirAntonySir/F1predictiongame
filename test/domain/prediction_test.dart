import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/models/session.dart';
import 'package:predictiongame/domain/prediction.dart';
import 'package:predictiongame/domain/league.dart';

void main() {
  test('PredictionEntry equality by sessionId + userId', () {
    final a = PredictionEntry(
      sessionId: 52,
      userId: 'anton',
      picks: const ['VER', 'LEC'],
      lockedAt: DateTime.utc(2026, 5, 24, 14),
    );
    const b = PredictionEntry(
      sessionId: 52,
      userId: 'anton',
      picks: ['NOR'],
    );
    expect(a.key, b.key);
  });

  test('requiredPicks per session type', () {
    expect(requiredPicks(SessionType.qualifying), 2);
    expect(requiredPicks(SessionType.race), 5);
    expect(requiredPicks(SessionType.sprint_quali), 1);
    expect(requiredPicks(SessionType.sprint), 3);
    expect(requiredPicks(SessionType.fp1), 0);
  });

  test('League contains players', () {
    const l = League(
      id: 'the_box',
      name: 'The Box',
      players: [
        Player(id: 'anton', displayName: 'Anton'),
        Player(id: 'lukas', displayName: 'Lukas'),
      ],
    );
    expect(l.players.length, 2);
    expect(l.players.first.displayName, 'Anton');
  });
}
