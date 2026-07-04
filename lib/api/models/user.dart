class User {
  final String id;
  final String email;
  final String displayName;
  /// Opaque AvatarConfig JSON (or null → user hasn't customized). Rendered
  /// client-side; kept as a raw string since only the avatar layer parses it.
  final String? avatar;
  final DateTime createdAt;

  const User({
    required this.id,
    required this.email,
    required this.displayName,
    this.avatar,
    required this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> j) => User(
        id: j['id'] as String,
        email: j['email'] as String,
        displayName: j['displayName'] as String,
        avatar: j['avatar'] as String?,
        createdAt: DateTime.parse(j['createdAt'] as String),
      );
}
