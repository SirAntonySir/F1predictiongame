import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/components/app_card.dart';
import 'package:predictiongame/components/countdown.dart';
import 'package:predictiongame/components/session_chip.dart';
import 'package:predictiongame/components/trend_badge.dart';
import 'package:predictiongame/theme/app_theme.dart';

Widget _frame(Widget child, {Brightness b = Brightness.light}) => MaterialApp(
      theme: b == Brightness.light ? AppTheme.light() : AppTheme.dark(),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  testWidgets('AppCard renders its child', (tester) async {
    await tester.pumpWidget(_frame(const AppCard(child: Text('hi'))));
    expect(find.text('hi'), findsOneWidget);
  });

  testWidgets('TrendBadge shows direction', (tester) async {
    await tester.pumpWidget(_frame(const TrendBadge(direction: TrendDirection.up, label: '1')));
    expect(find.text('▲ 1'), findsOneWidget);
  });

  testWidgets('SessionChip shows label and state', (tester) async {
    await tester.pumpWidget(_frame(const SessionChip(label: 'RACE', state: ChipState.next)));
    expect(find.text('RACE'), findsOneWidget);
  });

  testWidgets('Countdown renders D/H/M from a future date', (tester) async {
    final target = DateTime.now().add(const Duration(days: 2, hours: 14, minutes: 32));
    await tester.pumpWidget(_frame(Countdown(target: target)));
    expect(find.text('02'), findsOneWidget);
    expect(find.text('14'), findsOneWidget);
  });
}
