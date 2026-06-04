// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import '../theme/tokens.dart';

/// How the right edge of the ticket is rendered when the stub is missing
/// or has been "used".
///
/// - [none]    — normal rounded rectangle.
/// - [cut]     — physical perforation: notches carved into the top/bottom
///               right corners and a dashed line down what's left of the
///               right edge. Reads as "the stub was here and got ripped off".
/// - [ghosted] — keep the full body+stub silhouette (border outline,
///               perforation line, top/bottom notches at the perforation)
///               but leave the stub area transparent, so it reads as a
///               hole punched out of the ticket. No stub widget is needed.
enum TicketTear { none, cut, ghosted }

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
  /// How the right edge of the ticket is rendered. See [TicketTear] for the
  /// available variants. Cannot be used together with [stub].
  final TicketTear tear;
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
    this.tear = TicketTear.none,
  }) : assert(tear == TicketTear.none || stub == null,
            'cut/ghosted tickets cannot also render a stub');

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
    // Ghosted tickets need to reserve the stub's worth of horizontal space
    // (so the perforation line ends up in the same spot as a normal ticket)
    // but render nothing inside it — the painter shows it as a cutout.
    final reservesStubSpace = stubChild != null || tear == TicketTear.ghosted;

    // Row layout has two modes:
    //   1. Unbounded vertical context (the default — ticket in a ListView /
    //      Column): wrap in IntrinsicHeight so the Row knows what height
    //      to stretch its children to.
    //   2. Bounded vertical context (e.g. inside Expanded inside an
    //      IntrinsicHeight Row on iPad): skip IntrinsicHeight and just
    //      stretch — the ticket then grows to fill the parent's height,
    //      matching a taller sibling card.
    // Either way CrossAxisAlignment.stretch keeps body + stub the same
    // height as the row.
    final row = LayoutBuilder(
      builder: (ctx, constraints) {
        final coreRow = Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: hasSplitTaps
                  ? InkWell(onTap: onBodyTap, child: bodyChild)
                  : bodyChild,
            ),
            if (reservesStubSpace)
              SizedBox(
                width: stubWidth,
                // Empty SizedBox (not SizedBox.expand) when ghosted with
                // no stub widget — Row.stretch will fill it to row height
                // without needing a bounded parent.
                child: stubChild == null
                    ? const SizedBox()
                    : (hasSplitTaps
                        ? InkWell(onTap: onStubTap, child: stubChild)
                        : stubChild),
              ),
          ],
        );
        return constraints.maxHeight.isFinite
            ? coreRow
            : IntrinsicHeight(child: coreRow);
      },
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
            hasStub: stub != null || tear == TicketTear.ghosted,
            stubWidth: stubWidth,
            tear: tear,
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
  final TicketTear tear;
  static const _radius = 12.0;
  static const _notchRadius = 7.0;
  _TicketPainter({
    required this.background,
    required this.border,
    required this.borderWidth,
    required this.hasStub,
    required this.stubWidth,
    required this.tear,
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
    if (tear == TicketTear.ghosted) {
      // Wash the whole ticket with a low-alpha background first so the stub
      // area is a translucent ghost rather than fully see-through, then
      // paint the body region opaque on top so it stays solid.
      final ghostFill = Paint()
        ..color = background.withOpacity(0.30)
        ..style = PaintingStyle.fill;
      canvas.drawPath(body, ghostFill);
      canvas.drawPath(_bodyOnlyPath(size), fill);
    } else {
      canvas.drawPath(body, fill);
    }
    canvas.drawPath(body, stroke);

    if (hasStub || tear == TicketTear.cut) {
      // Dashed vertical perforation. For a stub it sits between body and
      // stub; for a cut-torn ticket it IS the right edge.
      final perforationX =
          tear == TicketTear.cut ? size.width : size.width - stubWidth;
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

  /// Path covering only the body half of a ghosted ticket. Traces the body's
  /// perimeter and uses two quarter-circle arcs at the perforation line so
  /// the body's right edge meets the perforation cleanly — the arcs bulge
  /// INTO the body, mirroring the half-circle notches that the full outline
  /// carves out of the top and bottom edges.
  Path _bodyOnlyPath(Size size) {
    const r = _radius;
    const n = _notchRadius;
    final stubX = size.width - stubWidth;
    final p = Path();
    p.moveTo(r, 0);
    // Top edge to the left side of the perforation notch.
    p.lineTo(stubX - n, 0);
    // Top quarter-circle, sharing the same circle as the full outline's
    // top notch (centred at (stubX, 0)). clockwise: false picks the arc
    // that bulges DOWN-LEFT, i.e. into the body — the mirror of what the
    // outline carves out of the top edge.
    p.arcToPoint(Offset(stubX, n),
        radius: const Radius.circular(_notchRadius), clockwise: false);
    // Down the perforation line.
    p.lineTo(stubX, size.height - n);
    // Bottom quarter-circle, same logic mirrored — bulges UP-LEFT into the
    // body so it meets the perforation cleanly.
    p.arcToPoint(Offset(stubX - n, size.height),
        radius: const Radius.circular(_notchRadius), clockwise: false);
    // Bottom edge to bottom-left corner.
    p.lineTo(r, size.height);
    p.arcToPoint(Offset(0, size.height - r),
        radius: const Radius.circular(_radius));
    p.lineTo(0, r);
    p.arcToPoint(const Offset(r, 0), radius: const Radius.circular(_radius));
    p.close();
    return p;
  }

  Path _ticketPath(Size size) {
    const r = _radius;
    const n = _notchRadius;
    final p = Path();
    // Rounded rectangle outline; if there's a stub, carve a circular notch
    // at the top and bottom along the perforation line. For TicketTear.cut
    // the right corners get notched to read as "stub was ripped off". For
    // TicketTear.faded the rectangle stays clean — the fade itself comes
    // from the ShaderMask wrapped around the whole ticket.
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
    if (tear == TicketTear.cut) {
      p.lineTo(size.width - n, 0);
      p.arcToPoint(
        Offset(size.width, n),
        radius: const Radius.circular(_notchRadius),
        clockwise: false,
      );
      p.lineTo(size.width, size.height - n);
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
      old.tear != tear;
}
