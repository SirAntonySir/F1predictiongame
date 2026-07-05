// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../theme/colors.dart';

import 'ticket_ornament.dart';
import 'ticket_stub.dart';
import 'ticket_style.dart';
import 'ticket_watermark_config.dart';

// Re-export the watermark config + presets so existing call sites that
// already import 'ticket_rohling.dart' (e.g. dev preview, debugging tools)
// keep compiling without an extra import line.
export 'ticket_watermark_config.dart';

class TicketDataCell {
  final String label;
  final String value;
  /// When true, the ticket overlays `assets/tick.svg` on top of this cell —
  /// used by [SouvenirTicket] to flag picks that turned out to be correct.
  final bool marked;
  const TicketDataCell({
    required this.label,
    required this.value,
    this.marked = false,
  });
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

  /// Illustration painted as a low-opacity watermark behind the body content,
  /// scaled up and clipped to the body region. Text sits on top.
  final Widget? illustration;

  /// Opacity of the watermark illustration. Defaults to 0.16 on cream paper
  /// and 0.22 on dark paper (dark presets need a louder watermark to read).
  final double? illustrationOpacity;

  /// Where the watermark sits inside the body. Nullable so a parent variant
  /// can pass through null and let Rohling's default win; resolved to
  /// [_kDefaultIllustrationAlignment] in build().
  final Alignment? illustrationAlignment;

  /// Multiplier on the watermark's natural size. Nullable for the same reason
  /// — resolves to [_kDefaultIllustrationScale] in build(). >1 lets the SVG
  /// bleed past the body bounds (ClipRect handles the overflow).
  final double? illustrationScale;

  /// Secondary watermark painted behind [illustration] — typically a circuit
  /// track outline that layers under the car silhouette. Same clipping rules.
  final Widget? secondaryIllustration;
  final double? secondaryIllustrationOpacity;
  final Alignment? secondaryIllustrationAlignment;
  final double? secondaryIllustrationScale;
  final TicketOrnament? ornament;
  final List<TicketDataCell> dataRow;
  final TicketStub stub;
  final TicketTear tear;

  /// Free-form body content. When set, replaces the structured
  /// metaLeft/metaRight/title/subtitle/dataRow column entirely — the caller
  /// is responsible for its own padding. Watermark illustrations still paint
  /// behind it. Used to host bespoke layouts (countdowns, perforated inner
  /// dividers, pick chips) that don't fit the structured slots.
  final Widget? bodyOverride;

  /// Free-form stub content. Replaces the sealed [TicketStub] rendering. The
  /// strip is still sized by [stub] (via [widthFor]) unless [stubWidthOverride]
  /// is set, so the perforation line stays consistent across variants.
  final Widget? stubOverride;

  /// Explicit stub strip width. Overrides [widthFor]([stub]) — useful when the
  /// caller has a wider/narrower custom stub via [stubOverride].
  final double? stubWidthOverride;

  /// Fires on a tap anywhere on the ticket. Ticket wrappers point this at their
  /// options sheet so a single tap opens the menu.
  final VoidCallback? onTap;

  /// Fires on a long-press anywhere on the ticket. Used by [PickTicket] and
  /// [SouvenirTicket] to invoke their default share-as-image action — set
  /// explicitly here when using [TicketRohling] directly. Composes with the
  /// tap handlers above (the gesture detector sits outside any InkWell).
  final VoidCallback? onLongPress;

  /// Overrides the LEFT edge serial only. When set, the left side renders
  /// this string (centered vertically, rotated 270°) instead of duplicating
  /// [edgeSerial]. The right edge serial still uses [edgeSerial]. Used to
  /// stamp the session type (RACE / QUALIFYING / SPRINT…) across the left
  /// edge prominently while keeping the round/event reference on the right.
  final String? leftEdgeSerial;

  /// Italic script accent rendered immediately below the title — "Grand
  /// Prix" / "Racing" / "Championship" in the variant's cursive flourish.
  /// Only paints when the active style's tokens declare a [scriptAccent]
  /// style; otherwise silently ignored (so callers can pass it for every
  /// ticket without bloating the older paper variants).
  final String? scriptAccent;

