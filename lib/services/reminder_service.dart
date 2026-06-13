import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import '../api/models/session.dart';
import '../api/models/upcoming_prediction.dart';
import '../state/notification_settings_controller.dart';

/// Schedules local "you haven't picked yet" reminders before each upcoming
/// session's lock time. Three reminders per session: 5 h / 1 h / 10 min out.
///
/// Design notes:
///   - Reminders are CANCELLED when the user saves a prediction for that
///     session (no spam after a pick).
///   - `syncFromUpcoming` is the only entry point and is idempotent — it
///     cancels every pending notification we own and reschedules from scratch
///     using the latest upcoming list. Cheaper than diffing; correct under
///     timezone changes, schedule reshuffles, lock-time edits, etc.
///   - All scheduling happens in the device's *local* timezone, derived from
///     `flutter_timezone` so that DST and travel work correctly.
///   - We don't request notification permission up front; the plugin's
///     `requestPermissions` is called lazily on first schedule. If the user
///     declines, the scheduling silently no-ops — they can re-enable in OS
///     settings later.
class ReminderService {
  ReminderService._();
  static final ReminderService instance = ReminderService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _inited = false;
  bool _permissionGranted = false;
  NotificationSettingsController? _settings;
  /// Cached last-known upcoming list so `resync()` can re-evaluate against
  /// changed settings without a fresh fetch from the API.
  List<UpcomingPrediction> _lastUpcoming = const [];

  /// Inject the settings controller so the service can respect user
  /// preferences (master on/off + quiet hours). Subscribes to changes so
  /// flipping a toggle in Settings re-schedules immediately.
  void attachSettings(NotificationSettingsController c) {
    if (_settings == c) return;
    _settings?.removeListener(_onSettingsChanged);
    _settings = c;
    c.addListener(_onSettingsChanged);
  }

  void _onSettingsChanged() {
    // Fire-and-forget — listeners can't return futures.
    // ignore: discarded_futures
    syncFromUpcoming(_lastUpcoming);
  }

  /// Three lead times we fire reminders at, ordered from latest to earliest.
  static const _offsets = [
    Duration(hours: 5),
    Duration(hours: 1),
    Duration(minutes: 10),
  ];

  static const _channelId = 'pick_reminders';
  static const _channelName = 'Pick reminders';
  static const _channelDesc =
      "Reminders to make your picks before a session's lock time.";

  /// Notification id encoding: sessionId * 10 + bucket (0..2).
  ///
  /// Caps sessionId at 2^31 / 10 ≈ 214M, well above any reasonable F1 session
  /// id. Bucket is the index into [_offsets].
  int _notifId(int sessionId, int bucket) => sessionId * 10 + bucket;

  Future<void> init() async {
    if (_inited) return;
    tzdata.initializeTimeZones();
    try {
      final tzInfo = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(tzInfo.identifier));
    } catch (e) {
      // Falls back to UTC; reminders will still fire, just with the date math
      // interpreted as UTC. Better than crashing.
      if (kDebugMode) debugPrint('ReminderService TZ init failed: $e');
    }

    const initIos = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      settings: const InitializationSettings(
        iOS: initIos,
        android: initAndroid,
      ),
    );
    _inited = true;
  }

  Future<void> _ensurePermission() async {
    if (_permissionGranted) return;
    final ios = _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      final ok = await ios.requestPermissions(alert: true, sound: true);
      _permissionGranted = ok ?? false;
    }
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      final ok = await android.requestNotificationsPermission();
      _permissionGranted = (ok ?? false) || _permissionGranted;
    }
  }

  /// Debug helper for the in-app notification center — exposes whatever the
  /// OS plugin currently has queued. iOS limits pending notifications to ~64;
  /// Android stores them in the AlarmManager.
  Future<List<PendingNotificationRequest>> pendingRequests() async {
    if (!_inited) return const [];
    return _plugin.pendingNotificationRequests();
  }

  /// Plain status snapshot for the notification center: `inited` tells us the
  /// plugin booted, `permissionGranted` is what the last `requestPermissions`
  /// call returned (best-effort — the OS can revoke between syncs).
  ({bool inited, bool permissionGranted}) statusSnapshot() =>
      (inited: _inited, permissionGranted: _permissionGranted);

  /// Cancel every reminder we own. Used before a full reschedule so we don't
  /// leave stale notifications for sessions that disappeared from `upcoming`.
  Future<void> _cancelAllOwn() async {
    final pending = await _plugin.pendingNotificationRequests();
    for (final p in pending) {
      // No other code path schedules notifications today, so cancelling
      // everything pending is fine in practice. If a future feature adds
      // notifications, switch to a tag-based filter.
      await _plugin.cancel(id: p.id);
    }
  }

  /// Recompute the reminder set from the supplied upcoming-predictions list.
  /// Cancels everything pending, then schedules 5h/1h/10min reminders for
  /// every still-unpicked, still-future session — subject to the user's
  /// notification preferences (master toggle + quiet hours).
  Future<void> syncFromUpcoming(List<UpcomingPrediction> upcoming) async {
    if (!_inited) return;
    _lastUpcoming = List.unmodifiable(upcoming);
    final s = _settings?.settings;
    // Master toggle: wipe everything and bail.
    if (s != null && !s.enabled) {
      await _cancelAllOwn();
      return;
    }
    final needsAny = upcoming.any(_needsReminder);
    if (needsAny) await _ensurePermission();
    await _cancelAllOwn();
    if (!_permissionGranted) return;
    final now = DateTime.now();
    for (final u in upcoming) {
      if (!_needsReminder(u)) continue;
      for (var i = 0; i < _offsets.length; i++) {
        final fireAt = u.locksAt.subtract(_offsets[i]);
        if (!fireAt.isAfter(now)) continue;
        // Quiet hours — skip individual buckets that would fire during the
        // user's quiet window. Don't try to shift; the next bucket (closer
        // to lock) will usually fall outside it and serve as the reminder.
        if (s != null && s.isInQuietHours(fireAt)) continue;
        await _scheduleOne(u, fireAt, i);
      }
    }
  }

  bool _needsReminder(UpcomingPrediction u) {
    if (u.isLocked) return false;
    final picks = u.myPicks;
    if (picks != null && picks.isNotEmpty) return false;
    return true;
  }

  /// Cancel the three reminder buckets for one session. Called after the user
  /// saves a prediction — no further "you haven't picked" pings.
  Future<void> cancelForSession(int sessionId) async {
    if (!_inited) return;
    for (var i = 0; i < _offsets.length; i++) {
      await _plugin.cancel(id: _notifId(sessionId, i));
    }
  }

  Future<void> _scheduleOne(
    UpcomingPrediction u,
    DateTime fireAt,
    int bucket,
  ) async {
    final id = _notifId(u.sessionId, bucket);
    final lead = _offsets[bucket];
    final title = lead.inHours >= 1
        ? '${lead.inHours}h until lock'
        : '${lead.inMinutes} min until lock';
    final body =
        "You haven't picked for ${u.eventName} (${_sessionTypeLabel(u.sessionType)}) yet.";

    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: tz.TZDateTime.from(fireAt, tz.local),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: false,
          presentSound: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: 'pick:${u.sessionId}',
    );
  }

  String _sessionTypeLabel(SessionType type) {
    switch (type) {
      case SessionType.race:         return 'Race';
      case SessionType.qualifying:   return 'Qualifying';
      case SessionType.sprint_quali: return 'Sprint Shootout';
      case SessionType.sprint:       return 'Sprint';
      case SessionType.fp1:
      case SessionType.fp2:
      case SessionType.fp3:
        return type.name.toUpperCase();
    }
  }
}
