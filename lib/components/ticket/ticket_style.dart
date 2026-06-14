// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'ticket_ornament.dart';
import 'ticket_stub.dart';

/// A bundle of typographic + decorative choices for the paper-ticket chrome.
/// Each value maps to a [TicketStyleTokens] entry via [tokensFor].
enum TicketStyle {
  vintageStencil,
  posterSprint,
  darkBoardingPass,
  vintageMustardCityCup,
  vintageSageGrandPrix,
  vintageOliveStateCup,
  vintageRoseChampionship,
}

/// Background pattern painted underneath the body content. Drawn by the
/// Rohling's painter.
enum TicketBackground {
  plain,
  linedVertical,
  diagonalStripeBand,
  chevronBand,
  dotBand,
}

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
  /// Optional asset path used as the watermark illustration when the caller
  /// doesn't pass one. Lets a variant declare its signature silhouette
  /// (car / checkered flag / crown) so the same artwork shows up across
  /// the souvenir wallet, home pick card, dev preview, and shared PNGs.
  /// Null means fall back to the generic round-keyed car silhouette set.
  final String? defaultIllustrationAsset;
  /// Optional italic script accent rendered immediately below the title
  /// ("Grand Prix" / "Racing" / "Championship") — the cursive flourish in
  /// the vintage racing-ticket reference. When null, the title stands
  /// alone (and [TicketRohling]'s caller appends " GP" as a suffix
  /// instead).
  final TextStyle? scriptAccent;

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
    this.defaultIllustrationAsset,
    this.scriptAccent,
  });
}

const _cream = Color(0xFFF1DD95);
const _ink = Color(0xFF1B1206);
const _red = Color(0xFFE10600);

// Vintage racing palette — each variant gets its own paper + ink pair so the
// rotation through them feels like flipping through a real ticket book.
const _mustard = Color(0xFFE8B940);
const _mustardInk = Color(0xFF1B1306);
const _sage = Color(0xFFBFD5B0);
const _sageInk = Color(0xFF1F2A1A);
const _olive = Color(0xFF4A5028);
const _oliveCream = Color(0xFFF1E6C8);
const _gold = Color(0xFFE8B940);
const _rose = Color(0xFFE9B5B5);
const _roseInk = Color(0xFF2B1212);

