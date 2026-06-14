// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import 'ticket_ornament.dart';
import 'ticket_stub.dart';
import 'ticket_style.dart';

class TicketDataCell {
  final String label;
  final String value;
  const TicketDataCell({required this.label, required this.value});
}

enum TicketTear { none, cut, ghosted }

/// Parameterised "blank" paper-ticket. Variants ([PickTicket],
/// [SouvenirTicket]) instantiate this with sensible defaults; callers can use
/// it directly for one-off tickets.
class TicketRohling extends StatelessWidget {
  final TicketStyle style;
  final String? edgeSerial;
  final String? metaLeft;
  final String? metaRight;
  final String title;
  final String? subtitle;
  final Widget? illustration;
  final TicketOrnament? ornament;
  final List<TicketDataCell> dataRow;
  final TicketStub stub;
  final TicketTear tear;
  final VoidCallback? onTap;
  final VoidCallback? onBodyTap;
  final VoidCallback? onStubTap;

  const TicketRohling({
    super.key,
    required this.style,
    this.edgeSerial,
    this.metaLeft,
    this.metaRight,
    required this.title,
    this.subtitle,
    this.illustration,
    this.ornament,
    required this.dataRow,
    required this.stub,
    this.tear = TicketTear.none,
    this.onTap,
    this.onBodyTap,
    this.onStubTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = tokensFor(style);
    final effectiveOrnament = ornament ?? tokens.defaultOrnament;
    final stubWidth = widthFor(stub);
    final hasSplitTaps = onBodyTap != null || onStubTap != null;

    final body = Padding(
      padding: const EdgeInsets.fromLTRB(26, 12, 18, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(child: Text(metaLeft ?? '', style: tokens.meta, overflow: TextOverflow.ellipsis)),
              Text(metaRight ?? '', style: tokens.meta),
            ],
          ),
          const SizedBox(height: 8),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TicketOrnamentWidget(ornament: effectiveOrnament, color: tokens.inkColor),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(subtitle!, style: tokens.subtitle),
                      ],
                      const SizedBox(height: 2),
                      Text(title, style: tokens.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                if (illustration != null) ...[
                  const SizedBox(width: 8),
                  SizedBox(width: 90, height: 46, child: illustration),
                ],
              ],
            ),
          ),
          if (dataRow.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.only(top: 6),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: tokens.inkColor.withOpacity(0.4))),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final cell in dataRow)
                    Padding(
                      padding: const EdgeInsets.only(right: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(cell.label, style: tokens.dataLabel),
                          const SizedBox(height: 3),
                          Text(cell.value, style: tokens.dataValue),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );

    final stubContent = TicketStubContent(stub: stub, titleHint: title, textStyle: tokens.meta);

    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: hasSplitTaps
              ? InkWell(onTap: onBodyTap, child: body)
              : body,
        ),
        if (stubWidth > 0)
          SizedBox(
            width: stubWidth,
            child: hasSplitTaps
                ? InkWell(onTap: onStubTap, child: stubContent)
                : stubContent,
          ),
      ],
    );

    final core = CustomPaint(
      painter: _TicketPainter(tokens: tokens, stubWidth: stubWidth, tear: tear),
      child: row,
    );

    final serialStyle = tokens.meta.copyWith(letterSpacing: 3);
    final stack = Stack(
      children: [
        core,
        if (edgeSerial != null) ...[
          Positioned(
            left: 4, top: 0, bottom: 0,
            child: Center(
              child: RotatedBox(
                quarterTurns: 3,
                child: Text(edgeSerial!, style: serialStyle, maxLines: 1, overflow: TextOverflow.fade, softWrap: false),
              ),
            ),
          ),
          Positioned(
            right: 4, top: 0, bottom: 0,
            child: Center(
              child: RotatedBox(
                quarterTurns: 1,
                child: Text(edgeSerial!, style: serialStyle, maxLines: 1, overflow: TextOverflow.fade, softWrap: false),
              ),
            ),
          ),
        ],
      ],
    );

    final ticket = IntrinsicHeight(child: stack);
    if (hasSplitTaps || onTap == null) return ticket;
    return InkWell(
      onTap: onTap,
      borderRadius: const BorderRadius.all(Radius.circular(12)),
      child: ticket,
    );
  }
}

