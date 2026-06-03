// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

/// Diagonal racing-stripe overlay used on the home hero card and the league
/// podium leader block — shared so both share the same stripe rhythm.
class RacingStripesPainter extends CustomPainter {
  final Color color;
  final double opacity;
  final double stripe;
  final double gap;

  const RacingStripesPainter({
    this.color = Colors.white,
    this.opacity = 0.13,
    this.stripe = 6.0,
    this.gap = 10.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color.withOpacity(opacity);
    final step = stripe + gap;
    final diagonal = size.width + size.height;
    for (var d = -size.height; d < diagonal; d += step) {
      final path = Path()
        ..moveTo(d, 0)
        ..lineTo(d + stripe, 0)
        ..lineTo(d + stripe + size.height, size.height)
        ..lineTo(d + size.height, size.height)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(RacingStripesPainter old) =>
      old.color != color ||
      old.opacity != opacity ||
      old.stripe != stripe ||
      old.gap != gap;
}
