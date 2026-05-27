// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import '../theme/tokens.dart';

/// A pick card styled like a paper ticket: cream background, strong border,
/// and a perforated tear-off bottom edge. Two visual halves laid out
/// horizontally (a slim left "stub" + the main body), with a dashed vertical
/// separator and circular notch cutouts at the top and bottom of the dashes.
///
/// Used by `home_screen._pickCard` and `session_results_screen._FutureSessionHero`
/// to give the user's predictions a tangible, hand-out feel.
class TicketCard extends StatelessWidget {
  final Widget body;
  final Widget? stub;
  final double stubWidth;
  final Color background;
  final Color borderColor;
  final double borderWidth;
  final EdgeInsetsGeometry bodyPadding;
  final EdgeInsetsGeometry stubPadding;
  final VoidCallback? onTap;
  const TicketCard({
    super.key,
    required this.body,
    this.stub,
    this.stubWidth = 88,
    this.background = const Color(0xFFFFF1B8),
    this.borderColor = Colors.black,
    this.borderWidth = 1.5,
    this.bodyPadding = const EdgeInsets.fromLTRB(Spacing.lg, Spacing.md, Spacing.lg, Spacing.md),
    this.stubPadding = const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.md),
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ticket = CustomPaint(
      painter: _TicketPainter(
        background: background,
        border: borderColor,
        borderWidth: borderWidth,
        hasStub: stub != null,
        stubWidth: stubWidth,
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Expanded(child: Padding(padding: bodyPadding, child: body)),
            if (stub != null)
              SizedBox(
                width: stubWidth,
                child: Padding(padding: stubPadding, child: Center(child: stub)),
              ),
          ],
        ),
      ),
    );
    if (onTap == null) return ticket;
    return InkWell(
      onTap: onTap,
      borderRadius: const BorderRadius.all(Radius.circular(12)),
      child: ticket,
    );
  }
}

class _TicketPainter extends CustomPainter {
  final Color background;
  final Color border;
  final double borderWidth;
  final bool hasStub;
  final double stubWidth;
  static const _radius = 12.0;
  static const _notchRadius = 7.0;
  _TicketPainter({
    required this.background,
    required this.border,
    required this.borderWidth,
    required this.hasStub,
    required this.stubWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()
      ..color = background
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = border
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;

    final body = _ticketPath(size);
    canvas.drawPath(body, fill);
    canvas.drawPath(body, stroke);

    if (hasStub) {
      // Dashed vertical perforation line between body and stub.
      final stubX = size.width - stubWidth;
      final dashPaint = Paint()
        ..color = border.withOpacity(0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      const top = _notchRadius;
      final bottom = size.height - _notchRadius;
      const dashLen = 4.0;
      const gapLen = 4.0;
      var y = top;
      while (y < bottom) {
        canvas.drawLine(Offset(stubX, y), Offset(stubX, (y + dashLen).clamp(top, bottom)), dashPaint);
        y += dashLen + gapLen;
      }
    }
  }

  Path _ticketPath(Size size) {
    const r = _radius;
    const n = _notchRadius;
    final p = Path();
    // Rounded rectangle outline; if there's a stub, carve a circular notch
    // at the top and bottom along the perforation line.
    final stubX = hasStub ? size.width - stubWidth : null;

    p.moveTo(r, 0);
    if (stubX != null) {
      p.lineTo(stubX - n, 0);
      // Top notch — semicircle bulging downward into the ticket.
      p.arcToPoint(
        Offset(stubX + n, 0),
        radius: const Radius.circular(_notchRadius),
        clockwise: false,
      );
    }
    p.lineTo(size.width - r, 0);
    p.arcToPoint(Offset(size.width, r), radius: const Radius.circular(_radius));
    p.lineTo(size.width, size.height - r);
    p.arcToPoint(Offset(size.width - r, size.height), radius: const Radius.circular(_radius));
    if (stubX != null) {
      p.lineTo(stubX + n, size.height);
      // Bottom notch — semicircle bulging upward into the ticket.
      p.arcToPoint(
        Offset(stubX - n, size.height),
        radius: const Radius.circular(_notchRadius),
        clockwise: false,
      );
    }
    p.lineTo(r, size.height);
    p.arcToPoint(Offset(0, size.height - r), radius: const Radius.circular(_radius));
    p.lineTo(0, r);
    p.arcToPoint(const Offset(r, 0), radius: const Radius.circular(_radius));
    p.close();
    return p;
  }

  @override
  bool shouldRepaint(_TicketPainter old) =>
      old.background != background ||
      old.border != border ||
      old.borderWidth != borderWidth ||
      old.hasStub != hasStub ||
      old.stubWidth != stubWidth;
}
