import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/theme/team_colors.dart';

void main() {
  group('teamColor', () {
    test('curated map wins over fallback', () {
      expect(
        teamColor('red_bull', fallbackHex: 'F47600'),
        const Color(0xFF1E41FF),
      );
    });

    test('falls back to provided hex when constructor is unknown', () {
      expect(
        teamColor('zzz_new_team', fallbackHex: 'F47600'),
        const Color(0xFFF47600),
      );
    });

    test('returns neutral grey when constructor unknown and no fallback', () {
      expect(teamColor('zzz_new_team'), const Color(0xFF707070));
    });

    test('ignores malformed fallback hex', () {
      expect(teamColor('zzz_new_team', fallbackHex: 'not-hex'), const Color(0xFF707070));
    });

    test('alias resolution still works (alphatauri -> rb)', () {
      expect(teamColor('alphatauri'), const Color(0xFF6692FF));
    });
  });

  // Guards against the curated map drifting from the live data again. These are
  // the exact constructorIds /api/sessions/:id/results returns for the 2026
  // grid (OpenF1-style — long forms differ from the standings endpoint's ids).
  group('2026 results constructorIds', () {
    const resultsIds = <String>[
      'red_bull_racing', 'ferrari', 'mclaren', 'mercedes', 'aston_martin',
      'alpine', 'williams', 'haas_f1_team', 'racing_bulls', 'audi', 'cadillac',
    ];

    test('all resolve to a real (non-fallback) colour', () {
      for (final id in resultsIds) {
        expect(teamColor(id), isNot(const Color(0xFF707070)),
            reason: '$id fell back to grey');
      }
    });

    test('renamed teams alias onto their canonical curated colour', () {
      expect(teamColor('red_bull_racing'), teamColor('red_bull'));
      expect(teamColor('haas_f1_team'), teamColor('haas'));
      expect(teamColor('racing_bulls'), teamColor('rb'));
    });

    test('new 2026 teams have dedicated colours', () {
      expect(teamColor('audi'), const Color(0xFFF50537));
      expect(teamColor('cadillac'), const Color(0xFF1A2B4A));
    });
  });
}
