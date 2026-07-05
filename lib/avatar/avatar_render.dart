import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../components/painted_splash.dart';
import 'avatar_config.dart';
import 'avatar_palette.dart';

/// Renders avatar configs to cached raster head-crops for profile/leaderboard
/// thumbnails. The full recolor engine runs client-side; this memoizes the
/// expensive parts (SVG parse, per-config raster) so a leaderboard of many
/// small avatars stays cheap — each row blits a cached [ui.Image] instead of
/// repainting thousands of paths every frame.
class AvatarRenderer {
  AvatarRenderer._();
  static final instance = AvatarRenderer._();

  // Parsed master art per pose asset (parse once, not per widget).
  final _artByPose = <String, SplashArt>{};
  final _artFutures = <String, Future<SplashArt>>{};
  // Crop rect in SVG coords, per pose asset, per crop style.
  final _cropByPose = <String, Rect>{};

  // Rendered head-crop images, keyed by (pose, configJson, sizePx). Soft-capped
  // LRU — a league has few members × few sizes, so this stays tiny.
  static const _maxImages = 128;
  final _images = <String, ui.Image>{};
  final _imageFutures = <String, Future<ui.Image>>{};

  Future<SplashArt> _artForPose(AvatarPose pose) {
    final cached = _artByPose[pose.asset];
    if (cached != null) return Future.value(cached);
    return _artFutures.putIfAbsent(pose.asset, () async {
      final svg = await rootBundle.loadString(pose.asset);
      final art = SplashArt.parse(svg);
      _artByPose[pose.asset] = art;
      _artFutures.remove(pose.asset);
      return art;
    });
  }

  /// Crop rect (SVG coords) for a pose + style. The tight [head] shot is
  /// anchored on the helmet; [bust] spans the figure's full width (raised arm
  /// never clipped); [bustTall] keeps that width but extends further down the
  /// body. All derive from the master art, whose geometry is shared with the
  /// recolored art.
  Rect _cropForPose(AvatarPose pose, SplashArt master, AvatarCrop crop) {
    return _cropByPose.putIfAbsent('${pose.asset}|${crop.name}', () {
      switch (crop) {
        case AvatarCrop.head:
          return headCropOf(master);
        case AvatarCrop.bust:
          return bustCropOf(master);
        case AvatarCrop.bustTall:
          return bustCropOf(master, heightFactor: 1.35);
      }
    });
  }

  /// Cropped avatar [ui.Image] for [config] at [sizePx] (image width; height
  /// follows the crop's aspect, so taller crops yield taller images).
  /// Transparent background (the widget supplies any disc/gradient behind it).
  Future<ui.Image> headThumbnail(AvatarConfig config, int sizePx,
      {AvatarCrop crop = AvatarCrop.head}) {
    final key = '${config.pose.name}|${crop.name}|${config.toJson()}|$sizePx';
    final cached = _images[key];
    if (cached != null) return Future.value(cached);
    return _imageFutures.putIfAbsent(key, () async {
      final master = await _artForPose(config.pose);
      final cropRect = _cropForPose(config.pose, master, crop);
      final recolored = recolorArt(master, config.ops);

      final scale = sizePx / cropRect.width;
      final heightPx = (cropRect.height * scale).round();
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec);
      canvas.scale(scale);
      canvas.translate(-cropRect.left, -cropRect.top);
      paintSplashArt(canvas, recolored);
      final img = await rec.endRecording().toImage(sizePx, heightPx);

      _imageFutures.remove(key);
      _images[key] = img;
      if (_images.length > _maxImages) {
        final oldest = _images.keys.first;
        _images.remove(oldest)?.dispose();
      }
      return img;
    });
  }
}

/// The crop framings [AvatarRenderer] can produce.
enum AvatarCrop { head, bust, bustTall }

/// Tunables for the tight head crop, derived from the helmet shell. Public so
/// a test can assert the framing stays sane if a pose SVG is regenerated.
const double headCropScale = 2.4; // square side = helmet-shell height × this
const double headCropTopPad = 0.2; // lift the top above the shell by ×height

/// Square crop (SVG coords) anchored on the helmet **shell** — the single
/// largest teal fill. Anchoring on the biggest fill (not the union of all
/// helmet-classified fills) rejects stray teal shading scattered down the
/// figure (boots, gloves shadow), which otherwise balloons the box. [scale]
/// sets the square side as a multiple of the shell height; [topPad] lifts the
/// top edge above the shell (also ×height). Falls back to the top of the pose
/// frame if no helmet is found.
Rect helmetCropOf(SplashArt master,
    {double scale = headCropScale, double topPad = headCropTopPad}) {
  Rect? shell;
  double shellArea = 0;
  for (final f in master.fills) {
    if (classifyMasterColor(HSVColor.fromColor(f.color)) ==
        AvatarRegion.helmet) {
      final b = f.path.getBounds();
      final area = b.width * b.height;
      if (area > shellArea) {
        shellArea = area;
        shell = b;
      }
    }
  }

  final h = shell;
  if (h == null) {
    // No teal helmet in the master — frame the top of the figure instead.
    final f = master.poseFrame;
    return Rect.fromLTWH(f.left, f.top, f.width, f.width);
  }
  final side = h.height * scale;
  final top = h.top - h.height * topPad;
  return Rect.fromLTWH(h.center.dx - side / 2, top, side, side);
}

/// Back-compat alias used by tests: the default (head) framing.
Rect headCropOf(SplashArt master) => helmetCropOf(master);

/// Head + shoulders + torso + arms crop (app-icon framing). As wide as the
/// figure's content bounds, top-anchored — so the raised arm, which defines
/// that width, is always included. Height defaults to a square ([heightFactor]
/// = 1.0); a larger factor extends the crop further down the body (less of the
/// figure cut off) while keeping the same top and width.
Rect bustCropOf(SplashArt master, {double heightFactor = 1.0}) {
  final b = master.contentBounds;
  final side = b.width;
  final top = b.top - b.height * 0.02; // slight headroom
  return Rect.fromLTWH(
      b.center.dx - side / 2, top, side, side * heightFactor);
}
