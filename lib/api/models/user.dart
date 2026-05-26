class User {
  final String id;
  final String email;
  final String displayName;
  final DateTime createdAt;

  const User({
    required this.id,
    required this.email,
    required this.displayName,
    required this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> j) => User(
        id: j['id'] as String,
        email: j['email'] as String,
        displayName: j['displayName'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
      );
}
