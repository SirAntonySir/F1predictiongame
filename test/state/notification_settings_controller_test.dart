import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/api_client.dart';
import 'package:predictiongame/api/models/notification_prefs.dart';
import 'package:predictiongame/state/notification_settings_controller.dart';

class _FakeApi implements ApiClient {
  NotificationPrefs stored;
  bool failPut = false;
  final puts = <Map<String, dynamic>>[];
  _FakeApi(this.stored);

  @override
  Future<NotificationPrefs> getNotificationPrefs() async => stored;

  @override
  Future<NotificationPrefs> putNotificationPrefs({
    bool? enabled,
    bool? quietEnabled,
    int? quietStartMin,
    int? quietEndMin,
  }) async {
    puts.add({
      if (enabled != null) 'enabled': enabled,
      if (quietEnabled != null) 'quietEnabled': quietEnabled,
      if (quietStartMin != null) 'quietStartMin': quietStartMin,
      if (quietEndMin != null) 'quietEndMin': quietEndMin,
    });
    if (failPut) throw Exception('boom');
    stored = stored.copyWith(
      enabled: enabled,
      quietEnabled: quietEnabled,
      quietStartMin: quietStartMin,
      quietEndMin: quietEndMin,
    );
    return stored;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  test('refresh pulls server values into the cache', () async {
    final api = _FakeApi(const NotificationPrefs(
        enabled: false, quietEnabled: true, quietStartMin: 1380, quietEndMin: 420));
    final c = NotificationSettingsController(api: api);
    expect(c.enabled, true); // defaults before refresh
    await c.refresh();
    expect(c.enabled, false);
    expect(c.quietHoursEnabled, true);
    expect(c.quietStartMin, 1380);
    expect(c.loaded, true);
  });

  test('setEnabled is optimistic and PUTs only that field', () async {
    final api = _FakeApi(NotificationPrefs.defaults);
    final c = NotificationSettingsController(api: api);
    await c.setEnabled(false);
    expect(c.enabled, false);
    expect(api.puts, [
      {'enabled': false}
    ]);
  });

  test('a failed PUT reverts the optimistic change', () async {
    final api = _FakeApi(NotificationPrefs.defaults)..failPut = true;
    final c = NotificationSettingsController(api: api);
    await c.setEnabled(false);
    expect(c.enabled, true); // reverted
  });

  test('no-op when the value is unchanged', () async {
    final api = _FakeApi(NotificationPrefs.defaults);
    final c = NotificationSettingsController(api: api);
    await c.setEnabled(true); // already default true
    expect(api.puts, isEmpty);
  });
}
