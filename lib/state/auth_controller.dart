import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthController extends ChangeNotifier {
  static const _key = 'current_user_id';
  String? _currentUserId;
  AuthController(this._currentUserId);

  String? get currentUserId => _currentUserId;
  bool get isLoggedIn => _currentUserId != null;

  static Future<AuthController> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AuthController(prefs.getString(_key));
  }

  Future<void> login(String userId) async {
    _currentUserId = userId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, userId);
    notifyListeners();
  }

  Future<void> logout() async {
    _currentUserId = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    notifyListeners();
  }
}
