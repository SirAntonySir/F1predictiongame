import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/avatar/avatar_config.dart';
import 'package:predictiongame/avatar/avatar_palette.dart';
import 'package:predictiongame/avatar/avatar_render.dart';
import 'package:predictiongame/components/painted_splash.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('headCropOf', () {
    test('frames a sane square near the top of each pose', () {
      for (final pose in AvatarPose.values) {
        final master = SplashArt.parse(File(pose.asset).readAsStringSync());
        final crop = headCropOf(master);
        // Square.
        expect(crop.width, closeTo(crop.height, 0.001),
            reason: '${pose.name} crop should be square');
        // Anchored on the helmet, so the crop's height is a fraction of the
        // full figure — never the whole thing (the union-of-all-teal bug).
        expect(crop.height, lessThan(master.height * 0.75),
            reason: '${pose.name} crop should be head-sized, not full-figure');
        // Sits in the upper half of the figure.
        expect(crop.center.dy, lessThan(master.height * 0.6),
            reason: '${pose.name} head should be up top');
      }
    });
  });

  group('AvatarRenderer', () {
    testWidgets('headThumbnail renders and caches by (pose, config, size)',
        (tester) async {
      await tester.runAsync(() async {
        const cfg = AvatarConfig(presetId: 'bolt', pose: AvatarPose.pose1);
        final a = await AvatarRenderer.instance.headThumbnail(cfg, 48);
        expect(a.width, 48);
        expect(a.height, 48);
        // Same key → same cached image instance.
        final b = await AvatarRenderer.instance.headThumbnail(cfg, 48);
        expect(identical(a, b), isTrue);
        // Different size → different image.
        final c = await AvatarRenderer.instance.headThumbnail(cfg, 64);
        expect(identical(a, c), isFalse);
        expect(c.width, 64);
      });
    });

    testWidgets('a null/default config still renders', (tester) async {
      await tester.runAsync(() async {
        final cfg = AvatarConfig.fromJson(null);
        final img = await AvatarRenderer.instance.headThumbnail(cfg, 32);
        expect(img.width, 32);
      });
    });
  });
}
