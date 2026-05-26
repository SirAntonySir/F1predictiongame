import 'user.dart';
import 'user_league.dart';

class MeResult {
  final User user;
  final List<UserLeague> leagues;
  const MeResult({required this.user, required this.leagues});

  factory MeResult.fromJson(Map<String, dynamic> j) => MeResult(
        user: User.fromJson(j['user'] as Map<String, dynamic>),
        leagues: (j['leagues'] as List)
            .cast<Map<String, dynamic>>()
            .map(UserLeague.fromJson)
            .toList(),
      );
}
