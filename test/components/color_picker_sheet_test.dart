import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/components/color_picker_sheet.dart';

/// Opens the picker from a button and returns the harness's popped-color ref.
Widget _harness({
  required Color initial,
  List<({String label, Color color})> matchColors = const [],
  required void Function(Color?) onResult,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () async {
              final c = await showColorPickerSheet(
                context,
                title: 'Helmet',
                initial: initial,
                matchColors: matchColors,
              );
              onResult(c);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('match chips show other regions and tapping one selects it',
      (tester) async {
    Color? result;
    await tester.pumpWidget(_harness(
      initial: const Color(0xFFFFFFFF),
      matchColors: const [
        (label: 'Chest', color: Color(0xFF123456)),
        (label: 'Boots', color: Color(0xFF654321)),
      ],
      onResult: (c) => result = c,
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // The other regions surface as labeled match chips.
    expect(find.text('CHEST'), findsOneWidget);
    expect(find.text('BOOTS'), findsOneWidget);

    // Tapping the Chest chip loads its color; Apply then returns that color.
    await tester.tap(find.text('CHEST'));
    await tester.pump();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(result, const Color(0xFF123456));
  });

  testWidgets('typing a hex code selects that color and Apply returns it',
      (tester) async {
    Color? result;
    await tester.pumpWidget(_harness(
      initial: const Color(0xFFFFFFFF),
      onResult: (c) => result = c,
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '00D2BE');
    await tester.pump();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(result, const Color(0xFF00D2BE));
  });

  testWidgets('hex shorthand expands and invalid input keeps the last color',
      (tester) async {
    Color? result;
    await tester.pumpWidget(_harness(
      initial: const Color(0xFFE10600),
      onResult: (c) => result = c,
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // The field opens showing the initial color.
    final field = find.byType(TextField);
    expect(tester.widget<TextField>(field).controller!.text, '#E10600');

    // '#abc' commits as #AABBCC; non-hex characters are filtered out, so
    // the committed color survives the garbage input.
    await tester.enterText(field, '#abc');
    await tester.pump();
    await tester.enterText(field, 'zz!?');
    await tester.pump();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(result, const Color(0xFFAABBCC));
  });

  testWidgets('hex field tracks colors picked via chips', (tester) async {
    await tester.pumpWidget(_harness(
      initial: const Color(0xFFFFFFFF),
      matchColors: const [(label: 'Chest', color: Color(0xFF123456))],
      onResult: (_) {},
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('CHEST'));
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '#123456',
    );
  });

  testWidgets('dragging the shade square does not dismiss the sheet',
      (tester) async {
    Color? result;
    var popped = false;
    await tester.pumpWidget(_harness(
      initial: const Color(0xFFFF0000),
      onResult: (c) {
        popped = true;
        result = c;
      },
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Apply'), findsOneWidget);

    // A downward drag inside the shade square used to slide the modal away.
    final square = find.byType(CustomPaint).first;
    await tester.drag(square, const Offset(0, 220));
    await tester.pumpAndSettle();

    // Sheet is still open (not dismissed by the drag).
    expect(find.text('Apply'), findsOneWidget);
    expect(popped, isFalse);
    expect(result, isNull);
  });
}
