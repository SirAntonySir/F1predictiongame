import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/components/ticket/ticket_title.dart';

void main() {
  group('ticketTitle', () {
    test('plain styles shorten "Grand Prix" to GP instead of appending it', () {
      final t = ticketTitle('Monaco Grand Prix', hasScript: false);
      expect(t.title, 'MONACO GP');
      expect(t.script, isNull);
    });

    test('script styles print the place and hand "Grand Prix" to the script line', () {
      final t = ticketTitle('Monaco Grand Prix', hasScript: true);
      expect(t.title, 'MONACO');
      expect(t.script, 'Grand Prix');
    });

    test('names that do not end in "Grand Prix" are left whole', () {
      for (final hasScript in [false, true]) {
        final t = ticketTitle('Bahrain Grand Prix in Malaysia', hasScript: hasScript);
        expect(t.title, 'BAHRAIN GRAND PRIX IN MALAYSIA');
        expect(t.script, isNull);
      }
    });
  });
}
