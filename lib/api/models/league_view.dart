import 'league_member.dart';

class LeagueView {
  final String id;
  final String name;
  final String? joinCode;
  final String role;
  /// True when the league has a join password set. Drives whether the
  /// join screen prompts for one and whether settings shows "Change
  /// password" vs "Set password". Defaults to false for backwards-compat
  /// when the field is missing (pre-password backends).
  final bool hasPassword;
  final List<LeagueMember> members;

  const LeagueView({
    required this.id,
    required this.name,
    required this.role,
    required this.joinCode,
    required this.hasPassword,
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
      hasPassword: l['hasPassword'] as bool? ?? false,
      members: ms,
    );
  }
}
