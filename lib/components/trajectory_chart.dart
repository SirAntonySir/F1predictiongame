// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import '../theme/typography.dart';

class ChartSeries {
  final String label;
  final Color color;
  final List<double> points;
  const ChartSeries({required this.label, required this.color, required this.points});
}

class TrajectoryChart extends StatelessWidget {
  final List<ChartSeries> series;
  final List<String> xLabels;
  final double height;
  const TrajectoryChart({super.key, required this.series, required this.xLabels, this.height = 140});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 10,
          children: series
              .map((s) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 14, height: 3, color: s.color),
                      const SizedBox(width: 5),
                      Text(s.label, style: AppText.body(10)),
                    ],
                  ))
              .toList(),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: height,
          child: CustomPaint(painter: _ChartPainter(series, t.colorScheme.onSurface.withOpacity(0.12))),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: _displayLabels()
              .map((l) => Flexible(
                    child: Text(
                      l,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.fade,
                      style: AppText.body(9, color: t.colorScheme.onSurface.withOpacity(0.55)),
                    ),
                  ))
              .toList(),
        ),
      ],
    );
  }

  // Many sessions → too many labels to fit horizontally. Downsample to at most
  // `_maxLabels` evenly-spaced anchors (always including first + last). The
  // chart line still uses every data point; only the tick text thins out.
  static const int _maxLabels = 6;
  List<String> _displayLabels() {
    if (xLabels.length <= _maxLabels) return xLabels;
    final n = xLabels.length;
    final indices = <int>{
      for (var i = 0; i < _maxLabels; i++) (i * (n - 1) / (_maxLabels - 1)).round(),
    }.toList()..sort();
    return [for (final i in indices) xLabels[i]];
  }
}

class _ChartPainter extends CustomPainter {
  final List<ChartSeries> series;
  final Color gridColor;
  _ChartPainter(this.series, this.gridColor);

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = size.height * (i / 3);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (series.isEmpty) return;
    final maxV = series
        .expand((s) => s.points)
        .fold<double>(0, (m, v) => v > m ? v : m);
    if (maxV == 0) return;
    for (final s in series) {
      final paint = Paint()
        ..color = s.color
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke;
      final path = Path();
      for (var i = 0; i < s.points.length; i++) {
        final x = size.width * (i / (s.points.length - 1));
        final y = size.height - (s.points[i] / maxV) * size.height;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, paint);
      final dot = Offset(size.width, size.height - (s.points.last / maxV) * size.height);
      canvas.drawCircle(dot, 3.5, Paint()..color = s.color);
    }
  }

  @override
  bool shouldRepaint(_ChartPainter old) => true;
}
