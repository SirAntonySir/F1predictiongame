import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_parsing/path_parsing.dart';

import '../avatar/avatar_palette.dart';
import '../state/avatar_controller.dart';

/// Full-bleed boot splash that draws an SVG artwork like an artist:
/// every stroke sketches itself on in document order (SVG-Artista style
/// dash-offset draw), then the color fills fade in over the ink.
/// Plays ONCE and rests on the fully painted artwork while the app boots.
///
/// General-purpose: any flat-color SVG works (paths, rects, ellipses,
/// circles, polygons; translate/rotate/scale transforms; hex colors).
/// Not supported: gradients, text, CSS/class styling, nested group
/// attribute inheritance. The asset is parsed ONCE into ui.Path objects
/// + cached PathMetrics; per frame only progress values change.
class PaintedSplash extends StatefulWidget {
  /// When true, [onFinished] fires exactly once as soon as the artwork is
  /// fully painted (immediately if the one-shot animation already ended).
  final bool ready;
  final VoidCallback? onFinished;

  /// Explicit artwork asset. When null, the saved avatar config's pose is
  /// used — that's the boot-splash path.
  final String? asset;

  /// Explicit avatar recolor ops (the builder preview passes the config it
  /// is editing). When null, the saved on-device avatar config is loaded —
  /// that's the boot-splash path.
  final Map<AvatarRegion, RegionOp>? ops;

  /// One-shot play time. The boot splash keeps the leisurely default; the
  /// builder preview passes something snappier.
  final Duration duration;
  const PaintedSplash({
    super.key,
    this.ready = false,
    this.onFinished,
    this.asset,
    this.ops,
    this.duration = const Duration(milliseconds: 3000),
  });

  @override
  State<PaintedSplash> createState() => _PaintedSplashState();
}

