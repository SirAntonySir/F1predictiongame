import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class TokenStorage {
  Future<String?> read();
  Future<void>    write(String token);
  Future<void>    clear();
}

class SecureTokenStorage implements TokenStorage {
  static const _key = 'f1pg.auth.token';
  final FlutterSecureStorage _store;
  SecureTokenStorage({FlutterSecureStorage? store})
      : _store = store ?? const FlutterSecureStorage();

  @override
  Future<String?> read() => _store.read(key: _key);

  @override
  Future<void> write(String token) => _store.write(key: _key, value: token);

  @override
  Future<void> clear() => _store.delete(key: _key);
}

class InMemoryTokenStorage implements TokenStorage {
  String? _token;
  @override
  Future<String?> read() async => _token;
  @override
  Future<void> write(String token) async { _token = token; }
  @override
  Future<void> clear() async { _token = null; }
}
