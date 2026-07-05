import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/state/seen_results_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('load is empty before anything is marked', () async {
    expect(await SeenResultsStore().load(), isEmpty);
  });

  test('markSeen persists and is additive across instances', () async {
    await SeenResultsStore().markSeen([1, 2]);
    // A fresh instance reads the same backing store.
    expect(await SeenResultsStore().load(), {1, 2});

    await SeenResultsStore().markSeen([2, 3]);
    expect(await SeenResultsStore().load(), {1, 2, 3});
  });

  test('markSeen with no ids is a no-op', () async {
    await SeenResultsStore().markSeen(const []);
    expect(await SeenResultsStore().load(), isEmpty);
  });
}
