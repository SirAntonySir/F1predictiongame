import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Thin wrapper over flutter_local_notifications used purely for *display* now
/// that scheduling lives on the backend:
///   - render a heads-up banner when a push arrives while the app is foreground
///     (FCM doesn't show its own banner in that state), and
///   - back the in-app Notifications screen's "what's in the tray" list via
///     [active] / [dismiss].
///
/// Best-effort throughout — a plugin failure must not break the app.
class LocalDisplay {
  LocalDisplay._();
  static final LocalDisplay instance = LocalDisplay._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _inited = false;

  static const _channelId = 'push_messages';
  static const _channelName = 'Notifications';
  static const _channelDesc =
      'Undercut alerts: reminders, session start, results.';

  /// [onTapPayload] receives the notification's `payload` (a route string) when
  /// the user taps a banner we displayed in the foreground.
  Future<void> init({void Function(String payload)? onTapPayload}) async {
    if (_inited) return;
    const initIos = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(iOS: initIos, android: initAndroid),
        onDidReceiveNotificationResponse: (resp) {
          final p = resp.payload;
          if (p != null && p.isNotEmpty) onTapPayload?.call(p);
        },
      );
      _inited = true;
    } catch (e) {
      if (kDebugMode) debugPrint('LocalDisplay init failed: $e');
    }
  }

  /// Show a banner for a foreground push. [payload] carries the deep-link route.
  Future<void> show({
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_inited) return;
    const details = NotificationDetails(
      iOS: DarwinNotificationDetails(),
      android: AndroidNotificationDetails(
        _channelId, _channelName,
        channelDescription: _channelDesc,
        importance: Importance.high,
        priority: Priority.high,
      ),
    );
    try {
      // id derived from the title so re-shows of the same alert collapse.
      await _plugin.show(
        id: title.hashCode & 0x7fffffff,
        title: title,
        body: body,
        notificationDetails: details,
        payload: payload,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('LocalDisplay show failed: $e');
    }
  }

  /// Notifications currently sitting in the OS tray (delivered, not dismissed).
  Future<List<ActiveNotification>> active() async {
    if (!_inited) return const [];
    try {
      return await _plugin.getActiveNotifications();
    } catch (_) {
      return const [];
    }
  }

  /// Remove one delivered notification from the tray.
  Future<void> dismiss(int id) async {
    try {
      await _plugin.cancel(id: id);
    } catch (_) {
      // ignore
    }
  }

  bool get inited => _inited;
}
