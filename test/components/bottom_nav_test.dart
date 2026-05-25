import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/components/bottom_nav.dart';
import 'package:predictiongame/theme/app_theme.dart';

void main() {
  testWidgets('BottomNav fires onTap with the index', (tester) async {
    int? tapped;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        bottomNavigationBar: BottomNav(currentIndex: 0, onTap: (i) => tapped = i),
      ),
    ));
    await tester.tap(find.text('CALENDAR'));
    expect(tapped, 1);
    await tester.tap(find.text('PREDICT'));
    expect(tapped, 2);
  });
}
