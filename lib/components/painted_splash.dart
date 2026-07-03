import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_parsing/path_parsing.dart';

/// Full-bleed boot splash that draws an SVG artwork like an artist:
/// every stroke sketches itself on in document order (SVG-Artista style
/// dash-offset draw), then the color fills fade in over the ink.
/// The loop erases in reverse and repeats while the app boots.
///
/// General-purpose: any flat-color SVG works (paths, rects, ellipses,
/// circles, polygons; translate/rotate/scale transforms; hex colors).
/// Not supported: gradients, text, CSS/class styling, nested group
/// attribute inheritance. The asset is parsed ONCE into ui.Path objects
/// + cached PathMetrics; per frame only progress values change.
class PaintedSplash extends StatefulWidget {
  /// When true, the loop stops repeating: the animation plays to the fully
  /// painted artwork and [onFinished] fires exactly once.
  final bool ready;
  final VoidCallback? onFinished;
  final String asset;
  const PaintedSplash({
    super.key,
    this.ready = false,
    this.onFinished,
    this.asset = 'assets/loading/loading.svg',
  });

  @override
  State<PaintedSplash> createState() => _PaintedSplashState();
}

class _PaintedSplashState extends State<PaintedSplash>
    with SingleTickerProviderStateMixin {
  static const _cycleMs = 4000;

  // Timeline within one cycle (controller value 0..1):
  // strokes sketch in, fills wash over them, hold, erase in reverse.
  static const _drawEnd = 0.42;
  static const _fillStart = 0.30;
  static const _fillEnd = 0.70;
  static const _eraseStart = 0.82;
  // Fully painted moment the handoff finishes on (middle of the hold).
  static const _holdMid = 0.76;

  late final AnimationController _controller;
  SplashArt? _art;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: _cycleMs));
    if (widget.ready) {
      _finishAtFullArt();
    } else {
      _controller.repeat();
    }
    _loadArt();
  }

  Future<void> _loadArt() async {
    final text = await rootBundle.loadString(widget.asset);
    final art = SplashArt.parse(text);
    if (mounted) setState(() => _art = art);
  }

  @override
  void didUpdateWidget(PaintedSplash old) {
    super.didUpdateWidget(old);
    if (widget.ready && !old.ready) _finishAtFullArt();
  }

  Duration _scaled(double delta) => Duration(
      milliseconds: (delta.abs() * _cycleMs).round().clamp(1, _cycleMs));

  /// Play on to the fully painted artwork at loop speed, then notify.
  /// If mid-erase, finish the erase and paint once more — the splash always
  /// exits on the complete artwork, never a half-drawn frame.
  ///
  /// `.orCancel` is load-bearing: a bare TickerFuture never completes when
  /// its animation is interrupted, which would leave the splash stuck.
  Future<void> _finishAtFullArt() async {
    _controller.stop();
    try {
      if (_controller.value > _holdMid) {
        await _controller
            .animateTo(1.0, duration: _scaled(1.0 - _controller.value))
            .orCancel;
        _controller.value = 0.0;
      }
      await _controller
          .animateTo(_holdMid, duration: _scaled(_holdMid - _controller.value))
          .orCancel;
    } on TickerCanceled {
      return; // disposed (or superseded) mid-flight — owner moved on.
    }
    if (mounted) widget.onFinished?.call();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Map the cycle position to (strokeProgress, fillProgress).
  static (double, double) progressAt(double v) {
    if (v >= _eraseStart) {
      final e = ((v - _eraseStart) / (1 - _eraseStart)).clamp(0.0, 1.0);
      return (1 - e, 1 - e);
    }
    final stroke = (v / _drawEnd).clamp(0.0, 1.0);
    final fill = ((v - _fillStart) / (_fillEnd - _fillStart)).clamp(0.0, 1.0);
    return (stroke, fill);
  }

  @override
  Widget build(BuildContext context) {
    final art = _art;
    if (art == null) return const SizedBox.expand();
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: art.width,
          height: art.height,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final (stroke, fill) = progressAt(_controller.value);
              return RepaintBoundary(
                child: CustomPaint(
                  size: Size(art.width, art.height),
                  isComplex: true,
                  painter: _ArtPainter(
                    art: art,
                    strokeProgress: stroke,
                    fillProgress: fill,
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
  _ArtPainter(art: art, strokeProgress: stroke, fillProgress: fill)
      .paint(canvas, Size(art.width, art.height));
}

class _ArtPainter extends CustomPainter {
  final SplashArt art;
  final double strokeProgress;
  final double fillProgress;
  _ArtPainter({
    required this.art,
    required this.strokeProgress,
    required this.fillProgress,
  });

  // Per-element stagger: element i is active during a sliding window of the
  // phase, so early elements finish while late ones are still starting.
  static double _stagger(double p, int i, int n, double window) {
    final start = n <= 1 ? 0.0 : (i / (n - 1)) * (1 - window);
    return ((p - start) / window).clamp(0.0, 1.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
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
      old.fillProgress != fillProgress;
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
