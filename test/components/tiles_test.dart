import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/components/pod_tile.dart';
import 'package:predictiongame/components/race_tile.dart';
import 'package:predictiongame/components/slot.dart';
import 'package:predictiongame/theme/app_theme.dart';

Widget _frame(Widget child) => MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: Center(child: SizedBox(width: 360, child: child))),
    );

void main() {
  testWidgets('RaceTile shows round, name, when', (tester) async {
    await tester.pumpWidget(_frame(const RaceTile(
      round: 8,
      country: 'Monaco',
      name: 'Monaco GP',
      when: '24 – 26 May',
      state: RaceState.next,
    )));
    expect(find.text('08'), findsOneWidget);
    expect(find.text('MONACO GP'), findsOneWidget);
    expect(find.text('NEXT'), findsOneWidget);
  });

  testWidgets('PodTile shows position + code + team-coloured background',
      (tester) async {
    await tester.pumpWidget(_frame(const PodTile(
      position: 1,
      driverCode: 'NOR',
      constructorId: 'mclaren',
      mark: PodMark.exact,
    )));
    expect(find.text('NOR'), findsOneWidget);
    expect(find.text('P1'), findsOneWidget);
  });

  testWidgets('Slot empty vs filled', (tester) async {
    await tester.pumpWidget(_frame(const Slot(position: 4)));
    expect(find.text('P4'), findsOneWidget);
    expect(find.text('Tap a driver below'), findsOneWidget);

    await tester.pumpWidget(_frame(const Slot(
      position: 1,
      driverCode: 'VER',
      driverName: 'Verstappen',
      number: 1,
      constructorId: 'red_bull',
    )));
    expect(find.text('Verstappen'), findsOneWidget);
  });
}
