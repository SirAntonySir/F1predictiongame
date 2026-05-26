import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/state/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('ThemeController defaults to system and persists changes', () async {
    final c = await ThemeController.load();
    expect(c.mode, ThemeMode.system);
    var notified = 0;
    c.addListener(() => notified++);
    await c.setMode(ThemeMode.dark);
    expect(c.mode, ThemeMode.dark);
    expect(notified, 1);

    final c2 = await ThemeController.load();
    expect(c2.mode, ThemeMode.dark);
  });

  // AuthController is covered by test/state/auth_controller_test.dart.
  // LeagueController is a thin backend-backed cache — covered by integration via screens.
}
