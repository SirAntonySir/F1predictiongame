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

  group('scoreRace (Top-5, ordered)', () {
    test('all five exact = 40 points', () {
      expect(scoreRace(['NOR', 'PIA', 'LEC', 'TSU', 'RUS'], result), 40);
    });

    test('right drivers wrong slots = 5 × NEAR = 20', () {
      expect(scoreRace(['RUS', 'TSU', 'LEC', 'PIA', 'NOR'], result), 20);
    });

    test('mixed: 2 exact + 1 near + 2 miss = 8+8+4+0+0 = 20', () {
      expect(scoreRace(['NOR', 'LEC', 'PIA', 'XXX', 'YYY'], result), 20);
    });

    test('all miss = 0', () {
      expect(scoreRace(['AAA', 'BBB', 'CCC', 'DDD', 'EEE'], result), 0);
    });
  });

  group('scoreQualifying (Top-2)', () {
    test('both exact = 16', () {
      expect(scoreQualifying(['NOR', 'PIA'], result), 16);
    });
    test('swap = 8', () {
      expect(scoreQualifying(['PIA', 'NOR'], result), 8);
    });
  });

  group('scoreSprintQualifying (Top-1)', () {
    test('pole exact = 8', () {
      expect(scoreSprintQualifying(['NOR'], result), 8);
    });
    test('miss = 0', () {
      expect(scoreSprintQualifying(['VER'], result), 0);
    });
  });

  group('scoreSprint (Top-3)', () {
    test('all exact = 24', () {
      expect(scoreSprint(['NOR', 'PIA', 'LEC'], result), 24);
    });
    test('one near = 12 (1 exact + 1 near + 1 miss)', () {
      expect(scoreSprint(['NOR', 'LEC', 'TSU'], result), 12);
    });
  });

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
