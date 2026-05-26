class UserLeague {
  final String id;
  final String name;
  final String role; // 'owner' | 'member'

  const UserLeague({required this.id, required this.name, required this.role});

  factory UserLeague.fromJson(Map<String, dynamic> j) => UserLeague(
        id: j['id'] as String,
        name: j['name'] as String,
        role: j['role'] as String,
      );
}
