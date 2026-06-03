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
  /// Fired when the user taps anywhere on the ticket. Use [onBodyTap] / [onStubTap]
  /// to give the two halves distinct actions instead.
  final VoidCallback? onTap;
  /// Tap handler for the main (left) half of the ticket. Takes precedence
  /// over [onTap] when set.
  final VoidCallback? onBodyTap;
  /// Tap handler for the stub (right) half. Takes precedence over [onTap]
  /// when set.
  final VoidCallback? onStubTap;
  /// When true, render the ticket as if the stub has been torn off — the
  /// right edge becomes a vertical perforation (dashed line + circular
  /// notches top/bottom) instead of a clean rounded corner. Cannot be used
  /// together with [stub].
  final bool torn;
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
    this.onBodyTap,
    this.onStubTap,
    this.torn = false,
  }) : assert(!torn || stub == null, 'torn tickets cannot also render a stub');

  @override
  Widget build(BuildContext context) {
    // If body/stub each have their own tap handler, wrap each half in its
    // own InkWell so the ticket reads as two distinct hit zones (the
    // perforation visually divides them anyway). Otherwise fall back to a
    // single ticket-wide tap.
    final hasSplitTaps = onBodyTap != null || onStubTap != null;
    final bodyChild = Padding(padding: bodyPadding, child: body);
    final stubChild = stub == null
        ? null
        : Padding(padding: stubPadding, child: Center(child: stub));

    final row = IntrinsicHeight(
      child: Row(
        children: [
          Expanded(
            child: hasSplitTaps
                ? InkWell(onTap: onBodyTap, child: bodyChild)
                : bodyChild,
          ),
          if (stubChild != null)
            SizedBox(
              width: stubWidth,
              child: hasSplitTaps
                  ? InkWell(onTap: onStubTap, child: stubChild)
                  : stubChild,
            ),
        ],
      ),
    );

    // The cream ticket background is theme-independent. Force a dark default
    // text + icon color so children that don't set an explicit color (e.g.
    // the Countdown widget) don't inherit the theme's onSurface — which is
    // white in dark mode and renders invisibly on the cream stock.
    final ticket = DefaultTextStyle.merge(
      style: const TextStyle(color: Colors.black),
      child: IconTheme.merge(
        data: const IconThemeData(color: Colors.black),
        child: CustomPaint(
          painter: _TicketPainter(
            background: background,
            border: borderColor,
            borderWidth: borderWidth,
            hasStub: stub != null,
            stubWidth: stubWidth,
            torn: torn,
          ),
          child: row,
        ),
      ),
    );
    if (hasSplitTaps || onTap == null) return ticket;
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
  final bool torn;
  static const _radius = 12.0;
  static const _notchRadius = 7.0;
  _TicketPainter({
    required this.background,
    required this.border,
    required this.borderWidth,
    required this.hasStub,
    required this.stubWidth,
    required this.torn,
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

    if (hasStub || torn) {
      // Dashed vertical perforation. For a stub it sits between body and
      // stub; for a torn ticket it IS the right edge.
      final perforationX = torn ? size.width : size.width - stubWidth;
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
        canvas.drawLine(
          Offset(perforationX, y),
          Offset(perforationX, (y + dashLen).clamp(top, bottom)),
          dashPaint,
        );
        y += dashLen + gapLen;
      }
    }
  }

  Path _ticketPath(Size size) {
    const r = _radius;
    const n = _notchRadius;
    final p = Path();
    // Rounded rectangle outline; if there's a stub, carve a circular notch
    // at the top and bottom along the perforation line. If torn, carve the
    // notches at the top-right and bottom-right corners so the right edge
    // reads as "the stub was here and got ripped off".
    final stubX = hasStub ? size.width - stubWidth : null;

    p.moveTo(r, 0);
    if (stubX != null) {
      p.lineTo(stubX - n, 0);
      p.arcToPoint(
        Offset(stubX + n, 0),
        radius: const Radius.circular(_notchRadius),
        clockwise: false,
      );
    }
    if (torn) {
      // Top edge runs all the way to a notch carved into the top-right corner.
      p.lineTo(size.width - n, 0);
      // Semicircle bulging downward, ending at the right edge below the corner.
      p.arcToPoint(
        Offset(size.width, n),
        radius: const Radius.circular(_notchRadius),
        clockwise: false,
      );
      // Right edge runs straight down to the bottom-right notch.
      p.lineTo(size.width, size.height - n);
      // Bottom-right notch bulging leftward, ending on the bottom edge.
      p.arcToPoint(
        Offset(size.width - n, size.height),
        radius: const Radius.circular(_notchRadius),
        clockwise: false,
      );
    } else {
      p.lineTo(size.width - r, 0);
      p.arcToPoint(Offset(size.width, r), radius: const Radius.circular(_radius));
      p.lineTo(size.width, size.height - r);
      p.arcToPoint(Offset(size.width - r, size.height), radius: const Radius.circular(_radius));
    }
    if (stubX != null) {
      p.lineTo(stubX + n, size.height);
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
      old.stubWidth != stubWidth ||
      old.torn != torn;
}
