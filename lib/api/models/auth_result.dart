import 'user.dart';

class AuthResult {
  final User user;
  final String token;
  const AuthResult({required this.user, required this.token});

  factory AuthResult.fromJson(Map<String, dynamic> j) => AuthResult(
        user: User.fromJson(j['user'] as Map<String, dynamic>),
        token: j['token'] as String,
      );
}
