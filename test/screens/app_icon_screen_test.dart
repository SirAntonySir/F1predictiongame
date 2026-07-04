import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/avatar/avatar_config.dart';
import 'package:predictiongame/avatar/avatar_palette.dart';
import 'package:predictiongame/screens/app_icon_screen.dart';
import 'package:predictiongame/state/avatar_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app(AvatarController c) =>
    MaterialApp(home: AppIconScreen(controller: c));

Future<AvatarController> _controller() {
  SharedPreferences.setMockInitialValues({});
  return AvatarController.load();
}

/// Both pose sections on one tall surface so tile taps don't depend on
/// scroll physics.
void _tallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('shows one tile per pose and livery', (tester) async {
    final c = await _controller();
    _tallViewport(tester);
    await tester.pumpWidget(_app(c));
    await tester.pump();

    // Only poses with baked icon assets get a gallery section — pose 3 ships
    // for the splash/builder but has no bundled launcher icons.
    final baked =
        AvatarPose.values.where((p) => p.hasBakedIcons).toList();
    for (final pose in AvatarPose.values) {
      expect(find.text(pose.label.toUpperCase()),
          pose.hasBakedIcons ? findsOneWidget : findsNothing);
    }
    for (final preset in avatarPresets) {
      expect(find.text(preset.name.toUpperCase()),
          findsNWidgets(baked.length));
    }
  });

  testWidgets('tapping a tile persists the variant immediately',
      (tester) async {
    final c = await _controller();
    _tallViewport(tester);
    await tester.pumpWidget(_app(c));
    await tester.pump();

    expect(c.config.iconVariant, AvatarConfig.defaultIcon);
    // ROSSO appears once per pose — pose1 first, pose3 last. The plugin
    // channel is absent in tests; the tap must still persist the choice
    // (and surface a toast) rather than throw.
    await tester.tap(find.text('ROSSO').last);
    await tester.pump(const Duration(seconds: 4));
    expect(c.config.iconVariant, 'pose3_rosso');

    await tester.tap(find.text('ROSSO').first);
    await tester.pump(const Duration(seconds: 4));
    expect(c.config.iconVariant, 'pose1_rosso');
  });

  testWidgets('every icon tile has an errorBuilder placeholder', (tester) async {
    // A bake that falls out of sync with the registered variants must not
    // spray red error boxes across the gallery — each tile degrades to a
    // neutral placeholder instead.
    final c = await _controller();
    _tallViewport(tester);
    await tester.pumpWidget(_app(c));
    await tester.pump();

    final images = tester.widgetList<Image>(find.byType(Image));
    expect(images, isNotEmpty);
    for (final img in images) {
      expect(img.errorBuilder, isNotNull);
    }
  });

  testWidgets('LIGHT toggle switches tiles to the light-background variants',
      (tester) async {
    final c = await _controller();
    _tallViewport(tester);
    await tester.pumpWidget(_app(c));
    await tester.pump();

    await tester.tap(find.text('LIGHT'));
    await tester.pump();
    await tester.tap(find.text('ROSSO').first);
    await tester.pump(const Duration(seconds: 4));
    expect(c.config.iconVariant, 'pose1_rosso_light');

    await tester.tap(find.text('DARK'));
    await tester.pump();
    await tester.tap(find.text('ROSSO').first);
    await tester.pump(const Duration(seconds: 4));
    expect(c.config.iconVariant, 'pose1_rosso');
  });
}
