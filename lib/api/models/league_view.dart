import 'league_member.dart';

class LeagueView {
  final String id;
  final String name;
  final String? joinCode;
  final String role;
  final List<LeagueMember> members;

  const LeagueView({
    required this.id,
    required this.name,
    required this.role,
    required this.joinCode,
    required this.members,
  });

  factory LeagueView.fromJson(Map<String, dynamic> j) {
    final l = j['league'] as Map<String, dynamic>;
    final ms = (j['members'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(LeagueMember.fromJson)
        .toList();
    return LeagueView(
      id: l['id'] as String,
      name: l['name'] as String,
      role: l['role'] as String,
      joinCode: l['joinCode'] as String?,
      members: ms,
    );
  }
}
