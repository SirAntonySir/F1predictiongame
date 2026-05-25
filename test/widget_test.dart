import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/main.dart';
import 'package:predictiongame/theme/colors.dart';

void main() {
  testWidgets('Light theme uses the brand surface', (tester) async {
    await tester.pumpWidget(const F1PgApp());
    final BuildContext ctx = tester.element(find.byType(Scaffold));
    expect(Theme.of(ctx).scaffoldBackgroundColor, LightPalette.surface);
  });
}
