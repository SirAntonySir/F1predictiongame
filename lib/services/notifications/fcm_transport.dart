import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'local_display.dart';
import 'push_transport.dart';

/// FCM-backed [PushTransport]. The ONLY file that imports firebase_messaging,
/// so the rest of the app (and its tests) stay SDK-agnostic.
///
/// [create] initialises Firebase from the native config files
/// (GoogleService-Info.plist / google-services.json). If those aren't present
/// yet — e.g. before the Firebase project is wired up — it returns null and the
/// app simply runs without push instead of crashing on boot.
class FcmPushTransport implements PushTransport {
  FcmPushTransport._(this._messaging, this._platform);

  final FirebaseMessaging _messaging;
  final String _platform;

  static Future<FcmPushTransport?> create() async {
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);
      final platform =
          defaultTargetPlatform == TargetPlatform.android ? 'android' : 'ios';
      return FcmPushTransport._(FirebaseMessaging.instance, platform);
    } catch (e) {
      if (kDebugMode) debugPrint('Firebase init failed — push disabled: $e');
      return null;
    }
  }

  @override
  String get platform => _platform;

  @override
  Future<bool> requestPermission() async {
    final s = await _messaging.requestPermission();
    return s.authorizationStatus == AuthorizationStatus.authorized ||
        s.authorizationStatus == AuthorizationStatus.provisional;
  }

  @override
  Future<String?> getToken() => _messaging.getToken();

  @override
  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;
}

/// Wire foreground display + tap-to-route. Call once after [FcmPushTransport.create].
/// [onRoute] receives the `data.route` deep link (e.g. `/predict?session=123`).
void attachFcmHandlers({
  required LocalDisplay display,
  required void Function(String route) onRoute,
}) {
  // Foreground: FCM doesn't show a banner itself, so we render one.
  FirebaseMessaging.onMessage.listen((m) {
    final n = m.notification;
    if (n != null) {
      // ignore: discarded_futures
      display.show(
        title: n.title ?? 'F1PG',
        body: n.body ?? '',
        payload: m.data['route'] as String?,
      );
    }
  });
  // Tapped while backgrounded.
  FirebaseMessaging.onMessageOpenedApp.listen((m) {
    final route = m.data['route'] as String?;
    if (route != null && route.isNotEmpty) onRoute(route);
  });
  // Launched from terminated by tapping a push.
  // ignore: discarded_futures
  FirebaseMessaging.instance.getInitialMessage().then((m) {
    final route = m?.data['route'] as String?;
    if (route != null && route.isNotEmpty) onRoute(route);
  });
}

/// Required by FCM so it can deliver while the app is backgrounded/terminated.
/// The OS renders the notification payload itself; nothing to do here.
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {}
