import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/models/leaderboard_row.dart';
import 'package:predictiongame/api/models/player_profile.dart';
import 'package:predictiongame/api/models/user.dart';

void main() {
  group('avatar fields parse from JSON', () {
    test('User.avatar (present and absent)', () {
      final withAvatar = User.fromJson({
        'id': 'u', 'email': 'e@x.com', 'displayName': 'U',
        'avatar': '{"preset":"bolt"}', 'createdAt': '2026-01-01T00:00:00.000Z',
      });
      expect(withAvatar.avatar, '{"preset":"bolt"}');

      final without = User.fromJson({
        'id': 'u', 'email': 'e@x.com', 'displayName': 'U',
        'avatar': null, 'createdAt': '2026-01-01T00:00:00.000Z',
      });
      expect(without.avatar, isNull);
    });

    test('PlayerHeader.avatarConfig reads the "avatar" key', () {
      final h = PlayerHeader.fromJson({
        'userId': 'u', 'displayName': 'U', 'avatar': '{"preset":"verde"}',
        'joinedAt': '2026-01-01T00:00:00.000Z', 'isSelf': false,
      });
      expect(h.avatarConfig, '{"preset":"verde"}');
    });

    test('LeaderboardRow.avatarConfig (present and absent)', () {
      final row = LeaderboardRow.fromJson({
        'userId': 'u', 'displayName': 'U', 'avatarConfig': '{"preset":"papaya"}',
        'inSeasonPoints': 1, 'preseasonPoints': 2, 'pointsTotal': 3,
        'sessionsScored': 4,
      });
      expect(row.avatarConfig, '{"preset":"papaya"}');

      final bare = LeaderboardRow.fromJson({
        'userId': 'u', 'displayName': 'U',
        'inSeasonPoints': 0, 'preseasonPoints': 0, 'pointsTotal': 0,
        'sessionsScored': 0,
      });
      expect(bare.avatarConfig, isNull);
    });
  });
}
