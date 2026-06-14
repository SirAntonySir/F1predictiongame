import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

/// Renders [ticket] off-screen inside a branded frame and returns PNG bytes.
///
/// Mounts the widget into the app's root Overlay positioned far off-screen,
/// waits two frames (layout, then paint) and captures via
/// [RenderRepaintBoundary.toImage]. The overlay entry is always torn down in
/// the finally block so a capture failure can't leak a phantom widget.
///
/// [width] is the logical width of the frame (the visible card). The branded
/// header + footer adapt to that width. The actual exported pixel size is
/// `width * pixelRatio`.
Future<Uint8List> captureBrandedTicket({
  required BuildContext context,
  required Widget ticket,
  double width = 520,
  double pixelRatio = 3.0,
}) async {
  final repaintKey = GlobalKey();
  final overlay = Overlay.of(context, rootOverlay: true);
  final mediaQuery = MediaQuery.of(context);

  final entry = OverlayEntry(
    builder: (_) => Positioned(
      // Far off the visible area so the capture rig can never be tapped or
      // flash on screen during the two-frame wait.
      left: -99999,
      top: 0,
      child: Material(
        type: MaterialType.transparency,
        // Force textScaler 1.0 so accessibility settings on the device don't
        // change the exported image.
        child: MediaQuery(
          data: mediaQuery.copyWith(textScaler: const TextScaler.linear(1.0)),
          child: RepaintBoundary(
            key: repaintKey,
            child: _BrandedTicketFrame(width: width, child: ticket),
          ),
        ),
      ),
    ),
  );

  overlay.insert(entry);

  try {
    // First frame: lays out the inserted subtree. Second frame: ensures paint
    // has flushed before toImage() reads from the layer.
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;

    final boundary =
        repaintKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw StateError('Failed to encode ticket image as PNG');
      }
      return byteData.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  } finally {
    entry.remove();
  }
}

/// Capture + native share sheet. Bytes are handed to [Share] via
/// [XFile.fromData] so we don't need to touch the filesystem — share_plus
/// handles temp-file plumbing on platforms that require it.
Future<void> shareBrandedTicket({
  required BuildContext context,
  required Widget ticket,
  String fileName = 'f1pg-ticket.png',
  String? shareText,
  double width = 520,
  double pixelRatio = 3.0,
}) async {
  // Resolve the share-sheet anchor BEFORE the async gap. iPad requires a
  // non-zero rect in the source view's coordinate space to position the share
  // popover; on iPhone/Android it's harmless. Falling back to a 1x1 rect at
  // the screen centre keeps the call from throwing when no usable render
  // object is attached (e.g. share triggered from a non-rendered context).
  final origin = _shareOriginFrom(context);

  final bytes = await captureBrandedTicket(
    context: context,
    ticket: ticket,
    width: width,
    pixelRatio: pixelRatio,
  );
  await Share.shareXFiles(
    [
      XFile.fromData(
        bytes,
        mimeType: 'image/png',
        name: fileName,
      ),
    ],
    text: shareText,
    sharePositionOrigin: origin,
  );
}

Rect _shareOriginFrom(BuildContext context) {
  final box = context.findRenderObject();
  if (box is RenderBox && box.hasSize && box.attached) {
    return box.localToGlobal(Offset.zero) & box.size;
  }
  final mq = MediaQuery.maybeOf(context);
  final size = mq?.size ?? const Size(320, 568);
  return Rect.fromLTWH(size.width / 2, size.height / 2, 1, 1);
}

/// F1PG brand frame around the ticket so the exported image is self-
/// identifying. Private — callers go through the capture helpers above so the
/// framing stays consistent across every share entry point.
class _BrandedTicketFrame extends StatelessWidget {
  const _BrandedTicketFrame({required this.width, required this.child});

  final double width;
  final Widget child;

  static const _paper = Color(0xFFEFEAE0);
  static const _ink = Color(0xFF14110D);
  static const _mute = Color(0xFF6A655B);
  static const _accent = Color(0xFFE10600);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      color: _paper,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 18,
                decoration: BoxDecoration(
                  color: _accent,
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'F1PG',
                style: GoogleFonts.barlowCondensed(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2.6,
                  color: _ink,
                  height: 1.0,
                ),
              ),
              const Spacer(),
              Text(
                'PREDICTION GAME',
                style: GoogleFonts.barlowCondensed(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.8,
                  color: _mute,
                  height: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
          const SizedBox(height: 12),
          Text(
            'shared from the F1PG app',
            textAlign: TextAlign.center,
            style: GoogleFonts.barlowCondensed(
              fontSize: 9,
              fontWeight: FontWeight.w500,
              letterSpacing: 1.6,
              color: _mute,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}
