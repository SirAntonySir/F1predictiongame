import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/avatar/avatar_palette.dart';
import 'package:predictiongame/components/painted_splash.dart';

/// Launcher-icon bake pipeline. Skipped in normal test runs; execute with:
///
///   flutter test test/tools/bake_icons_test.dart --dart-define=BAKE=true
///
/// For every pose × livery it renders the upper-body crop on the dark
/// (#2E2C31, variant id `poseN_livery`) and light (ticket cream #EFEAE0,
/// variant id `poseN_livery_light`) backgrounds and writes every platform
/// copy in place:
///
///   assets/avatar/icons/{id}.png            120px  (gallery preview)
///   ios/Runner/{id}@2x.png                  120px  (+ @3x 180px)
///   android .../mipmap-*/ic_launcher_{id}.png  48/72/96/144/192px
///
/// New variants still need native registration (Info.plist, project.pbxproj,
/// AndroidManifest activity-alias) — the bake only writes pixels.
const _bake = bool.fromEnvironment('BAKE');

const _darkBg = Color(0xFF2E2C31);

/// Ticket paper cream (ticket_capture.dart `_paper`) — the light-mode set.
const _lightBg = Color(0xFFEFEAE0);

/// Upper-body crop square per pose, in that pose's SVG coordinates.
/// Pose 1 is the original bake square (AvatarConfig doc comment) — the
/// primary app icon was baked with it, so it must not drift. Pose 2/3 were
/// derived from the same figure-relative proportions, then tuned by eye on
/// the rendered result.
const _crops = {
  AvatarPose.pose1: Rect.fromLTWH(130.4, -85.2, 1199.4, 1199.4),
  AvatarPose.pose2: Rect.fromLTWH(-191.5, -101.2, 1271.0, 1271.0),
  AvatarPose.pose3: Rect.fromLTWH(360.0, 290.0, 982.0, 982.0),
};

const _sizes = {
  'assets/avatar/icons/{id}.png': 120,
  'ios/Runner/{id}@2x.png': 120,
  'ios/Runner/{id}@3x.png': 180,
  'android/app/src/main/res/mipmap-mdpi/ic_launcher_{id}.png': 48,
  'android/app/src/main/res/mipmap-hdpi/ic_launcher_{id}.png': 72,
  'android/app/src/main/res/mipmap-xhdpi/ic_launcher_{id}.png': 96,
  'android/app/src/main/res/mipmap-xxhdpi/ic_launcher_{id}.png': 144,
  'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_{id}.png': 192,
};

Future<void> _writeIcon(
    SplashArt art, Rect crop, Color bg, String id) async {
  for (final entry in _sizes.entries) {
    final size = entry.value;
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    canvas.drawRect(
        Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
        Paint()..color = bg);
    canvas
      ..clipRect(Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()))
      ..scale(size / crop.width)
      ..translate(-crop.left, -crop.top);
    debugPaintSplashArt(canvas, art, 1.0, 1.0);
    final img = await rec.endRecording().toImage(size, size);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    File(entry.key.replaceAll('{id}', id))
        .writeAsBytesSync(bytes!.buffer.asUint8List());
  }
}

void main() {
  testWidgets('bake launcher icons for every pose × livery × background',
      (tester) async {
    for (final pose in AvatarPose.values) {
      final text =
          await tester.runAsync(() => rootBundle.loadString(pose.asset));
      final master = SplashArt.parse(text!);
      final crop = _crops[pose]!;
      await tester.runAsync(() async {
        for (final preset in avatarPresets) {
          final art = recolorArt(master, preset.ops);
          final id = '${pose.name}_${preset.id}';
          await _writeIcon(art, crop, _darkBg, id);
          await _writeIcon(art, crop, _lightBg, '${id}_light');
        }
      });
      // ignore: avoid_print
      print('baked ${pose.name}: crop=$crop');
    }
  }, skip: !_bake);
}
