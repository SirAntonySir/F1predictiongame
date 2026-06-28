/// Abstraction over the platform push SDK so [PushService] logic stays testable
/// without Firebase. The real implementation (FCM) lives in `fcm_transport.dart`
/// and is the only file that imports firebase_messaging; tests use a fake.
abstract class PushTransport {
  /// `'ios'` or `'android'` — reported to the backend with the token so it can
  /// route through the right delivery channel.
  String get platform;

  /// Ask the OS for notification permission. Returns true if granted.
  Future<bool> requestPermission();

  /// The current registration token, or null if unavailable (permission denied,
  /// no Play Services, Firebase not configured yet, …).
  Future<String?> getToken();

  /// Fires whenever the SDK rotates the token — the new token must be
  /// re-registered with the backend.
  Stream<String> get onTokenRefresh;
}
