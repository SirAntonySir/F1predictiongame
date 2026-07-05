import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../avatar/avatar_config.dart';
import '../avatar/avatar_palette.dart';
import '../avatar/avatar_render.dart';
import '../theme/app_theme.dart';

/// A large app-icon-style bust (head + shoulders + upper torso) rendered from
/// an [AvatarConfig] JSON. Fills its parent — the figure is contained and
/// centered, so the full upper body is always visible — with an optional
/// gradient fade toward the bottom. Used behind the profile standing card and
/// centered in the leaderboard podium steps.
class AvatarBust extends StatefulWidget {
  final String? configJson;

  /// Fade the figure out toward the bottom (so overlaid stats stay readable).
  final bool bottomFade;

  /// Framing: [AvatarCrop.bust] (head→mid-torso square) or [AvatarCrop.bustTall]
  /// (extends further down the body, so less of the figure is cut off — used
  /// for the P1 podium step).
  final AvatarCrop crop;

  /// Logical raster width; the image is cached by (pose, config, crop, sizePx).
  final double resolution;

  /// When set, render this pose instead of the one saved in [configJson]
  /// (the livery/colors still come from the config). The podium forces the
  /// crossed-arms pose so all three steps read as a matched set.
  final AvatarPose? forcePose;

  /// Mirror the figure left-to-right (horizontal flip). Does not affect the
  /// vertical bottom-fade gradient.
  final bool mirror;
  const AvatarBust({
    super.key,
    required this.configJson,
    this.bottomFade = true,
    this.crop = AvatarCrop.bust,
    this.resolution = 300,
    this.forcePose,
    this.mirror = false,
  });

  @override
  State<AvatarBust> createState() => _AvatarBustState();
}

class _AvatarBustState extends State<AvatarBust> {
  ui.Image? _image;
  int _sizePx = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(AvatarBust old) {
    super.didUpdateWidget(old);
    if (old.configJson != widget.configJson ||
        old.resolution != widget.resolution ||
        old.forcePose != widget.forcePose ||
        old.crop != widget.crop) {
      _image = null;
      _sizePx = 0;
      _resolve();
    }
  }

  void _resolve() {
    final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1.0;
    final sizePx = (widget.resolution * dpr).round().clamp(1, 1024);
    if (sizePx == _sizePx && _image != null) return;
    _sizePx = sizePx;
    var config = AvatarConfig.fromJson(widget.configJson);
    if (widget.forcePose != null) {
      config = config.copyWith(pose: widget.forcePose);
    }
    AvatarRenderer.instance
        .headThumbnail(config, sizePx, crop: widget.crop)
        .then((img) {
      if (mounted && _sizePx == sizePx) setState(() => _image = img);
    });
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) return const SizedBox.shrink();
    Widget img = RawImage(image: image, fit: BoxFit.contain);
    if (widget.bottomFade) {
      img = ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white, Colors.white, Colors.transparent],
          stops: [0.0, 0.6, 1.0],
        ).createShader(rect),
        child: img,
      );
    }
    if (widget.mirror) {
      img = Transform.flip(flipX: true, child: img);
    }
    return IgnorePointer(child: img);
  }
}

/// Circular head-crop of a user's avatar, rendered from their [AvatarConfig]
/// JSON. A null/blank config renders the default livery (matching
/// `AvatarConfig.fromJson(null)`), so every row shows an avatar. The rendered
/// figure is cached by [AvatarRenderer]; this widget just resolves the image
/// and paints it over a themed disc.
class AvatarThumbnail extends StatefulWidget {
  final String? configJson;
  final double size;

  /// When true, paint a themed disc + border behind the head-crop. When false,
  /// render the figure alone on a transparent background (a floating bust).
  final bool background;
  const AvatarThumbnail({
    super.key,
    required this.configJson,
    this.size = 32,
    this.background = true,
  });

  @override
  State<AvatarThumbnail> createState() => _AvatarThumbnailState();
}

class _AvatarThumbnailState extends State<AvatarThumbnail> {
  ui.Image? _image;
  int _sizePx = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(AvatarThumbnail old) {
    super.didUpdateWidget(old);
    if (old.configJson != widget.configJson || old.size != widget.size) {
      _resolve();
    }
  }

  void _resolve() {
    final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1.0;
    final sizePx = (widget.size * dpr).round().clamp(1, 1024);
    if (sizePx == _sizePx && _image != null) return;
    _sizePx = sizePx;
    final config = AvatarConfig.fromJson(widget.configJson);
    // Cheap on cache hit (returns a completed future). On first resolve we
    // hold the placeholder disc until the raster is ready.
    AvatarRenderer.instance.headThumbnail(config, sizePx).then((img) {
      if (mounted && _sizePx == sizePx) setState(() => _image = img);
    });
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (!widget.background) {
      // Transparent bust — the figure alone, no disc or border.
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: image == null ? null : RawImage(image: image, fit: BoxFit.contain),
      );
    }
    final t = Theme.of(context);
    final bg = Color.alphaBlend(
        t.colorScheme.onSurface.withValues(alpha: 0.06), t.colorScheme.surface);
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: Border.all(color: t.strokeColor, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: image == null ? null : RawImage(image: image, fit: BoxFit.cover),
    );
  }
}
