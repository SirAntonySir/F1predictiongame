import 'package:flutter/foundation.dart';
import '../api/api_client.dart';
import '../api/models/notification_prefs.dart';

/// Server-backed notification preferences. Since the backend now fires the
/// notifications, it owns these values; this controller is a thin cache over
/// `GET/PUT /api/notification-prefs` so the settings screen stays instant.
///
/// Updates are optimistic: the cached value flips immediately (so the toggle
/// doesn't lag a round-trip) and reverts if the PUT fails. The endpoint is
/// authenticated, so [refresh] is a no-op-until-logged-in call made after auth.
class NotificationSettingsController extends ChangeNotifier {
  NotificationSettingsController({required ApiClient api}) : _api = api;

  final ApiClient _api;
  NotificationPrefs _prefs = NotificationPrefs.defaults;
  bool _loaded = false;

  /// Test seam — start from a known prefs value without hitting the network.
  @visibleForTesting
  factory NotificationSettingsController.forTesting({
    required ApiClient api,
    NotificationPrefs? prefs,
  }) {
    final c = NotificationSettingsController(api: api);
    if (prefs != null) {
      c._prefs = prefs;
      c._loaded = true;
    }
    return c;
  }

  NotificationPrefs get prefs => _prefs;
  bool get loaded => _loaded;
  bool get enabled => _prefs.enabled;
  bool get quietHoursEnabled => _prefs.quietEnabled;
  int get quietStartMin => _prefs.quietStartMin;
  int get quietEndMin => _prefs.quietEndMin;

  /// Pull the latest server values. Best-effort — on failure (offline, not yet
  /// authenticated) the cached/default values are kept.
  Future<void> refresh() async {
    try {
      _prefs = await _api.getNotificationPrefs();
      _loaded = true;
      notifyListeners();
    } catch (_) {
      // keep cache
    }
  }

  Future<void> setEnabled(bool v) {
    if (_prefs.enabled == v) return Future.value();
    return _patch(_prefs.copyWith(enabled: v),
        () => _api.putNotificationPrefs(enabled: v));
  }

  Future<void> setQuietHoursEnabled(bool v) {
    if (_prefs.quietEnabled == v) return Future.value();
    return _patch(_prefs.copyWith(quietEnabled: v),
        () => _api.putNotificationPrefs(quietEnabled: v));
  }

  Future<void> setQuietWindow({required int startMin, required int endMin}) {
    if (_prefs.quietStartMin == startMin && _prefs.quietEndMin == endMin) {
      return Future.value();
    }
    return _patch(
        _prefs.copyWith(quietStartMin: startMin, quietEndMin: endMin),
        () => _api.putNotificationPrefs(
            quietStartMin: startMin, quietEndMin: endMin));
  }

  Future<void> _patch(
    NotificationPrefs optimistic,
    Future<NotificationPrefs> Function() call,
  ) async {
    final prev = _prefs;
    _prefs = optimistic;
    notifyListeners();
    try {
      _prefs = await call();
    } catch (_) {
      _prefs = prev; // revert — never lie about what the server stored
    }
    notifyListeners();
  }
}
