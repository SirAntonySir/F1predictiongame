import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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

  // The encrypted SharedPreferences blob can survive an app reinstall via
  // Android Auto Backup, but the AndroidKeyStore key it was sealed with does
  // not — every read then throws `javax.crypto.BadPaddingException`. Same
  // shape on iOS keychain mismatches after restore. Treat any decrypt-related
  // PlatformException as "no token, wipe and move on" so boot doesn't die.
  bool _isCorruption(Object e) {
    if (e is! PlatformException) return false;
    final s = '${e.code} ${e.message}';
    return s.contains('BadPaddingException') ||
        s.contains('BAD_DECRYPT') ||
        s.contains('IllegalBlockSizeException') ||
        s.contains('AEADBadTagException');
  }

  Future<void> _nuke() async {
    try {
      await _store.deleteAll();
    } catch (e, st) {
      debugPrint('SecureTokenStorage.deleteAll failed: $e\n$st');
    }
  }

  @override
  Future<String?> read() async {
    try {
      return await _store.read(key: _key);
    } catch (e, st) {
      if (_isCorruption(e)) {
        debugPrint('SecureTokenStorage: corrupted store, wiping. $e');
        await _nuke();
        return null;
      }
      debugPrint('SecureTokenStorage.read failed: $e\n$st');
      return null;
    }
  }

  @override
  Future<void> write(String token) async {
    try {
      await _store.write(key: _key, value: token);
    } catch (e) {
      if (!_isCorruption(e)) rethrow;
      await _nuke();
      await _store.write(key: _key, value: token);
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _store.delete(key: _key);
    } catch (e) {
      if (!_isCorruption(e)) rethrow;
      await _nuke();
    }
  }
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
