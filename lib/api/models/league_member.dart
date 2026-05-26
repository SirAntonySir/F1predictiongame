class LeagueMember {
  final String id;
  final String displayName;
  final String role;

  const LeagueMember({required this.id, required this.displayName, required this.role});

  factory LeagueMember.fromJson(Map<String, dynamic> j) => LeagueMember(
        id: j['userId'] as String,
        displayName: j['displayName'] as String,
        role: j['role'] as String,
      );
}
