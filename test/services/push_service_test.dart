import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/api_client.dart';
import 'package:predictiongame/services/notifications/push_service.dart';
import 'package:predictiongame/services/notifications/push_transport.dart';

class _FakeApi implements ApiClient {
  final registered = <Map<String, dynamic>>[];
  final deleted = <String>[];

  @override
  Future<void> registerDevice({required String token, required String platform, String? timezone}) async {
    registered.add({'token': token, 'platform': platform, 'timezone': timezone});
  }

  @override
  Future<void> deleteDevice(String token) async {
    deleted.add(token);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeTransport implements PushTransport {
  bool granted;
  String? token;
  int getTokenCalls = 0;
  /// When set, replaces the default `token` reply — lets tests script
  /// null-then-token sequences or the iOS apns-token-not-set throw.
  Future<String?> Function()? getTokenImpl;
  final _refresh = StreamController<String>.broadcast();
  _FakeTransport({this.granted = true, this.token = 'tok-1'});

  @override
  String get platform => 'ios';
  @override
  Future<bool> requestPermission() async => granted;
  @override
  Future<String?> getToken() {
    getTokenCalls++;
    final impl = getTokenImpl;
    if (impl != null) return impl();
    return Future.value(token);
  }

  @override
  Stream<String> get onTokenRefresh => _refresh.stream;
  void rotate(String t) => _refresh.add(t);
}

void main() {
  test('start registers the token with platform + timezone', () async {
    final api = _FakeApi();
    final t = _FakeTransport(token: 'tok-1');
    final svc = PushService(api: api, transport: t, timezoneProvider: () => 'Europe/Vienna');

    await svc.start();

    expect(api.registered, [
      {'token': 'tok-1', 'platform': 'ios', 'timezone': 'Europe/Vienna'}
    ]);
    expect(svc.permissionGranted, true);
  });

  test('start does not register when permission is denied', () async {
    final api = _FakeApi();
    final svc = PushService(api: api, transport: _FakeTransport(granted: false));
    await svc.start();
    expect(api.registered, isEmpty);
    expect(svc.permissionGranted, false);
  });

  test('token rotation re-registers the new token', () async {
    final api = _FakeApi();
    final t = _FakeTransport(token: 'tok-1');
    final svc = PushService(api: api, transport: t);
    await svc.start();
    t.rotate('tok-2');
    await Future<void>.delayed(Duration.zero);
    expect(api.registered.map((r) => r['token']), ['tok-1', 'tok-2']);
  });

  test('stop deletes the last token', () async {
    final api = _FakeApi();
    final t = _FakeTransport(token: 'tok-1');
    final svc = PushService(api: api, transport: t);
    await svc.start();
    await svc.stop();
    expect(api.deleted, ['tok-1']);
  });

  test('start is idempotent', () async {
    final api = _FakeApi();
    final svc = PushService(api: api, transport: _FakeTransport(token: 'tok-1'));
    await svc.start();
    await svc.start();
    expect(api.registered, hasLength(1));
  });

  test('iOS race: getToken throws, a late refresh still registers', () async {
    final api = _FakeApi();
    final t = _FakeTransport()
      ..getTokenImpl = (() async => throw Exception('apns-token-not-set'));
    final svc = PushService(
        api: api, transport: t, tokenRetryDelays: const []);
    await svc.start();
    expect(api.registered, isEmpty);
    // APNs token arrives later → FCM token generated → refresh stream fires.
    t.rotate('tok-late');
    await Future<void>.delayed(Duration.zero);
    expect(api.registered.map((r) => r['token']), ['tok-late']);
  });

  test('getToken null/throw is retried until the token arrives', () async {
    final api = _FakeApi();
    final t = _FakeTransport();
    var calls = 0;
    t.getTokenImpl = () async {
      calls++;
      if (calls == 1) throw Exception('apns-token-not-set');
      if (calls == 2) return null;
      return 'tok-1';
    };
    final svc = PushService(
        api: api,
        transport: t,
        tokenRetryDelays: const [Duration.zero, Duration.zero, Duration.zero]);
    await svc.start();
    expect(calls, 3);
    expect(api.registered.map((r) => r['token']), ['tok-1']);
  });

  test('refresh with the already-registered token does not duplicate', () async {
    final api = _FakeApi();
    final t = _FakeTransport(token: 'tok-1');
    final svc = PushService(api: api, transport: t);
    await svc.start();
    t.rotate('tok-1');
    await Future<void>.delayed(Duration.zero);
    expect(api.registered, hasLength(1));
  });
}
