import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'branded_sheet.dart';

/// House-style HSV color picker in a bottom sheet: shade square, hue bar,
/// quick swatches. Pops with the chosen [Color], or null on cancel.
Future<Color?> showColorPickerSheet(
  BuildContext context, {
  required String title,
  required Color initial,
}) {
  return showBrandedSheet<Color>(
    context,
    builder: (ctx) => _ColorPickerSheet(title: title, initial: initial),
  );
}

// Racing-flavored quick picks: brand red, rosso, papaya, petronas teal,
// yellow, blue, then the neutral ladder (white/silver/black).
const _quickSwatches = <Color>[
  Color(0xFFE10600),
  Color(0xFFFF8700),
  Color(0xFFFFD233),
  Color(0xFF21C463),
  Color(0xFF00D2BE),
  Color(0xFF0090FF),
  Color(0xFFB147FF),
  Color(0xFFF2F2F2),
  Color(0xFFB8B8B8),
  Color(0xFF141414),
];

class _ColorPickerSheet extends StatefulWidget {
  final String title;
  final Color initial;
  const _ColorPickerSheet({required this.title, required this.initial});

  @override
  State<_ColorPickerSheet> createState() => _ColorPickerSheetState();
}

class _ColorPickerSheetState extends State<_ColorPickerSheet> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);

  @override
  Widget build(BuildContext context) {
    return BrandedSheet(
      title: widget.title,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ShadeSquare(
            hsv: _hsv,
            onChanged: (s, v) => setState(
                () => _hsv = _hsv.withSaturation(s).withValue(v)),
          ),
          const SizedBox(height: Spacing.md),
          _HueBar(
            hue: _hsv.hue,
            onChanged: (h) => setState(() => _hsv = _hsv.withHue(h)),
          ),
          const SizedBox(height: Spacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final c in _quickSwatches)
                _SwatchDot(
                  color: c,
                  selected: c.toARGB32() == _hsv.toColor().toARGB32(),
                  onTap: () =>
                      setState(() => _hsv = HSVColor.fromColor(c)),
                ),
            ],
          ),
        ],
      ),
      primaryLabel: 'Apply',
      onPrimary: () => Navigator.of(context).pop(_hsv.toColor()),
      onSecondary: () => Navigator.of(context).pop(),
    );
  }
}

class _SwatchDot extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _SwatchDot(
      {required this.color, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? t.colorScheme.onSurface : t.strokeColor,
            width: selected ? 2 : Strokes.subtle,
          ),
        ),
      ),
    );
  }
}

/// Saturation (→) × value (↓) plane for the current hue, with a ring thumb.
class _ShadeSquare extends StatelessWidget {
  final HSVColor hsv;
  final void Function(double s, double v) onChanged;
  const _ShadeSquare({required this.hsv, required this.onChanged});

  void _pick(Offset local, Size size) {
    onChanged(
      (local.dx / size.width).clamp(0.0, 1.0),
      (1 - local.dy / size.height).clamp(0.0, 1.0),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 150,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, 150);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanDown: (d) => _pick(d.localPosition, size),
            onPanUpdate: (d) => _pick(d.localPosition, size),
            child: CustomPaint(
              size: size,
              painter: _ShadeSquarePainter(hsv),
            ),
          );
        },
      ),
    );
  }
}

class _ShadeSquarePainter extends CustomPainter {
  final HSVColor hsv;
  _ShadeSquarePainter(this.hsv);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect =
        RRect.fromRectAndRadius(rect, Radii.rSm.topLeft);
    canvas.clipRRect(rrect);
    // White → pure hue across, then transparent → black down.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(colors: [
          Colors.white,
          HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor(),
        ]).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black],
        ).createShader(rect),
    );
    final thumb = Offset(
        hsv.saturation * size.width, (1 - hsv.value) * size.height);
    canvas.drawCircle(
        thumb,
        9,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3);
    canvas.drawCircle(
        thumb,
        10.5,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(_ShadeSquarePainter old) => old.hsv != hsv;
}

/// Rainbow hue strip with a vertical thumb.
class _HueBar extends StatelessWidget {
  final double hue;
  final ValueChanged<double> onChanged;
  const _HueBar({required this.hue, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 24,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, 24);
          void pick(Offset local) =>
              onChanged((local.dx / size.width).clamp(0.0, 1.0) * 360);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanDown: (d) => pick(d.localPosition),
            onPanUpdate: (d) => pick(d.localPosition),
            child: CustomPaint(size: size, painter: _HueBarPainter(hue)),
          );
        },
      ),
    );
  }
}

class _HueBarPainter extends CustomPainter {
  final double hue;
  _HueBarPainter(this.hue);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.clipRRect(RRect.fromRectAndRadius(rect, Radii.rSm.topLeft));
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(colors: [
          for (var h = 0; h <= 360; h += 60)
            HSVColor.fromAHSV(1, h.toDouble() % 360, 1, 1).toColor(),
        ]).createShader(rect),
    );
    final x = hue / 360 * size.width;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: Offset(x, size.height / 2),
              width: 6,
              height: size.height),
          const Radius.circular(3)),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_HueBarPainter old) => old.hue != hue;
}
