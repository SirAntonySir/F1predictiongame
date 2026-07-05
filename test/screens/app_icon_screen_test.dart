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

    // Helmet-only set: a single baked group (pose1 ids), so no pose section
    // headers at all, and each livery appears exactly once.
    final baked =
        AvatarPose.values.where((p) => p.hasBakedIcons).toList();
    expect(baked, hasLength(1));
    for (final pose in AvatarPose.values) {
      expect(find.text(pose.label.toUpperCase()), findsNothing);
    }
    for (final preset in avatarPresets) {
      expect(find.text(preset.name.toUpperCase()), findsOneWidget);
    }
  });

  testWidgets('tile picks stay draft until SAVE persists them',
      (tester) async {
    final c = await _controller();
    _tallViewport(tester);
    await tester.pumpWidget(_app(c));
    await tester.pump();

    expect(c.config.iconVariant, AvatarConfig.defaultIcon);
    expect(find.text('SAVE'), findsOneWidget);
    // Helmet-only set: each livery appears once. Tapping only stages the
    // choice — the controller still holds the saved default.
    await tester.tap(find.text('ROSSO'));
    await tester.pump();
    expect(c.config.iconVariant, AvatarConfig.defaultIcon);

    await tester.tap(find.text('BOLT'));
    await tester.pump();
    expect(c.config.iconVariant, AvatarConfig.defaultIcon);

    // The plugin channel is absent in tests; SAVE must still persist the
    // choice (and surface a toast) rather than throw.
    await tester.tap(find.text('SAVE'));
    await tester.pump(const Duration(seconds: 4));
    expect(c.config.iconVariant, 'pose1_bolt');
  });

  testWidgets('SAVE is inert while nothing is staged', (tester) async {
    final c = await _controller();
    _tallViewport(tester);
    await tester.pumpWidget(_app(c));
    await tester.pump();

    await tester.tap(find.text('SAVE'));
    await tester.pump(const Duration(seconds: 4));
    expect(c.config.iconVariant, AvatarConfig.defaultIcon);

    // Re-picking the already-saved tile keeps SAVE disabled too.
    final saved = avatarPresets
        .firstWhere((p) => AvatarConfig.defaultIcon == 'pose1_${p.id}');
    await tester.tap(find.text(saved.name.toUpperCase()));
    await tester.pump();
    await tester.tap(find.text('SAVE'));
    await tester.pump(const Duration(seconds: 4));
    expect(c.config.iconVariant, AvatarConfig.defaultIcon);
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
    await tester.pump();
    await tester.tap(find.text('SAVE'));
    await tester.pump(const Duration(seconds: 4));
    expect(c.config.iconVariant, 'pose1_rosso_light');

    await tester.tap(find.text('DARK'));
    await tester.pump();
    await tester.tap(find.text('ROSSO').first);
    await tester.pump();
    await tester.tap(find.text('SAVE'));
    await tester.pump(const Duration(seconds: 4));
    expect(c.config.iconVariant, 'pose1_rosso');
  });
}
