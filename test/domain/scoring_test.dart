import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/models/session_result.dart';
import 'package:predictiongame/domain/scoring.dart';

SessionResult _row(int pos, String code) => SessionResult(
      position: pos,
      driverCode: code,
      driverName: code,
      constructorId: 'x',
      constructorName: 'X',
    );

void main() {
  final result = [
    _row(1, 'NOR'),
    _row(2, 'PIA'),
    _row(3, 'LEC'),
    _row(4, 'TSU'),
    _row(5, 'RUS'),
    _row(6, 'VER'),
  ];

  group('outcomeFor', () {
    test('exact slot match', () {
      expect(outcomeFor('NOR', 1, result, 5), PickOutcome.exact);
    });
    test('in top-N but wrong slot', () {
      expect(outcomeFor('NOR', 3, result, 5), PickOutcome.inTopN);
    });
    test('not in top-N', () {
      expect(outcomeFor('VER', 1, result, 5), PickOutcome.miss);
    });
  });
}
