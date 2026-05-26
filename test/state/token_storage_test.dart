import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/state/token_storage.dart';

void main() {
  group('InMemoryTokenStorage', () {
    test('read returns null when empty', () async {
      final s = InMemoryTokenStorage();
      expect(await s.read(), isNull);
    });

    test('write then read returns the token', () async {
      final s = InMemoryTokenStorage();
      await s.write('abc');
      expect(await s.read(), 'abc');
    });

    test('clear removes the token', () async {
      final s = InMemoryTokenStorage();
      await s.write('abc');
      await s.clear();
      expect(await s.read(), isNull);
    });
  });
}
