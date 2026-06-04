import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:predictiongame/components/branded_field.dart';
import 'package:predictiongame/theme/app_theme.dart';

Widget _frame(Widget c) => MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: SizedBox(width: 360, child: c)),
    );

bool _obscured(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).obscureText;

void main() {
  testWidgets('obscured field starts hidden and the eye toggles reveal',
      (tester) async {
    await tester.pumpWidget(_frame(BrandedField(
      label: 'Password',
      controller: TextEditingController(text: 'hunter2'),
      obscure: true,
    )));

    // Hidden by default; the "reveal" (solid eye) icon is shown.
    expect(_obscured(tester), isTrue);
    expect(find.byIcon(FontAwesomeIcons.solidEye.data), findsOneWidget);
    expect(find.byIcon(FontAwesomeIcons.solidEyeSlash.data), findsNothing);

    // Tap reveals — text shows, icon flips to eye-slash.
    await tester.tap(find.byType(IconButton));
    await tester.pump();
    expect(_obscured(tester), isFalse);
    expect(find.byIcon(FontAwesomeIcons.solidEyeSlash.data), findsOneWidget);

    // Tap again re-hides.
    await tester.tap(find.byType(IconButton));
    await tester.pump();
    expect(_obscured(tester), isTrue);
  });

  testWidgets('non-obscured field has no eye toggle', (tester) async {
    await tester.pumpWidget(_frame(BrandedField(
      label: 'Display name',
      controller: TextEditingController(),
    )));
    expect(find.byType(IconButton), findsNothing);
    expect(_obscured(tester), isFalse);
  });
}