TicketStyleTokens tokensFor(TicketStyle s) {
  switch (s) {
    case TicketStyle.vintageStencil:
      return TicketStyleTokens(
        title: GoogleFonts.alfaSlabOne(fontSize: 28, height: 0.9, letterSpacing: -0.5, color: _ink),
        subtitle: GoogleFonts.ibmPlexMono(fontSize: 9, letterSpacing: 3, fontWeight: FontWeight.w700, color: _ink),
        meta: GoogleFonts.ibmPlexMono(fontSize: 9, letterSpacing: 2, fontWeight: FontWeight.w700, color: _ink),
        // Stampete on driver codes + points gives the picks a rubber-stamped
        // paper-ticket feel across every variant (overridden per-preset where
        // the font-size needs to differ).
        dataValue: const TextStyle(fontFamily: 'Stampete', fontSize: 18, letterSpacing: 1, color: _ink),
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
        title: GoogleFonts.bebasNeue(fontSize: 42, height: 0.85, letterSpacing: 2, color: _ink),
        subtitle: GoogleFonts.ibmPlexMono(fontSize: 9, letterSpacing: 3, fontWeight: FontWeight.w700, color: _ink),
        meta: GoogleFonts.ibmPlexMono(fontSize: 9, letterSpacing: 2, fontWeight: FontWeight.w700, color: _ink),
        dataValue: const TextStyle(fontFamily: 'Stampete', fontSize: 18, letterSpacing: 1, color: _ink),
        dataLabel: GoogleFonts.ibmPlexMono(fontSize: 9, letterSpacing: 2, fontWeight: FontWeight.w700, color: _ink),
        paperColor: _cream,
        inkColor: _ink,
        accentBarColor: null,
        // Plain background lets the car silhouette + circuit watermarks
        // breathe — the diagonal stripe band fought them for attention.
        background: TicketBackground.plain,
        defaultStub: const TicketStub.repeatedTitle(),
        defaultOrnament: TicketOrnament.none,
        innerFrame: false,
      );
    case TicketStyle.darkBoardingPass:
      return TicketStyleTokens(
        title: GoogleFonts.oswald(fontSize: 28, height: 0.9, letterSpacing: 1, fontWeight: FontWeight.w700, color: _cream),
        subtitle: GoogleFonts.ibmPlexMono(fontSize: 9, letterSpacing: 3, fontWeight: FontWeight.w700, color: _cream),
        meta: GoogleFonts.ibmPlexMono(fontSize: 9, letterSpacing: 2, fontWeight: FontWeight.w700, color: _cream),
        dataValue: const TextStyle(fontFamily: 'Stampete', fontSize: 18, letterSpacing: 1, color: _cream),
        dataLabel: GoogleFonts.ibmPlexMono(fontSize: 9, letterSpacing: 2, fontWeight: FontWeight.w700, color: _cream),
        paperColor: _ink,
        inkColor: _cream,
        accentBarColor: _red,
        background: TicketBackground.plain,
        defaultStub: const TicketStub.serialCode(),
        defaultOrnament: TicketOrnament.none,
        innerFrame: true,
      );

    // ── Vintage Racing Series ────────────────────────────────────────────
    // Four siblings sharing a chunky slab/serif headline, monospace meta,
    // and rubber-stamped data row, but each on its own paper + ink + trim
    // so the rotation through them reads like a real vintage ticket book.

    case TicketStyle.vintageMustardCityCup:
      // The "primary" vintage flavour: mustard yellow paper, chevron racing
      // trim top/bottom, Alfa Slab One headline — the closest match to the
      // dominant ticket in the City Cup reference sheet.
      return TicketStyleTokens(
        title: GoogleFonts.alfaSlabOne(fontSize: 30, height: 0.9, letterSpacing: -0.5, color: _mustardInk),
        subtitle: GoogleFonts.ibmPlexMono(fontSize: 9, letterSpacing: 3, fontWeight: FontWeight.w700, color: _mustardInk),
        meta: GoogleFonts.ibmPlexMono(fontSize: 9, letterSpacing: 2, fontWeight: FontWeight.w700, color: _mustardInk),
        dataValue: const TextStyle(fontFamily: 'Stampete', fontSize: 18, letterSpacing: 1, color: _mustardInk),
        dataLabel: GoogleFonts.ibmPlexMono(fontSize: 9, letterSpacing: 2, fontWeight: FontWeight.w700, color: _mustardInk),
        paperColor: _mustard,
        inkColor: _mustardInk,
        accentBarColor: null,
        background: TicketBackground.chevronBand,
        defaultStub: const TicketStub.admitOne(),
        // Race-car silhouette ornament — pulled from the user-provided
        // ornament_car.svg, the dominant motif in the City Cup reference.
        defaultOrnament: TicketOrnament.car,
        innerFrame: true,
        // Same car silhouette as the ornament, blown up as the body
        // watermark so the variant reads consistently at both scales.
        defaultIllustrationAsset: 'assets/ornament_car.svg',
        scriptAccent: GoogleFonts.yellowtail(
          fontSize: 24,
          color: const Color(0xFFB33A1A),
          height: 1.0,
        ),
      );

    case TicketStyle.vintageSageGrandPrix:
      // Pale-mint paper, Bowlby One SC display (rounded geometric slab),
      // dot-band trim, trophy ornament. The "garden party at the GP"
      // mood from the sage row of the reference sheet.
      return TicketStyleTokens(
        title: GoogleFonts.bowlbyOneSc(fontSize: 28, height: 0.9, letterSpacing: 0.5, color: _sageInk),
        subtitle: GoogleFonts.ibmPlexMono(fontSize: 9, letterSpacing: 3, fontWeight: FontWeight.w700, color: _sageInk),
        meta: GoogleFonts.ibmPlexMono(fontSize: 9, letterSpacing: 2, fontWeight: FontWeight.w700, color: _sageInk),
        dataValue: const TextStyle(fontFamily: 'Stampete', fontSize: 18, letterSpacing: 1, color: _sageInk),
        dataLabel: GoogleFonts.ibmPlexMono(fontSize: 9, letterSpacing: 2, fontWeight: FontWeight.w700, color: _sageInk),
        paperColor: _sage,
        inkColor: _sageInk,
        accentBarColor: null,
        background: TicketBackground.dotBand,
        defaultStub: const TicketStub.admitOne(),
        defaultOrnament: TicketOrnament.trophy,
        innerFrame: true,
        // Sage has no bespoke watermark of its own; reuse the car silhouette
        // so the body still gets a vintage racing motif behind it.
        defaultIllustrationAsset: 'assets/ornament_car.svg',
        scriptAccent: GoogleFonts.yellowtail(
          fontSize: 22,
          color: const Color(0xFF7A1F23),
          height: 1.0,
        ),
      );

    case TicketStyle.vintageOliveStateCup:
      // The dark sibling: olive paper, cream ink, IM Fell English SC
      // broadsheet headline, gold accent bar, waving checkered-flag
      // ornament. Pair to darkBoardingPass but in the State Cup family.
      return TicketStyleTokens(
        title: GoogleFonts.imFellEnglishSc(fontSize: 30, height: 0.9, letterSpacing: 0.5, fontWeight: FontWeight.w700, color: _oliveCream),
        subtitle: GoogleFonts.ibmPlexMono(fontSize: 9, letterSpacing: 3, fontWeight: FontWeight.w700, color: _oliveCream),
        meta: GoogleFonts.ibmPlexMono(fontSize: 9, letterSpacing: 2, fontWeight: FontWeight.w700, color: _oliveCream),
        dataValue: const TextStyle(fontFamily: 'Stampete', fontSize: 17, letterSpacing: 1, color: _oliveCream),
        dataLabel: GoogleFonts.ibmPlexMono(fontSize: 9, letterSpacing: 2, fontWeight: FontWeight.w700, color: _oliveCream),
        paperColor: _olive,
        inkColor: _oliveCream,
        accentBarColor: _gold,
        background: TicketBackground.chevronBand,
        defaultStub: const TicketStub.admitOne(),
        defaultOrnament: TicketOrnament.checkeredFlag,
        innerFrame: true,
        defaultIllustrationAsset: 'assets/ornament_checkered.svg',
        scriptAccent: GoogleFonts.yellowtail(
          fontSize: 22,
          color: _gold,
          height: 1.0,
        ),
      );

    case TicketStyle.vintageRoseChampionship:
      // Hippodrome-formal: dusty pink paper, Ultra ultra-heavy slab,
      // crown + laurel ornament, fine line-grid background. The most
      // "ceremonial" of the four.
      return TicketStyleTokens(
        title: GoogleFonts.ultra(fontSize: 24, height: 0.95, letterSpacing: -0.5, color: _roseInk),
        subtitle: GoogleFonts.ibmPlexMono(fontSize: 9, letterSpacing: 3, fontWeight: FontWeight.w700, color: _roseInk),
        meta: GoogleFonts.ibmPlexMono(fontSize: 9, letterSpacing: 2, fontWeight: FontWeight.w700, color: _roseInk),
        dataValue: const TextStyle(fontFamily: 'Stampete', fontSize: 18, letterSpacing: 1, color: _roseInk),
        dataLabel: GoogleFonts.ibmPlexMono(fontSize: 9, letterSpacing: 2, fontWeight: FontWeight.w700, color: _roseInk),
        paperColor: _rose,
        inkColor: _roseInk,
        accentBarColor: null,
        background: TicketBackground.linedVertical,
        defaultStub: const TicketStub.admitOne(),
        defaultOrnament: TicketOrnament.crown,
        innerFrame: false,
        defaultIllustrationAsset: 'assets/ornament_crown.svg',
        scriptAccent: GoogleFonts.yellowtail(
          fontSize: 26,
          color: const Color(0xFF7A1F23),
          height: 1.0,
        ),
      );
  }
}
