import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/components/podium/podium_data.dart';
import 'package:predictiongame/components/podium/results_podium.dart';
import 'package:predictiongame/components/podium/results_podium_sheet.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('ResultsPodium renders sample data in $brightness',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: Scaffold(
          body: Center(
            child: SizedBox(
                width: 360, child: ResultsPodium(data: PodiumData.sample())),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // Winner + medals render their labels.
      expect(find.text('ANTON'), findsOneWidget);
      expect(find.text('+24'), findsOneWidget);
    });
  }

  testWidgets('showResultsPodium shows both buttons and dismisses',
      (tester) async {
    var shownAll = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () => showResultsPodium(ctx, PodiumData.sample(),
                  onShowAll: () => shownAll++),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('RESULTS ARE IN'), findsOneWidget);
    expect(find.text('NICE'), findsOneWidget);
    expect(find.text('SHOW ALL'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Show all dismisses and fires the callback.
    await tester.tap(find.text('SHOW ALL'));
    await tester.pumpAndSettle();
    expect(find.text('RESULTS ARE IN'), findsNothing);
    expect(shownAll, 1);
  });

  testWidgets('Close button dismisses the sheet', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () => showResultsPodium(ctx, PodiumData.sample()),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Close'), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('RESULTS ARE IN'), findsNothing);
  });
}
