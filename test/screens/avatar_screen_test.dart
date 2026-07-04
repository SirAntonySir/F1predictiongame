import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/avatar/avatar_palette.dart';
import 'package:predictiongame/components/painted_splash.dart';
import 'package:predictiongame/screens/avatar_screen.dart';
import 'package:predictiongame/state/avatar_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app(AvatarController c) =>
    MaterialApp(home: AvatarScreen(controller: c));

Future<AvatarController> _controller() {
  SharedPreferences.setMockInitialValues({});
  return AvatarController.load();
}

/// The whole builder (preview + chips + rows + icon gallery) on one tall
/// surface, so taps don't depend on scroll physics.
void _tallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('shows preview, save pill, chips, region rows, icon gallery',
      (tester) async {
    final c = await _controller();
    _tallViewport(tester);
    await tester.pumpWidget(_app(c));
    await tester.pump(const Duration(seconds: 4));

    expect(find.byType(PaintedSplash), findsOneWidget);
    expect(find.text('SAVE'), findsOneWidget);
    for (final preset in avatarPresets) {
      // One livery chip each; the icon gallery lives on its own screen.
      expect(find.text(preset.name.toUpperCase()), findsOneWidget);
    }
    for (final region in AvatarRegion.values) {
      expect(find.text(region.label), findsOneWidget);
    }
  });

  testWidgets('edits stay draft until SAVE persists them', (tester) async {
    final c = await _controller();
    _tallViewport(tester);
    await tester.pumpWidget(_app(c));
    await tester.pump(const Duration(seconds: 4));

    await tester.tap(find.text('PAPAYA').first); // livery chip
    await tester.pump(); // rebuild so the next chip sees the new draft
    await tester.tap(find.text('ARMS CROSSED').first); // pose chip
    await tester.pump(const Duration(seconds: 4));
    // Draft only — the controller still holds the saved default.
    expect(c.config.presetId, 'undercut');
    expect(c.config.pose, AvatarPose.pose1);

    await tester.tap(find.text('SAVE'));
    await tester.pump(const Duration(seconds: 4));
    expect(c.config.presetId, 'papaya');
    expect(c.config.pose, AvatarPose.pose2);
  });

  testWidgets('region color pick marks EDITED and persists on SAVE',
      (tester) async {
    final c = await _controller();
    _tallViewport(tester);
    await tester.pumpWidget(_app(c));
    await tester.pump(const Duration(seconds: 4));

    await tester.tap(find.text('Helmet'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('EDITED'), findsOneWidget);
    expect(c.config.overrides, isEmpty); // draft only

    await tester.tap(find.text('SAVE'));
    await tester.pump(const Duration(seconds: 4));
    expect(c.config.overrides.containsKey(AvatarRegion.helmet), isTrue);
  });

  testWidgets('RESET clears draft overrides', (tester) async {
    final c = await _controller();
    await c.setRegionColor(AvatarRegion.boots, const Color(0xFF0090FF));
    _tallViewport(tester);
    await tester.pumpWidget(_app(c));
    await tester.pump(const Duration(seconds: 4));

    expect(find.text('RESET'), findsOneWidget);
    await tester.tap(find.text('RESET'));
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('RESET'), findsNothing);
    expect(find.text('EDITED'), findsNothing);
    // Saved config still has the override until SAVE commits the clear.
    expect(c.config.overrides, isNotEmpty);
    await tester.tap(find.text('SAVE'));
    await tester.pump(const Duration(seconds: 4));
    expect(c.config.overrides, isEmpty);
  });

  testWidgets('cancelling the picker leaves the draft untouched',
      (tester) async {
    final c = await _controller();
    _tallViewport(tester);
    await tester.pumpWidget(_app(c));
    await tester.pump(const Duration(seconds: 4));

    await tester.tap(find.text('Boots'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('EDITED'), findsNothing);
    expect(c.config.isCustom, isFalse);
  });
}
