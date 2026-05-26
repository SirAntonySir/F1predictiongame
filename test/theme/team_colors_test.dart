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
}
