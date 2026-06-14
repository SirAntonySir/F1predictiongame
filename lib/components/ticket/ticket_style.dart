// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'ticket_ornament.dart';
import 'ticket_stub.dart';

/// A bundle of typographic + decorative choices for the paper-ticket chrome.
/// Each value maps to a [TicketStyleTokens] entry via [tokensFor].
enum TicketStyle { vintageStencil, posterSprint, darkBoardingPass }

/// Background pattern painted underneath the body content. Drawn by the
/// Rohling's painter.
enum TicketBackground { plain, linedVertical, diagonalStripeBand }

/// Resolved tokens for one [TicketStyle]. The Rohling pulls fonts and colours
/// from here so callers never construct a TextStyle directly.
class TicketStyleTokens {
  final TextStyle title;
  final TextStyle subtitle;
  final TextStyle meta;
  final TextStyle dataValue;
  final TextStyle dataLabel;
  final Color paperColor;
  final Color inkColor;
  final Color? accentBarColor;
  final TicketBackground background;
  final TicketStub defaultStub;
  final TicketOrnament defaultOrnament;
  final bool innerFrame;

  const TicketStyleTokens({
    required this.title,
    required this.subtitle,
    required this.meta,
    required this.dataValue,
    required this.dataLabel,
    required this.paperColor,
    required this.inkColor,
    required this.accentBarColor,
    required this.background,
    required this.defaultStub,
    required this.defaultOrnament,
    required this.innerFrame,
  });
}

const _cream = Color(0xFFF1DD95);
const _ink = Color(0xFF1B1206);
const _red = Color(0xFFE10600);

TicketStyleTokens tokensFor(TicketStyle s) {
  switch (s) {
    case TicketStyle.vintageStencil:
      return TicketStyleTokens(
        title: GoogleFonts.alfaSlabOne(fontSize: 44, height: 0.9, letterSpacing: -0.5, color: _ink),
        subtitle: GoogleFonts.ibmPlexMono(fontSize: 9, letterSpacing: 3, fontWeight: FontWeight.w700, color: _ink),
        meta: GoogleFonts.ibmPlexMono(fontSize: 9, letterSpacing: 2, fontWeight: FontWeight.w700, color: _ink),
        dataValue: GoogleFonts.alfaSlabOne(fontSize: 14, letterSpacing: 1, color: _ink),
        dataLabel: GoogleFonts.ibmPlexMono(fontSize: 9, letterSpacing: 2, fontWeight: FontWeight.w700, color: _ink),
        paperColor: _cream,
        inkColor: _ink,
        accentBarColor: null,
        background: TicketBackground.linedVertical,
        defaultStub: const TicketStub.admitOne(),
        defaultOrnament: TicketOrnament.crossedFlags,
        innerFrame: true,
      );
    case TicketStyle.posterSprint:
      return TicketStyleTokens(
        title: GoogleFonts.bebasNeue(fontSize: 56, height: 0.85, letterSpacing: 2, color: _ink),
        subtitle: GoogleFonts.ibmPlexMono(fontSize: 9, letterSpacing: 3, fontWeight: FontWeight.w700, color: _ink),
        meta: GoogleFonts.ibmPlexMono(fontSize: 9, letterSpacing: 2, fontWeight: FontWeight.w700, color: _ink),
        dataValue: GoogleFonts.anton(fontSize: 18, letterSpacing: 1, color: _ink),
        dataLabel: GoogleFonts.ibmPlexMono(fontSize: 9, letterSpacing: 2, fontWeight: FontWeight.w700, color: _ink),
        paperColor: _cream,
        inkColor: _ink,
        accentBarColor: null,
        background: TicketBackground.diagonalStripeBand,
        defaultStub: const TicketStub.repeatedTitle(),
        defaultOrnament: TicketOrnament.none,
        innerFrame: false,
      );
    case TicketStyle.darkBoardingPass:
      return TicketStyleTokens(
        title: GoogleFonts.oswald(fontSize: 36, height: 0.9, letterSpacing: 1, fontWeight: FontWeight.w700, color: _cream),
        subtitle: GoogleFonts.ibmPlexMono(fontSize: 9, letterSpacing: 3, fontWeight: FontWeight.w700, color: _cream),
        meta: GoogleFonts.ibmPlexMono(fontSize: 9, letterSpacing: 2, fontWeight: FontWeight.w700, color: _cream),
        dataValue: GoogleFonts.anton(fontSize: 17, letterSpacing: 1, color: _cream),
        dataLabel: GoogleFonts.ibmPlexMono(fontSize: 9, letterSpacing: 2, fontWeight: FontWeight.w700, color: _cream),
        paperColor: _ink,
        inkColor: _cream,
        accentBarColor: _red,
        background: TicketBackground.plain,
        defaultStub: const TicketStub.serialCode(),
        defaultOrnament: TicketOrnament.none,
        innerFrame: true,
      );
  }
}
