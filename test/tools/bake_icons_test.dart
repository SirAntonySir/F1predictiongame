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
/// The icon art is the standalone HELMET master (assets/avatar/helmet.svg) —
/// helmets read far better at launcher size than the full-figure poses, so
/// the gallery offers one helmet per livery (× dark/light background). The
/// 24 variants reuse the already-registered `pose1_*` ids, so no native
/// re-registration is needed; pose 2/3 ids stay registered but unbaked and
/// hidden from the gallery (AvatarPose.hasBakedIcons).
///
/// Per variant id, every platform copy is written in place:
///
///   assets/avatar/icons/{id}.png            120px  (gallery preview)
///   ios/Runner/{id}@2x.png                  120px  (+ @3x 180px)
///   android .../mipmap-*/ic_launcher_{id}.png  48/72/96/144/192px
///
/// plus the PRIMARY app icon (all AppIcon.appiconset sizes + ic_launcher)
/// from the Undercut helmet.
const _bake = bool.fromEnvironment('BAKE');

const _darkBg = Color(0xFF2E2C31);

/// Ticket paper cream (ticket_capture.dart `_paper`) — the light-mode set.
const _lightBg = Color(0xFFEFEAE0);

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
  // iPad alternate-icon files (App Store validation 90892): 76pt@2x = 152px
  // under the plain id, 83.5pt@2x = 167px under the "-83.5" twin id that the
  // CFBundleIcons~ipad section lists alongside it.
  await _writePng(art, crop, bg, 'ios/Runner/$id@2x~ipad.png', 152);
  await _writePng(art, crop, bg, 'ios/Runner/$id-83.5@2x~ipad.png', 167);
}

/// Primary launcher icon targets: every AppIcon.appiconset size (iOS) and the
/// ic_launcher mipmaps (Android). Baked from the standalone helmet master in
/// the Undercut livery — the brand icon.
const _primarySizes = {
  'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png': 1024,
  'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@1x.png': 20,
  'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@2x.png': 40,
  'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@3x.png': 60,
  'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@1x.png': 29,
  'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@2x.png': 58,
  'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@3x.png': 87,
  'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@1x.png': 40,
  'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@2x.png': 80,
  'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@3x.png': 120,
  'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@2x.png': 120,
  'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@3x.png': 180,
  'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@1x.png': 76,
  'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@2x.png': 152,
  'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-83.5x83.5@2x.png': 167,
  'android/app/src/main/res/mipmap-mdpi/ic_launcher.png': 48,
  'android/app/src/main/res/mipmap-hdpi/ic_launcher.png': 72,
  'android/app/src/main/res/mipmap-xhdpi/ic_launcher.png': 96,
  'android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png': 144,
  'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png': 192,
};

Future<void> _writePng(
    SplashArt art, Rect crop, Color bg, String path, int size) async {
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
  File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
}

void main() {
  testWidgets('bake helmet launcher icons (livery × background) + primary',
      (tester) async {
    final text = await tester
        .runAsync(() => rootBundle.loadString('assets/avatar/helmet.svg'));
    final helmet = SplashArt.parse(text!);
    final b = helmet.contentBounds;
    // Padding factor: the square crop is the helmet's long side × this, so the
    // helmet fills 1/factor of the frame (1.35 ≈ 74%, leaving a margin around
    // the shell rather than bleeding to the icon edge).
    final side = (b.width > b.height ? b.width : b.height) * 1.35;
    final crop = Rect.fromCenter(center: b.center, width: side, height: side);

    await tester.runAsync(() async {
      // Gallery variants: one helmet per livery, dark + light. Reuses the
      // pose1_* ids so the existing native registrations keep working.
      for (final preset in avatarPresets) {
        final art =
            recolorArt(helmet, preset.ops, positionalRules: false);
        final id = 'pose1_${preset.id}';
        await _writeIcon(art, crop, _darkBg, id);
        await _writeIcon(art, crop, _lightBg, '${id}_light');
      }
      // Primary app icon: the Undercut helmet. Shares the pose1_undercut art
      // above, so "reset to default" previews exactly what the primary shows
      // — AvatarConfig.defaultIcon relies on that identity.
      final art =
          recolorArt(helmet, presetById('undercut').ops, positionalRules: false);
      for (final entry in _primarySizes.entries) {
        await _writePng(art, crop, _darkBg, entry.key, entry.value);
      }
    });
    // ignore: avoid_print
    print('baked ${avatarPresets.length}×2 helmet variants + primary: crop=$crop');
  }, skip: !_bake);
}
