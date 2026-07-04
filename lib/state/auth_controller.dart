import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_client.dart';
import '../api/models/user.dart';
import '../api/models/user_league.dart';
import 'avatar_controller.dart';
import 'predictions_controller.dart';
import 'token_storage.dart';

class AuthController extends ChangeNotifier {
  AuthController({required this.storage});

  /// Assigned exactly once in main.dart after HttpApiClient is constructed.
  late ApiClient api;
  final TokenStorage storage;

  String? _token;
  User? _user;
  List<UserLeague> _leagues = const [];
  bool _sessionExpiredFlag = false;

  String? get token => _token;
  String? get currentUserId => _user?.id;
  User? get user => _user;
  List<UserLeague> get leagues => _leagues;

  bool get isLoggedIn => _token != null && _user != null;
  bool get hasLeague  => _leagues.isNotEmpty;

  PredictionsController? _predictions;
  void attachPredictionsController(PredictionsController c) { _predictions = c; }

  AvatarController? _avatar;
  void attachAvatarController(AvatarController c) { _avatar = c; }

  /// Push the freshly-fetched server avatar into the avatar controller (or
  /// seed the server from a non-default local config). Best-effort; a null
  /// controller (not yet attached at cold-start bootstrap) is a no-op —
  /// main() reconciles once explicitly after the controller loads.
  Future<void> _syncAvatar() async {
    await _avatar?.reconcileWithServer(_user?.avatar);
  }

  bool consumeSessionExpiredFlag() {
    if (!_sessionExpiredFlag) return false;
    _sessionExpiredFlag = false;
    return true;
  }

  Future<void> bootstrap() async {
    final t = await storage.read();
    if (t == null) {
      notifyListeners();
      return;
    }
    _token = t;
    try {
      final me = await api.me();
      _user = me.user;
      _leagues = me.leagues;
      await _syncAvatar();
    } on UnauthorizedException {
      await _wipe();
    }
    notifyListeners();
  }

  Future<void> signup(String email, String password, String displayName) async {
    final r = await api.signup(email: email, password: password, displayName: displayName);
    _token = r.token;
    await storage.write(r.token);
    _user = r.user;
    _leagues = const [];
    await _wipeLegacyStores();
    await _syncAvatar();
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    final r = await api.login(email: email, password: password);
    _token = r.token;
    await storage.write(r.token);
    _user = r.user;
    final me = await api.me();
    _leagues = me.leagues;
    await _wipeLegacyStores();
    await _syncAvatar();
    notifyListeners();
  }

  Future<void> refreshMe() async {
    final me = await api.me();
    _user = me.user;
    _leagues = me.leagues;
    await _syncAvatar();
    notifyListeners();
  }

  Future<void> logout() async {
    try { await api.logout(); } catch (_) {/* ignore network errors on logout */}
    await _wipe();
    notifyListeners();
  }

  void invalidate() {
    if (_token == null && _user == null) return;
    // ignore: discarded_futures
    _wipe();
    _sessionExpiredFlag = true;
    notifyListeners();
  }

  Future<void> _wipe() async {
    _token = null;
    _user = null;
    _leagues = const [];
    _predictions?.clear();
    await storage.clear();
  }

  /// Per the auth wiring spec D5: drop demo-era SharedPreferences keys on
  /// first successful auth so they can never collide with the real backend
  /// user ids.
  Future<void> _wipeLegacyStores() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('predictions_v1');
    await prefs.remove('preseason_v1');
    await prefs.remove('current_user_id'); // old AuthController.load() key
  }

  // Test helper — sets state without going through the API.
  @visibleForTesting
  void applyTestState({required User user, required String token, required List<UserLeague> leagues}) {
    _user = user;
    _token = token;
    _leagues = leagues;
  }
}
