import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/theme/team_colors.dart';

void main() {
  test('resolves canonical constructor ids', () {
    expect(teamColor('red_bull'), const Color(0xFF1E41FF));
    expect(teamColor('ferrari'), const Color(0xFFE8002D));
    expect(teamColor('mclaren'), const Color(0xFFFF8000));
    expect(teamColor('mercedes'), const Color(0xFF27F4D2));
  });

  test('resolves renamed/aliased constructor ids', () {
    expect(teamColor('alphatauri'), teamColor('rb'));
    expect(teamColor('alfa'), teamColor('kick_sauber'));
    expect(teamColor('sauber'), teamColor('kick_sauber'));
  });

  test('falls back to a neutral colour for unknown ids', () {
    expect(teamColor('not_a_team'), const Color(0xFF707070));
  });
}