class _PaintedSplashState extends State<PaintedSplash>
    with SingleTickerProviderStateMixin {
  // One-shot timeline (controller value 0..1): strokes sketch in, fills
  // wash over them, ends fully painted and stays there.
  static const _drawEnd = 0.55;
  static const _fillStart = 0.40;
  static const _fillEnd = 0.95;

  // Parsed rainbow masters, keyed by asset. Parsing is ~1.4k paths of
  // regex + path building; the builder preview re-renders on every color
  // tweak and must not pay that again.
  static final Map<String, SplashArt> _masterCache = {};

  late final AnimationController _controller;
  SplashArt? _master;
  SplashArt? _art;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: widget.duration);
    _controller.forward();
    if (widget.ready) _notifyWhenPainted();
    _loadArt();
  }

  Future<void> _loadArt() async {
    var asset = widget.asset;
    var ops = widget.ops;
    if (asset == null || ops == null) {
      final config = await AvatarController.loadConfig();
      asset ??= config.pose.asset;
      ops ??= config.ops;
    }
    var master = _masterCache[asset];
    if (master == null) {
      final text = await rootBundle.loadString(asset);
      master = _masterCache[asset] = SplashArt.parse(text);
    }
    if (!mounted) return;
    setState(() {
      _master = master;
      _art = recolorArt(master!, ops!);
    });
  }

  @override
  void didUpdateWidget(PaintedSplash old) {
    super.didUpdateWidget(old);
    if (widget.ready && !old.ready) _notifyWhenPainted();
    // Live recolor (builder color tweaks): remap colors on the cached
    // master, no reparse, no animation restart.
    if (widget.ops != null && widget.ops != old.ops && _master != null) {
      setState(() => _art = recolorArt(_master!, widget.ops!));
    }
  }

  /// Fire [PaintedSplash.onFinished] once the artwork is fully painted —
  /// immediately if the one-shot animation already ended.
  ///
  /// `.orCancel` is load-bearing: a bare TickerFuture never completes when
  /// its animation is interrupted, which would leave the splash stuck.
  Future<void> _notifyWhenPainted() async {
    if (!_controller.isCompleted) {
      try {
        await _controller.forward().orCancel;
      } on TickerCanceled {
        return; // disposed mid-flight — owner moved on.
      }
    }
    if (mounted) widget.onFinished?.call();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Map the one-shot timeline position to (strokeProgress, fillProgress).
  static (double, double) progressAt(double v) {
    final stroke = (v / _drawEnd).clamp(0.0, 1.0);
    final fill = ((v - _fillStart) / (_fillEnd - _fillStart)).clamp(0.0, 1.0);
    return (stroke, fill);
  }

  @override
  Widget build(BuildContext context) {
    final art = _art;
    if (art == null) return const SizedBox.expand();
    // Fit the FIGURE, not the SVG canvas: poses are traced with different
    // canvas sizes and margins, so containing the viewBox would place each
    // pose differently. The pose frame (figure height in a pose-1-shaped
    // box) makes figure HEIGHT the scale reference, so every pose renders
    // the character at the same size as pose 1.
    final frame = art.poseFrame;
    return SizedBox.expand(
      child: FittedBox(
        // Contain, not cover: the artwork has a transparent background, so
        // the whole figure fits on screen and the margins read as surface.
        fit: BoxFit.contain,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: frame.width,
          height: frame.height,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final (stroke, fill) = progressAt(_controller.value);
              return RepaintBoundary(
                child: CustomPaint(
                  size: frame.size,
                  isComplex: true,
                  painter: _ArtPainter(
                    art: art,
                    strokeProgress: stroke,
                    fillProgress: fill,
                    origin: frame.topLeft,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Test hooks: expose the timeline mapping and a direct paint of the parsed
/// artwork so tests can render review frames without a running widget.
@visibleForTesting
(double, double) splashProgressAt(double v) =>
    _PaintedSplashState.progressAt(v);

@visibleForTesting
void debugPaintSplashArt(
    Canvas canvas, SplashArt art, double stroke, double fill) {
  paintSplashArt(canvas, art);
}

/// Paint fully-drawn artwork in its raw SVG coordinate space. The caller sets
/// up any scale/translate on [canvas] first (e.g. to fit a crop). Used to
/// rasterize static avatar thumbnails; the animated splash uses [_ArtPainter]
/// directly with progress values.
void paintSplashArt(Canvas canvas, SplashArt art) {
  _ArtPainter(art: art, strokeProgress: 1, fillProgress: 1)
      .paint(canvas, Size(art.width, art.height));
}

class _ArtPainter extends CustomPainter {
  final SplashArt art;
  final double strokeProgress;
  final double fillProgress;

  /// Point in SVG coordinates painted at the widget's top-left — the
  /// content-bounds origin for figure-fit framing. Zero keeps raw SVG
  /// coordinates (icon baking relies on that).
  final Offset origin;
  _ArtPainter({
    required this.art,
    required this.strokeProgress,
    required this.fillProgress,
    this.origin = Offset.zero,
  });

  // Per-element stagger: element i is active during a sliding window of the
  // phase, so early elements finish while late ones are still starting.
  static double _stagger(double p, int i, int n, double window) {
    final start = n <= 1 ? 0.0 : (i / (n - 1)) * (1 - window);
    return ((p - start) / window).clamp(0.0, 1.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(-origin.dx, -origin.dy);
    // 1. Strokes sketch on (document order = artist's ink pass).
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.butt;
    final ns = art.strokes.length;
    for (var i = 0; i < ns; i++) {
      final s = art.strokes[i];
      final local = _stagger(strokeProgress, i, ns, 0.22);
      if (local <= 0) continue;
      strokePaint
        ..color = s.color
        ..strokeWidth = s.width;
      if (local >= 1) {
        canvas.drawPath(s.path, strokePaint);
      } else {
        var remaining = s.length * local;
        for (final m in s.metrics) {
          if (remaining <= 0) break;
          final take = remaining.clamp(0.0, m.length);
          canvas.drawPath(m.extractPath(0, take), strokePaint);
          remaining -= m.length;
        }
      }
    }

    // 2. Color fills wash in over the ink (document order = z-order).
    final fillPaint = Paint()..style = PaintingStyle.fill;
    final nf = art.fills.length;
    for (var i = 0; i < nf; i++) {
      final f = art.fills[i];
      final local = _stagger(fillProgress, i, nf, 0.30);
      if (local <= 0) continue;
      fillPaint.color = f.color.withValues(alpha: local);
      canvas.drawPath(f.path, fillPaint);
    }
  }

  @override
  bool shouldRepaint(_ArtPainter old) =>
      old.art != art ||
      old.strokeProgress != strokeProgress ||
      old.fillProgress != fillProgress ||
      old.origin != origin;
}

/// A parsed SVG artwork: strokes (with cached metrics for partial drawing)
/// and color fills, both in document order, plus the viewBox size.
class SplashArt {
  final double width;
  final double height;
  final List<StrokeElement> strokes;
  final List<FillElement> fills;
  SplashArt({
    required this.width,
    required this.height,
    required this.strokes,
    required this.fills,
  });

  /// Tight bounding box of the drawn content (figure + shadow), padded for
  /// stroke width. Trace canvases carry arbitrary margins per pose; framing
  /// against this box gives every pose the same on-screen placement.
  late final Rect contentBounds = () {
    Rect? union;
    void add(Rect r) => union = union?.expandToInclude(r) ?? r;
    for (final s in strokes) {
      add(s.path.getBounds());
    }
    for (final f in fills) {
      add(f.path.getBounds());
    }
    return union?.inflate(4) ?? Rect.fromLTWH(0, 0, width, height);
  }();

  /// Pose 1 (Victory)'s figure aspect ratio — the framing reference every
  /// pose is normalized to. Guarded by a test against the shipped asset;
  /// update if pose1.svg is ever regenerated with different framing.
  static const referenceFigureAspect = 1443 / 2125;

  /// The rect the renderer fits on screen: this pose's figure height in a
  /// pose-1-shaped frame, centered on the figure. Height is the scale
  /// reference — every pose's frame has the same aspect, so `contain`
  /// always resolves to the same figure height regardless of how wide a
  /// pose is (arms up vs arms crossed). Poses narrower than pose 1 get
  /// symmetric side margins instead of being blown up to fill the width.
  /// A pose WIDER than pose 1 would clip — regenerate such an asset to the
  /// reference framing instead.
  late final Rect poseFrame = Rect.fromCenter(
    center: contentBounds.center,
    width: contentBounds.height * referenceFigureAspect,
    height: contentBounds.height,
  );

  /// Per-element vertical center in SVG coords (fills, then strokes — same
  /// order the paint loop and [recolorArt] iterate). Cached once on the parsed
  /// master so position-aware recoloring doesn't re-measure bounds on every
  /// live color tweak.
  late final List<double> fillCentersY =
      [for (final f in fills) f.path.getBounds().center.dy];
  late final List<double> strokeCentersY =
      [for (final s in strokes) s.path.getBounds().center.dy];

  static final _viewBoxRe =
      RegExp(r'viewBox="\s*[\d.+-]+\s+[\d.+-]+\s+([\d.+-]+)\s+([\d.+-]+)\s*"');
  static final _groupStrokeWidthRe = RegExp(r'<g\b[^>]*stroke-width="([\d.]+)"');
  static final _elementRe = RegExp(
      r'<(path|rect|ellipse|circle|polygon|polyline)\b([^>]*?)/>',
      dotAll: true);
  static final _attrRe = RegExp(r'([\w-]+)="([^"]*)"', dotAll: true);
  static final _translateRe =
      RegExp(r'translate\(\s*(-?[\d.]+)[\s,]+(-?[\d.]+)\s*\)');
  static final _rotateRe = RegExp(r'rotate\(\s*(-?[\d.]+)\s*\)');
  static final _scaleRe = RegExp(r'scale\(\s*(-?[\d.]+)(?:[\s,]+(-?[\d.]+))?\s*\)');

  static SplashArt parse(String svg) {
    final vb = _viewBoxRe.firstMatch(svg);
    final width = vb == null ? 100.0 : double.parse(vb.group(1)!);
    final height = vb == null ? 100.0 : double.parse(vb.group(2)!);

    // Group-level stroke width (trace SVGs set it once on the stroke group);
    // element-level stroke-width attributes override it.
    final gw = _groupStrokeWidthRe.firstMatch(svg);
    final groupStrokeWidth = gw == null ? 1.0 : double.parse(gw.group(1)!);

    final strokes = <StrokeElement>[];
    final fills = <FillElement>[];

    for (final m in _elementRe.allMatches(svg)) {
      final tag = m.group(1)!;
      final attrs = <String, String>{
        for (final a in _attrRe.allMatches(m.group(2)!))
          a.group(1)!: a.group(2)!
      };

      Path? path;
      switch (tag) {
        case 'path':
          final d = attrs['d'];
          if (d == null) continue;
          path = _parsePathData(d);
        case 'rect':
          final x = _num(attrs['x']), y = _num(attrs['y']);
          final w = _num(attrs['width']), h = _num(attrs['height']);
          final rx = _num(attrs['rx']);
          path = Path()
            ..addRRect(RRect.fromRectAndRadius(
                Rect.fromLTWH(x, y, w, h), Radius.circular(rx)));
        case 'ellipse' || 'circle':
          final cx = _num(attrs['cx']), cy = _num(attrs['cy']);
          final r = _num(attrs['r']);
          final rx = attrs.containsKey('rx') ? _num(attrs['rx']) : r;
          final ry = attrs.containsKey('ry') ? _num(attrs['ry']) : r;
          path = Path()
            ..addOval(Rect.fromCenter(
                center: Offset(cx, cy), width: rx * 2, height: ry * 2));
        case 'polygon' || 'polyline':
          path = _parsePoints(attrs['points'], close: tag == 'polygon');
      }
      if (path == null) continue;

      final t = attrs['transform'];
      if (t != null) path = path.transform(_matrixFor(t).storage);

      final strokeColor = _color(attrs['stroke']);
      final fillColor = _color(attrs['fill']);
      if (strokeColor != null) {
        final metrics = path.computeMetrics().toList();
        strokes.add(StrokeElement(
          path: path,
          color: strokeColor,
          width: attrs.containsKey('stroke-width')
              ? _num(attrs['stroke-width'])
              : groupStrokeWidth,
          metrics: metrics,
          length: metrics.fold(0.0, (sum, pm) => sum + pm.length),
        ));
      } else if (fillColor != null) {
        fills.add(FillElement(path: path, color: fillColor));
      }
    }
    return SplashArt(
        width: width, height: height, strokes: strokes, fills: fills);
  }

  static double _num(String? s) => s == null ? 0 : double.parse(s);

  /// Hex colors only (#rgb and #rrggbb); returns null for none/absent/other.
  static Color? _color(String? s) {
    if (s == null || s == 'none' || !s.startsWith('#')) return null;
    var hex = s.substring(1);
    if (hex.length == 3) {
      hex = hex.split('').map((c) => '$c$c').join();
    }
    if (hex.length != 6) return null;
    return Color(0xFF000000 | int.parse(hex, radix: 16));
  }

  static Matrix4 _matrixFor(String transform) {
    final tr = _translateRe.firstMatch(transform);
    final matrix = tr == null
        ? Matrix4.identity()
        : Matrix4.translationValues(
            double.parse(tr.group(1)!), double.parse(tr.group(2)!), 0);
    final rot = _rotateRe.firstMatch(transform);
    if (rot != null) {
      matrix.rotateZ(double.parse(rot.group(1)!) * math.pi / 180);
    }
    final sc = _scaleRe.firstMatch(transform);
    if (sc != null) {
      final sx = double.parse(sc.group(1)!);
      final sy = sc.group(2) == null ? sx : double.parse(sc.group(2)!);
      matrix.scaleByDouble(sx, sy, 1, 1);
    }
    return matrix;
  }

  static Path? _parsePoints(String? points, {required bool close}) {
    if (points == null) return null;
    final nums = points
        .trim()
        .split(RegExp(r'[\s,]+'))
        .map(double.parse)
        .toList();
    if (nums.length < 4) return null;
    final path = Path()..moveTo(nums[0], nums[1]);
    for (var i = 2; i + 1 < nums.length; i += 2) {
      path.lineTo(nums[i], nums[i + 1]);
    }
    if (close) path.close();
    return path;
  }

  static Path _parsePathData(String d) {
    final proxy = _UiPathProxy();
    writeSvgPathDataToPath(d, proxy);
    return proxy.path;
  }
}

class StrokeElement {
  final Path path;
  final Color color;
  final double width;
  final List<ui.PathMetric> metrics;
  final double length;
  StrokeElement({
    required this.path,
    required this.color,
    required this.width,
    required this.metrics,
    required this.length,
  });
}

class FillElement {
  final Path path;
  final Color color;
  FillElement({required this.path, required this.color});
}

/// Bridges package:path_parsing's callback API onto a dart:ui Path.
class _UiPathProxy implements PathProxy {
  final Path path = Path();
  @override
  void close() => path.close();
  @override
  void cubicTo(double x1, double y1, double x2, double y2, double x3, double y3) =>
      path.cubicTo(x1, y1, x2, y2, x3, y3);
  @override
  void lineTo(double x, double y) => path.lineTo(x, y);
  @override
  void moveTo(double x, double y) => path.moveTo(x, y);
}