class _TicketPainter extends CustomPainter {
  final TicketStyleTokens tokens;
  final double stubWidth;
  final TicketTear tear;
  static const _radius = 10.0;
  static const _notchRadius = 7.0;

  _TicketPainter({required this.tokens, required this.stubWidth, required this.tear});

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()
      ..color = tokens.paperColor
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = tokens.inkColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final outline = _outline(size);
    canvas.drawPath(outline, fill);
    canvas.save();
    canvas.clipPath(outline);
    _paintBackground(canvas, size);
    canvas.restore();
    canvas.drawPath(outline, stroke);

    if (tokens.innerFrame) {
      final inset = Rect.fromLTWH(5, 5, size.width - 10, size.height - 10);
      final frame = Paint()
        ..color = tokens.inkColor.withOpacity(0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8;
      canvas.drawRRect(
        RRect.fromRectAndRadius(inset, const Radius.circular(4)),
        frame,
      );
    }

    if (tokens.accentBarColor != null) {
      final bar = Paint()
        ..color = tokens.accentBarColor!
        ..style = PaintingStyle.fill;
      canvas.save();
      canvas.clipPath(outline);
      canvas.drawRect(Rect.fromLTWH(0, 0, 6, size.height), bar);
      canvas.restore();
    }

    if (stubWidth > 0) {
      final perfX = size.width - stubWidth;
      final dashPaint = Paint()
        ..color = tokens.inkColor.withOpacity(0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      const top = _notchRadius;
      final bottom = size.height - _notchRadius;
      const dash = 4.0;
      const gap = 4.0;
      var y = top;
      while (y < bottom) {
        canvas.drawLine(
          Offset(perfX, y),
          Offset(perfX, (y + dash).clamp(top, bottom)),
          dashPaint,
        );
        y += dash + gap;
      }
    }
  }

  void _paintBackground(Canvas canvas, Size size) {
    switch (tokens.background) {
      case TicketBackground.plain:
        return;
      case TicketBackground.linedVertical:
        final p = Paint()
          ..color = tokens.inkColor.withOpacity(0.08)
          ..strokeWidth = 1;
        for (double x = 12; x < size.width - stubWidth - 4; x += 3) {
          canvas.drawLine(Offset(x, 4), Offset(x, size.height - 4), p);
        }
        return;
      case TicketBackground.diagonalStripeBand:
        final bandTop = size.height * 0.30;
        final bandBottom = size.height * 0.78;
        canvas.save();
        canvas.clipRect(Rect.fromLTRB(0, bandTop, size.width - stubWidth, bandBottom));
        final p = Paint()
          ..color = tokens.inkColor.withOpacity(0.10)
          ..strokeWidth = 8;
        for (double d = -size.height; d < size.width + size.height; d += 22) {
          canvas.drawLine(Offset(d, 0), Offset(d + size.height, size.height), p);
        }
        canvas.restore();
        return;
    }
  }

  Path _outline(Size size) {
    const r = _radius;
    const n = _notchRadius;
    final stubX = stubWidth > 0 ? size.width - stubWidth : null;
    final p = Path()..moveTo(r, 0);
    if (stubX != null) {
      p.lineTo(stubX - n, 0);
      p.arcToPoint(Offset(stubX + n, 0), radius: const Radius.circular(_notchRadius), clockwise: false);
    }
    if (tear == TicketTear.cut) {
      p.lineTo(size.width - n, 0);
      p.arcToPoint(Offset(size.width, n), radius: const Radius.circular(_notchRadius), clockwise: false);
      p.lineTo(size.width, size.height - n);
      p.arcToPoint(Offset(size.width - n, size.height), radius: const Radius.circular(_notchRadius), clockwise: false);
    } else {
      p.lineTo(size.width - r, 0);
      p.arcToPoint(Offset(size.width, r), radius: const Radius.circular(_radius));
      p.lineTo(size.width, size.height - r);
      p.arcToPoint(Offset(size.width - r, size.height), radius: const Radius.circular(_radius));
    }
    if (stubX != null) {
      p.lineTo(stubX + n, size.height);
      p.arcToPoint(Offset(stubX - n, size.height), radius: const Radius.circular(_notchRadius), clockwise: false);
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
      old.tokens != tokens || old.stubWidth != stubWidth || old.tear != tear;
}