  const TicketRohling({
    super.key,
    required this.style,
    this.edgeSerial,
    this.metaLeft,
    this.metaRight,
    this.title = '',
    this.subtitle,
    this.illustration,
    this.illustrationOpacity,
    this.illustrationAlignment,
    this.illustrationScale,
    this.secondaryIllustration,
    this.secondaryIllustrationOpacity,
    this.secondaryIllustrationAlignment,
    this.secondaryIllustrationScale,
    this.ornament,
    this.dataRow = const [],
    required this.stub,
    this.tear = TicketTear.none,
    this.bodyOverride,
    this.stubOverride,
    this.stubWidthOverride,
    this.onTap,
    this.onLongPress,
    this.leftEdgeSerial,
    this.scriptAccent,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = tokensFor(style);
    final effectiveOrnament = ornament ?? tokens.defaultOrnament;
    // Ghosted tear reserves the stub strip width even when there's no stub
    // widget — the painter draws the carved-out silhouette where the stub
    // would have been.
    final stubWidth = stubWidthOverride ??
        (stub is StubNone && tear == TicketTear.ghosted
            ? kStubWidth
            : widthFor(stub));

    final isDark = tokens.paperColor.computeLuminance() < 0.3;
    // Resolve every watermark knob from the per-instance override → config
    // default chain. PickTicket / SouvenirTicket pass null so the config wins.
    final effectiveIllustrationOpacity = illustrationOpacity ??
        (isDark
            ? kPrimaryWatermark.opacityDark
            : kPrimaryWatermark.opacityCream);
    final effectiveSecondaryOpacity = secondaryIllustrationOpacity ??
        (isDark
            ? kSecondaryWatermark.opacityDark
            : kSecondaryWatermark.opacityCream);
    final effectiveIllustrationAlignment =
        illustrationAlignment ?? kPrimaryWatermark.alignment;
    final effectiveIllustrationScale =
        illustrationScale ?? kPrimaryWatermark.scale;
    final effectiveSecondaryAlignment =
        secondaryIllustrationAlignment ?? kSecondaryWatermark.alignment;
    final effectiveSecondaryScale =
        secondaryIllustrationScale ?? kSecondaryWatermark.scale;

    final foreground = bodyOverride ??
        Padding(
          padding: const EdgeInsets.fromLTRB(26, 12, 18, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                      child: Text(metaLeft ?? '',
                          style: tokens.meta, overflow: TextOverflow.ellipsis)),
                  Text(metaRight ?? '', style: tokens.meta),
                ],
              ),
              const SizedBox(height: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  TicketOrnamentWidget(
                      ornament: effectiveOrnament, color: tokens.inkColor),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(subtitle!, style: tokens.subtitle),
                  ],
                  const SizedBox(height: 2),
                  Text(title,
                      style: tokens.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  // Italic script accent — only renders when both the
                  // caller passes a string AND the variant declares a
                  // [scriptAccent] style. Older paper variants silently
                  // drop it.
                  if (scriptAccent != null && tokens.scriptAccent != null) ...[
                    const SizedBox(height: 4),
                    Text(scriptAccent!,
                        style: tokens.scriptAccent,
                        maxLines: 1,
                        overflow: TextOverflow.fade),
                  ],
                ],
              ),
              if (dataRow.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.only(top: 6),
                  decoration: BoxDecoration(
                    border: Border(
                        top: BorderSide(
                            color: tokens.inkColor.withOpacity(0.4))),
                  ),
                  // Wrap so 5 picks + status spill onto a second row when the
                  // ticket isn't wide enough for them all — keeps the paper-ticket
                  // aesthetic without horizontal clipping.
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.start,
                    children: [
                      for (final cell in dataRow)
                        // Marked cells get a hand-drawn tick painted on top of
                        // both the label and value, sized to the cell's
                        // natural width and slightly oversized vertically so
                        // the strokes hug the text instead of looking pasted.
                        Stack(
                          clipBehavior: Clip.none,
                          alignment: Alignment.center,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(cell.label, style: tokens.dataLabel),
                                const SizedBox(height: 3),
                                Text(cell.value, style: tokens.dataValue),
                              ],
                            ),
                            if (cell.marked)
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: SvgPicture.asset(
                                    'assets/tick.svg',
                                    fit: BoxFit.contain,
                                    // Brand green so the tick reads as a
                                    // correctness signal regardless of paper
                                    // colour (would disappear into the ink on
                                    // cream / dark presets otherwise).
                                    colorFilter: const ColorFilter.mode(
                                      BrandColors.ok,
                                      BlendMode.srcIn,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );

    // Body = watermark illustration (scaled up, low-opacity, clipped) + the
    // text/data column on top. The watermark sits inside the body region only,
    // so it never crosses the perforation into the stub.
    // Primary uses BoxFit.cover so the car silhouette can bleed off-edge;
    // secondary uses BoxFit.contain so the circuit outline stays fully visible.
    // Caller-provided SVG widgets often render with their authored stroke /
    // fill (white for the circuit outline asset, black for stencils) — we
    // recolor them to the style's ink so they read against any paper. srcIn
    // keeps only the opaque pixels and tints them; the alpha channel survives.
    final inkFilter = ColorFilter.mode(tokens.inkColor, BlendMode.srcIn);
    // [boxW] / [boxH] set the watermark "frame" aspect. Choice matters because
    // FittedBox+cover/contain pick which axis becomes the slack the alignment
    // can consume — a wide 400×180 frame (aspect 2.22) inside a body that's
    // closer to square forces cover into height-fill, so vertical alignment
    // becomes a no-op. The primary (car) passes a more square frame so cover
    // overflows vertically and `bottomRight` actually crops the top.
    Widget watermark(Widget w, double opacity, Alignment align, double scale,
            {required BoxFit fit, double boxW = 400, double boxH = 180}) =>
        Positioned.fill(
          // Skeleton.ignore: skeletonizer would otherwise paint the SVG's
          // opaque silhouette as a solid black slab. Watermarks are decorative
          // — render at their real low opacity (or empty while loading)
          // instead of joining the skeleton shading pass.
          child: Skeleton.ignore(
            child: IgnorePointer(
              child: ClipRect(
                child: Opacity(
                  opacity: opacity,
                  // Transform.scale wraps the FITTED output so scale > 1
                  // actually grows the rendered watermark (bleeding into the
                  // ClipRect's crop). Putting the scale on the SizedBox alone
                  // is a no-op: the outer FittedBox immediately refits to the
                  // parent, so width × scale and height × scale cancel for the
                  // visible aspect. scale=0 looked special only because it
                  // collapsed the SizedBox to 0×0.
                  child: Transform.scale(
                    scale: scale,
                    alignment: align,
                    child: FittedBox(
                      fit: fit,
                      alignment: align,
                      child: SizedBox(
                        width: boxW,
                        height: boxH,
                        // Align(align) so the inner SVG hugs the requested edge
                        // INSIDE the frame — without this, SvgPicture's own
                        // centering would park a square asset in the middle of
                        // the frame, and the outer FittedBox couldn't push it
                        // further when the fit had already filled the
                        // constrained axis.
                        child: Align(
                          alignment: align,
                          child:
                              ColorFiltered(colorFilter: inkFilter, child: w),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

    // Stack order: paper (already painted by CustomPainter) → car silhouette
    // (primary, bleeds off-edge per [kPrimaryWatermark]) → foreground.
    // The secondary watermark (circuit) is lifted to the OUTER stack below
    // so it spans the full ticket width and bleeds across the perforation
    // into the stub area.
    final body = Stack(
      children: [
        if (illustration != null)
          watermark(illustration!, effectiveIllustrationOpacity,
              effectiveIllustrationAlignment, effectiveIllustrationScale,
              fit: kPrimaryWatermark.fit,
              boxW: kPrimaryWatermark.boxW,
              boxH: kPrimaryWatermark.boxH),
        foreground,
      ],
    );

    final stubContent = stubOverride ??
        TicketStubContent(stub: stub, titleHint: title, textStyle: tokens.meta);

    // Size the ticket from the body's natural height instead of going through
    // IntrinsicHeight + Row + Expanded — that combination mismeasures here
    // (Wrap inside a flex child trips up the dry-intrinsic chain) and squeezes
    // the body until it overflows. Body is the non-positioned child of an
    // inner Stack so it determines size; the stub fills the reserved right
    // strip via Positioned.
    final bodyChild = body;
    final stubChild = stubContent;

    // Circuit watermark sits ABOVE the body padding but BELOW the stub —
    // bleeds full-width while the stub stays legible. Must be a direct child
    // of Stack so the Positioned.fill inside `watermark(...)` applies.
    final inner = stubWidth > 0
        ? Stack(
            children: [
              Padding(
                padding: EdgeInsets.only(right: stubWidth),
                child: bodyChild,
              ),
              if (secondaryIllustration != null)
                watermark(secondaryIllustration!, effectiveSecondaryOpacity,
                    effectiveSecondaryAlignment, effectiveSecondaryScale,
                    fit: kSecondaryWatermark.fit,
                    boxW: kSecondaryWatermark.boxW,
                    boxH: kSecondaryWatermark.boxH),
              Positioned(
                top: 0,
                bottom: 0,
                right: 0,
                width: stubWidth,
                child: stubChild,
              ),
            ],
          )
        : Stack(
            children: [
              bodyChild,
              if (secondaryIllustration != null)
                watermark(secondaryIllustration!, effectiveSecondaryOpacity,
                    effectiveSecondaryAlignment, effectiveSecondaryScale,
                    fit: kSecondaryWatermark.fit,
                    boxW: kSecondaryWatermark.boxW,
                    boxH: kSecondaryWatermark.boxH),
            ],
          );

    final core = CustomPaint(
      painter: _TicketPainter(tokens: tokens, stubWidth: stubWidth, tear: tear),
      child: inner,
    );

    final serialStyle = tokens.meta.copyWith(letterSpacing: 3);
    final stack = Stack(
      children: [
        core,
        if (edgeSerial != null || leftEdgeSerial != null) ...[
          // LEFT edge: when [leftEdgeSerial] is set, render it centered
          // vertically so the session-type stamp sits in the middle of the
          // ticket. Otherwise duplicate [edgeSerial], top-anchored
          // shrink-wrap (so long round/event names don't reserve invisible
          // space that pushes into the data row).
          if (leftEdgeSerial != null)
            Positioned(
              left: 4,
              top: 0,
              bottom: 0,
              child: Center(
                child: RotatedBox(
                  quarterTurns: 3,
                  child: Text(leftEdgeSerial!,
                      style: serialStyle,
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false),
                ),
              ),
            )
          else if (edgeSerial != null)
            Positioned(
              left: 4,
              top: 0,
              child: RotatedBox(
                quarterTurns: 3,
                child: Text(edgeSerial!,
                    style: serialStyle,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false),
              ),
            ),
          // RIGHT edge: always uses [edgeSerial] (top-anchored shrink-wrap).
          if (edgeSerial != null)
            Positioned(
              right: 4,
              top: 0,
              child: RotatedBox(
                quarterTurns: 1,
                child: Text(edgeSerial!,
                    style: serialStyle,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false),
              ),
            ),
        ],
      ],
    );

    Widget ticket = stack;
    if (onTap != null) {
      ticket = InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        child: ticket,
      );
    }
    if (onLongPress != null) {
      // GestureDetector sits OUTSIDE the InkWell so the long-press fires even
      // over the tap InkWell. behavior: opaque so dead-zone areas (the
      // watermark bleed, ghosted stub region) still receive the gesture.
      ticket = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: onLongPress,
        child: ticket,
      );
    }
    return ticket;
  }
}

class _TicketPainter extends CustomPainter {
  final TicketStyleTokens tokens;
  final double stubWidth;
  final TicketTear tear;
  static const _radius = 10.0;
  static const _notchRadius = 7.0;

  _TicketPainter(
      {required this.tokens, required this.stubWidth, required this.tear});

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..style = PaintingStyle.fill;
    if (tokens.paperGradient != null) {
      // Vertical top→bottom fade (lit top edge to darker base). The flat
      // paperColor still backs the ghosted-tear wash below.
      fill.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: tokens.paperGradient!,
      ).createShader(Offset.zero & size);
    } else {
      fill.color = tokens.paperColor;
    }
    final stroke = Paint()
      ..color = tokens.inkColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final outline = _outline(size);
    if (tear == TicketTear.ghosted && stubWidth > 0) {
      // Wash the whole outline at low opacity so the stub area reads as a
      // ghost of where the stub used to be, then paint the body region (left
      // of the perforation) solid on top. Background patterns clip to the
      // body region too — the stub area is intentionally bare.
      final ghostFill = Paint()
        ..color = tokens.paperColor.withOpacity(0.30)
        ..style = PaintingStyle.fill;
      canvas.drawPath(outline, ghostFill);
      final bodyOnly = _bodyOnlyPath(size);
      canvas.drawPath(bodyOnly, fill);
      canvas.save();
      canvas.clipPath(bodyOnly);
      _paintBackground(canvas, size);
      canvas.restore();
    } else {
      canvas.drawPath(outline, fill);
      canvas.save();
      canvas.clipPath(outline);
      _paintBackground(canvas, size);
      canvas.restore();
    }

    // Floodlit top glow — a radial stadium-light wash bled from the top edge,
    // clipped to the ticket outline so it never crosses into the notches.
    if (tokens.topGlowColor != null) {
      canvas.save();
      canvas.clipPath(outline);
      final glowRect = Rect.fromLTWH(0, 0, size.width, size.height * 0.6);
      final glow = Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.15, -1.0),
          radius: 1.2,
          colors: [
            tokens.topGlowColor!.withOpacity(0.16),
            tokens.topGlowColor!.withOpacity(0.0),
          ],
        ).createShader(glowRect);
      canvas.drawRect(glowRect, glow);
      canvas.restore();
    }

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
      canvas.save();
      canvas.clipPath(outline);
      const barW = 6.0;
      // Neon glow: a blurred wider band behind the bar so the edge reads as
      // lit rather than painted (nightCarbon's cyan edge).
      if (tokens.accentBarGlow) {
        final glow = Paint()
          ..color = tokens.accentBarColor!.withOpacity(0.55)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
        canvas.drawRect(Rect.fromLTWH(0, 0, barW + 4, size.height), glow);
      }
      if (tokens.accentBarColor2 != null) {
        // Striped pit-marker / hazard-tape bar: alternating segments down
        // the strip.
        const seg = 9.0;
        var y = 0.0;
        var flip = false;
        while (y < size.height) {
          canvas.drawRect(
            Rect.fromLTWH(0, y, barW, seg),
            Paint()
              ..color = flip ? tokens.accentBarColor2! : tokens.accentBarColor!,
          );
          y += seg;
          flip = !flip;
        }
      } else {
        canvas.drawRect(Rect.fromLTWH(0, 0, barW, size.height),
            Paint()..color = tokens.accentBarColor!);
      }
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
        canvas.clipRect(
            Rect.fromLTRB(0, bandTop, size.width - stubWidth, bandBottom));
        final p = Paint()
          ..color = tokens.inkColor.withOpacity(0.10)
          ..strokeWidth = 8;
        for (double d = -size.height; d < size.width + size.height; d += 22) {
          canvas.drawLine(
              Offset(d, 0), Offset(d + size.height, size.height), p);
        }
        canvas.restore();
        return;
      case TicketBackground.chevronBand:
        // Vintage racing-ticket trim: two thin diagonal-stripe bands
        // hugging the top and bottom edges, leaving the body clear for
        // the headline and watermark. Mirrors the chevron-band pattern
        // in the City Cup / State Cup reference tickets.
        final p = Paint()
          ..color = tokens.inkColor.withOpacity(0.32)
          ..strokeWidth = 1.4;
        const bandHeight = 7.0;
        void paintBand(double top) {
          canvas.save();
          canvas.clipRect(
              Rect.fromLTWH(0, top, size.width - stubWidth, bandHeight));
          for (double x = -10; x < size.width; x += 4) {
            canvas.drawLine(
              Offset(x, top + bandHeight),
              Offset(x + bandHeight, top),
              p,
            );
          }
          canvas.restore();
        }
        paintBand(3);
        paintBand(size.height - bandHeight - 3);
        return;
      case TicketBackground.dotBand:
        // Repeating ink dots along the top and bottom edges — the Sage
        // Grand Prix garden-party trim. Pairs with star-flanked meta rows
        // when the foreground uses them.
        final p = Paint()
          ..color = tokens.inkColor.withOpacity(0.42)
          ..style = PaintingStyle.fill;
        const inset = 5.0;
        for (double x = 8; x < size.width - stubWidth - 4; x += 7) {
          canvas.drawCircle(Offset(x, inset), 1.3, p);
          canvas.drawCircle(Offset(x, size.height - inset), 1.3, p);
        }
        return;
      case TicketBackground.carbonWeave:
        // Fine 45° cross-hatch → woven carbon-fibre texture. Two faint line
        // sets, one each diagonal, clipped to the body so the stub stays bare.
        canvas.save();
        canvas.clipRect(Rect.fromLTWH(0, 0, size.width - stubWidth, size.height));
        final weave = Paint()
          ..color = tokens.inkColor.withOpacity(0.05)
          ..strokeWidth = 1;
        for (double d = -size.height; d < size.width; d += 6) {
          canvas.drawLine(
              Offset(d, 0), Offset(d + size.height, size.height), weave);
        }
        for (double d = 0; d < size.width + size.height; d += 6) {
          canvas.drawLine(
              Offset(d, 0), Offset(d - size.height, size.height), weave);
        }
        canvas.restore();
        return;
      case TicketBackground.telemetryGrid:
        // Square timing-screen grid.
        canvas.save();
        canvas.clipRect(Rect.fromLTWH(0, 0, size.width - stubWidth, size.height));
        final grid = Paint()
          ..color = tokens.inkColor.withOpacity(0.14)
          ..strokeWidth = 1;
        for (double x = 0; x < size.width - stubWidth; x += 20) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
        }
        for (double y = 0; y < size.height; y += 20) {
          canvas.drawLine(Offset(0, y), Offset(size.width - stubWidth, y), grid);
        }
        canvas.restore();
        return;
      case TicketBackground.asphaltSpeckle:
        // Scattered tarmac grit — a deterministic LCG so the speckle is
        // stable across repaints (no Random, which would shimmer).
        final w = (size.width - stubWidth).floor();
        final h = size.height.floor();
        if (w <= 0 || h <= 0) return;
        final light = Paint()..color = tokens.inkColor.withOpacity(0.06);
        final dark = Paint()..color = const Color(0x59000000);
        var seed = 20250705;
        int next() => seed = (seed * 1103515245 + 12345) & 0x7fffffff;
        for (int i = 0; i < 240; i++) {
          final x = next() % w;
          final y = next() % h;
          canvas.drawCircle(Offset(x.toDouble(), y.toDouble()), 0.8,
              i.isEven ? light : dark);
        }
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
      p.arcToPoint(Offset(stubX + n, 0),
          radius: const Radius.circular(_notchRadius), clockwise: false);
    }
    if (tear == TicketTear.cut) {
      p.lineTo(size.width - n, 0);
      p.arcToPoint(Offset(size.width, n),
          radius: const Radius.circular(_notchRadius), clockwise: false);
      p.lineTo(size.width, size.height - n);
      p.arcToPoint(Offset(size.width - n, size.height),
          radius: const Radius.circular(_notchRadius), clockwise: false);
    } else {
      p.lineTo(size.width - r, 0);
      p.arcToPoint(Offset(size.width, r),
          radius: const Radius.circular(_radius));
      p.lineTo(size.width, size.height - r);
      p.arcToPoint(Offset(size.width - r, size.height),
          radius: const Radius.circular(_radius));
    }
    if (stubX != null) {
      p.lineTo(stubX + n, size.height);
      p.arcToPoint(Offset(stubX - n, size.height),
          radius: const Radius.circular(_notchRadius), clockwise: false);
    }
    p.lineTo(r, size.height);
    p.arcToPoint(Offset(0, size.height - r),
        radius: const Radius.circular(_radius));
    p.lineTo(0, r);
    p.arcToPoint(const Offset(r, 0), radius: const Radius.circular(_radius));
    p.close();
    return p;
  }

  /// Path covering only the body half of a ghosted ticket. Mirrors the
  /// outline's notches at the perforation so the body edge meets the
  /// (translucent) stub edge cleanly — the arcs bulge INTO the body, the
  /// inverse of what `_outline` carves out.
  Path _bodyOnlyPath(Size size) {
    const r = _radius;
    const n = _notchRadius;
    final stubX = size.width - stubWidth;
    final p = Path()..moveTo(r, 0);
    p.lineTo(stubX - n, 0);
    p.arcToPoint(Offset(stubX, n),
        radius: const Radius.circular(_notchRadius), clockwise: false);
    p.lineTo(stubX, size.height - n);
    p.arcToPoint(Offset(stubX - n, size.height),
        radius: const Radius.circular(_notchRadius), clockwise: false);
    p.lineTo(r, size.height);
    p.arcToPoint(Offset(0, size.height - r),
        radius: const Radius.circular(_radius));
    p.lineTo(0, r);
    p.arcToPoint(const Offset(r, 0), radius: const Radius.circular(_radius));
    p.close();
    return p;
  }

  @override
  bool shouldRepaint(_TicketPainter old) =>
      old.tokens != tokens || old.stubWidth != stubWidth || old.tear != tear;
}

