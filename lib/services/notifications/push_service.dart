import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../api/api_client.dart';
import 'push_transport.dart';

/// Owns the device-token lifecycle: request permission, register the FCM token
/// with the backend, re-register on rotation, and drop it on logout. This
/// replaces the old on-device [ReminderService] scheduler — the backend now
/// decides what to send; the app only reports where to send it.
///
/// Every network/SDK call is best-effort: a failure here must never block the
/// app. When permission is denied or no token is available, the user simply
/// receives nothing (the spec's accepted trade-off for replacing local
/// notifications entirely).
class PushService {
  PushService({
    required ApiClient api,
    required PushTransport transport,
    String Function()? timezoneProvider,
  })  : _api = api,
        _transport = transport,
        _timezoneProvider = timezoneProvider;

  final ApiClient _api;
  final PushTransport _transport;
  final String Function()? _timezoneProvider;

  StreamSubscription<String>? _sub;
  String? _lastToken;
  bool _started = false;
  bool _permissionGranted = false;

  bool get permissionGranted => _permissionGranted;

  /// Call after login. Idempotent — a second call while already started no-ops.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      _permissionGranted = await _transport.requestPermission();
      if (!_permissionGranted) return;
      final token = await _transport.getToken();
      if (token != null) await _register(token);
      _sub = _transport.onTokenRefresh.listen((t) {
        // ignore: discarded_futures
        _register(t);
      });
    } catch (e, st) {
      // Firebase not configured, no Play Services, etc. — stay silent so boot
      // and login still succeed.
      if (kDebugMode) debugPrint('PushService start failed (continuing): $e\n$st');
    }
  }

  Future<void> _register(String token) async {
    _lastToken = token;
    try {
      await _api.registerDevice(
        token: token,
        platform: _transport.platform,
        timezone: _timezoneProvider?.call(),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('registerDevice failed: $e');
    }
  }

  /// Call on logout — stop listening and drop this device's token server-side
  /// so the user stops receiving pushes here.
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _started = false;
    final token = _lastToken;
    _lastToken = null;
    if (token != null) {
      try {
        await _api.deleteDevice(token);
      } catch (e) {
        if (kDebugMode) debugPrint('deleteDevice failed: $e');
      }
    }
  }
}
