import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/avatar/avatar_config.dart';
import 'package:predictiongame/avatar/avatar_palette.dart';
import 'package:predictiongame/state/avatar_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AvatarConfig', () {
    test('json round-trip preserves preset, overrides, icon variant', () {
      const config = AvatarConfig(
        presetId: 'papaya',
        overrides: {AvatarRegion.helmet: Color(0xFF123456)},
        iconVariant: 'silver',
        pose: AvatarPose.pose2,
      );
      final back = AvatarConfig.fromJson(config.toJson());
      expect(back.presetId, 'papaya');
      expect(back.overrides, {AvatarRegion.helmet: const Color(0xFF123456)});
      // Legacy bare preset id migrates to its pose-1 variant.
      expect(back.iconVariant, 'pose1_silver');
      expect(back.pose, AvatarPose.pose2);
    });

    test('null, garbage, and unknown ids fall back to defaults', () {
      expect(AvatarConfig.fromJson(null).presetId, 'undercut');
      expect(AvatarConfig.fromJson(null).iconVariant, 'pose1_undercut');
      expect(AvatarConfig.fromJson('{not json').presetId, 'undercut');
      final unknown = AvatarConfig.fromJson(
          '{"preset":"gone","overrides":{"nope":1,"helmet":"red"},"icon":"x"}');
      expect(unknown.presetId, 'undercut');
      expect(unknown.overrides, isEmpty);
      expect(unknown.iconVariant, 'pose1_undercut');
      expect(unknown.pose, AvatarPose.pose1);
    });

    test('validIconVariant: pose-qualified, legacy, garbage', () {
      expect(AvatarConfig.validIconVariant('pose2_rosso'), 'pose1_undercut');
      expect(AvatarConfig.validIconVariant('rosso'), 'pose1_rosso'); // legacy
      // The retired 'classic' ticket icon migrates to the default.
      expect(AvatarConfig.validIconVariant('classic'), 'pose1_undercut');
      expect(AvatarConfig.validIconVariant('pose9_rosso'), 'pose1_undercut');
      expect(AvatarConfig.validIconVariant('pose1_nope'), 'pose1_undercut');
      expect(AvatarConfig.validIconVariant(null), 'pose1_undercut');
      // Helmet-only icon set: pose1_* ids (dark + light) are the baked
      // variants; saved pose2/pose3 selections migrate to the default.
      expect(AvatarConfig.validIconVariant('pose1_rosso_light'),
          'pose1_rosso_light');
      expect(AvatarConfig.validIconVariant('pose3_rosso'), 'pose1_undercut');
      expect(AvatarConfig.validIconVariant('pose2_rosso_light'),
          'pose1_undercut');
      expect(AvatarConfig.validIconVariant('pose1_nope_light'),
          'pose1_undercut');
      // Two variants (dark + light) per baked pose x livery.
      expect(AvatarConfig.iconVariants.length,
          AvatarPose.values.where((p) => p.hasBakedIcons).length *
              avatarPresets.length *
              2);
      expect(AvatarConfig.iconVariants, contains('pose1_undercut'));
      expect(AvatarConfig.iconVariants, isNot(contains('pose3_undercut')));
    });

    test('ops layer overrides on top of the preset', () {
      const config = AvatarConfig(
        presetId: 'rosso',
        overrides: {AvatarRegion.helmet: Color(0xFF0000FF)},
      );
      final helmetOp = config.ops[AvatarRegion.helmet]!;
      final applied = helmetOp.apply(const HSVColor.fromAHSV(1, 180, 0.9, 0.8));
      expect(applied.hue, closeTo(240, 1)); // picked blue, not rosso red
      // Untouched regions still come from the preset.
      expect(config.ops[AvatarRegion.chest], presetById('rosso').ops[AvatarRegion.chest]);
    });
  });

  group('AvatarController', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('load starts with defaults, persists changes across loads', () async {
      final c = await AvatarController.load();
      expect(c.config.presetId, 'undercut');

      await c.setPreset('silver');
      await c.setRegionColor(AvatarRegion.boots, const Color(0xFFAA0000));
      await c.setIconVariant('pose1_papaya');
      await c.setPose(AvatarPose.pose2);

      final again = await AvatarController.load();
      expect(again.config.presetId, 'silver');
      expect(again.config.overrides[AvatarRegion.boots],
          const Color(0xFFAA0000));
      expect(again.config.iconVariant, 'pose1_papaya');
      expect(again.config.pose, AvatarPose.pose2);
    });

    test('setPreset clears region overrides', () async {
      final c = await AvatarController.load();
      await c.setRegionColor(AvatarRegion.helmet, const Color(0xFF00FF00));
      expect(c.config.isCustom, isTrue);
      await c.setPreset('rosso');
      expect(c.config.isCustom, isFalse);
    });

    test('clearOverrides keeps preset and icon variant', () async {
      final c = await AvatarController.load();
      await c.setPreset('papaya');
      await c.setIconVariant('pose1_silver');
      await c.setRegionColor(AvatarRegion.legs, const Color(0xFF112233));
      await c.clearOverrides();
      expect(c.config.presetId, 'papaya');
      expect(c.config.iconVariant, 'pose1_silver');
      expect(c.config.overrides, isEmpty);
    });

    test('notifies listeners on every mutation', () async {
      final c = await AvatarController.load();
      var notified = 0;
      c.addListener(() => notified++);
      await c.setPreset('rosso');
      await c.setRegionColor(AvatarRegion.chest, const Color(0xFF445566));
      await c.clearOverrides();
      await c.setIconVariant('pose1_rosso');
      expect(notified, 4);
    });
  });
}
