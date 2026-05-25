import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/state/predictions_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('save then read roundtrip', () async {
    final s = await PredictionsStore.load();
    await s.save(
      userId: 'anton',
      sessionId: 52,
      picks: const ['VER', 'LEC', 'NOR', 'PIA', 'SAI'],
    );
    final picks = s.picksFor(userId: 'anton', sessionId: 52);
    expect(picks, ['VER', 'LEC', 'NOR', 'PIA', 'SAI']);
  });

  test('lock sets lockedAt and prevents save', () async {
    final s = await PredictionsStore.load();
    await s.save(userId: 'anton', sessionId: 52, picks: const ['VER']);
    await s.lock(userId: 'anton', sessionId: 52);
    expect(s.isLocked(userId: 'anton', sessionId: 52), true);
    expect(
      () => s.save(userId: 'anton', sessionId: 52, picks: const ['LEC']),
      throwsStateError,
    );
  });

  test('persistence across reload', () async {
    final s = await PredictionsStore.load();
    await s.save(userId: 'anton', sessionId: 52, picks: const ['VER', 'LEC']);
    final s2 = await PredictionsStore.load();
    expect(s2.picksFor(userId: 'anton', sessionId: 52), ['VER', 'LEC']);
  });
}
