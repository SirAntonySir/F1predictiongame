import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persisted preferences for local notifications. Backed by SharedPreferences
/// because they're tiny, sync at boot, and don't need a server round-trip.
///
/// Defaults match the spec:
///   - reminders ON  (the user explicitly asked for pick reminders)
///   - quiet hours OFF
///   - quiet window 22:00–08:00 if they turn it on
class NotificationSettings {
  static const _kEnabled       = 'notif.enabled';
  static const _kQuietEnabled  = 'notif.quietHours.enabled';
  static const _kQuietStartMin = 'notif.quietHours.startMin';
  static const _kQuietEndMin   = 'notif.quietHours.endMin';

  bool enabled;
  bool quietHoursEnabled;
  /// Minutes since local midnight.
  int quietStartMin;
  int quietEndMin;

  NotificationSettings({
    this.enabled = true,
    this.quietHoursEnabled = false,
    this.quietStartMin = 22 * 60,
    this.quietEndMin = 8 * 60,
  });

  static Future<NotificationSettings> load() async {
    final p = await SharedPreferences.getInstance();
    return NotificationSettings(
      enabled:           p.getBool(_kEnabled)         ?? true,
      quietHoursEnabled: p.getBool(_kQuietEnabled)    ?? false,
      quietStartMin:     p.getInt(_kQuietStartMin)    ?? 22 * 60,
      quietEndMin:       p.getInt(_kQuietEndMin)      ?? 8 * 60,
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kEnabled, enabled);
    await p.setBool(_kQuietEnabled, quietHoursEnabled);
    await p.setInt(_kQuietStartMin, quietStartMin);
    await p.setInt(_kQuietEndMin, quietEndMin);
  }

  /// Is `when` inside the configured quiet window? Returns `false` if quiet
  /// hours are disabled. Handles overnight windows (end < start) correctly.
  bool isInQuietHours(DateTime when) {
    if (!quietHoursEnabled) return false;
    final mins = when.hour * 60 + when.minute;
    if (quietStartMin <= quietEndMin) {
      // Same-day window, e.g. 13:00–15:00
      return mins >= quietStartMin && mins < quietEndMin;
    } else {
      // Overnight window, e.g. 22:00–08:00
      return mins >= quietStartMin || mins < quietEndMin;
    }
  }
}

/// ChangeNotifier wrapper around [NotificationSettings] so settings screens
/// and the [ReminderService] can react to changes without a refresh button.
class NotificationSettingsController extends ChangeNotifier {
  final NotificationSettings _s;
  NotificationSettingsController._(this._s);

  static Future<NotificationSettingsController> load() async {
    return NotificationSettingsController._(await NotificationSettings.load());
  }

  /// Test-only constructor — skips SharedPreferences load. The supplied
  /// [settings] still saves to disk when mutated; pass a fresh instance in
  /// tests to avoid touching real storage.
  @visibleForTesting
  factory NotificationSettingsController.forTesting([NotificationSettings? settings]) {
    return NotificationSettingsController._(settings ?? NotificationSettings());
  }

  NotificationSettings get settings => _s;
  bool get enabled => _s.enabled;
  bool get quietHoursEnabled => _s.quietHoursEnabled;
  int  get quietStartMin => _s.quietStartMin;
  int  get quietEndMin   => _s.quietEndMin;

  Future<void> setEnabled(bool v) async {
    if (_s.enabled == v) return;
    _s.enabled = v;
    await _s.save();
    notifyListeners();
  }

  Future<void> setQuietHoursEnabled(bool v) async {
    if (_s.quietHoursEnabled == v) return;
    _s.quietHoursEnabled = v;
    await _s.save();
    notifyListeners();
  }

  Future<void> setQuietWindow({required int startMin, required int endMin}) async {
    if (_s.quietStartMin == startMin && _s.quietEndMin == endMin) return;
    _s.quietStartMin = startMin;
    _s.quietEndMin = endMin;
    await _s.save();
    notifyListeners();
  }
}
