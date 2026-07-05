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
  // Dark trio — replaced the old muddy `darkBoardingPass`. Each is a proper
  // night-race skin with its own paper texture, accent bar, and ink.
  nightCarbon,
  pitWallTelemetry,
  asphaltStencil,
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
  // Dark-trio textures.
  carbonWeave,
  telemetryGrid,
  asphaltSpeckle,
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

  /// Vertical [top, bottom] gradient for the paper fill. When set, overrides
  /// the flat [paperColor] (which is still used as the ghosted-tear wash and
  /// as a fallback). Lets the dark variants fade from a lit top to a darker
  /// base instead of reading as a flat slab.
  final List<Color>? paperGradient;

  /// Colour of the "floodlit" radial glow bled from the top edge — the
  /// stadium-lights wash on [nightCarbon]. Painted at low opacity inside the
  /// ticket outline. Null = no glow.
  final Color? topGlowColor;

  /// Second colour for a striped accent bar. When set, the left accent bar is
  /// drawn as alternating [accentBarColor]/[accentBarColor2] segments (pit
  /// marker / hazard tape) instead of a solid strip.
  final Color? accentBarColor2;

  /// When true, the left accent bar gets a soft outward glow — the neon edge
  /// on [nightCarbon].
  final bool accentBarGlow;

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
    this.paperGradient,
    this.topGlowColor,
    this.accentBarColor2,
    this.accentBarGlow = false,
  });
}

const _cream = Color(0xFFF1DD95);
const _ink = Color(0xFF1B1206);

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

// Dark trio — night-race skins that replaced the old brown boarding pass.
const _carbonTop = Color(0xFF13161B);
const _carbonBase = Color(0xFF0A0C0F);
const _carbonInk = Color(0xFFF4F2EC);
const _carbonDim = Color(0xFF8FA3AD);
const _cyan = Color(0xFF37E7FF);

const _navyTop = Color(0xFF0C1626);
const _navyBase = Color(0xFF0A111D);
const _amber = Color(0xFFFFCF6B);
const _navyInk = Color(0xFF6E8CB0);
const _timingRed = Color(0xFFFF5C3A);
const _timingRedDeep = Color(0xFFB83217);

const _asphaltTop = Color(0xFF242422);
const _asphaltBase = Color(0xFF171715);
const _asphaltInk = Color(0xFFEDEDEA);
const _asphaltDim = Color(0xFF9A9992);
const _vermilion = Color(0xFFFF4326);

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
    // ── Dark Trio ────────────────────────────────────────────────────────
    // Replaced the old muddy brown `darkBoardingPass`. Three night-race
    // skins, each with its own paper texture, accent treatment, and ink.

    case TicketStyle.nightCarbon:
      // Floodlit night GP: carbon-weave black paper, a cyan stadium-light
      // glow bleeding from the top edge, and a glowing neon accent bar.
      return TicketStyleTokens(
        title: GoogleFonts.oswald(fontSize: 30, height: 0.88, letterSpacing: 1, fontWeight: FontWeight.w700, color: _carbonInk),
        subtitle: GoogleFonts.ibmPlexMono(fontSize: 9, letterSpacing: 3, fontWeight: FontWeight.w700, color: _carbonDim),
        meta: GoogleFonts.ibmPlexMono(fontSize: 9, letterSpacing: 2, fontWeight: FontWeight.w700, color: _carbonDim),
        dataValue: const TextStyle(fontFamily: 'Stampete', fontSize: 18, letterSpacing: 1, color: _carbonInk),
        dataLabel: GoogleFonts.ibmPlexMono(fontSize: 9, letterSpacing: 2, fontWeight: FontWeight.w700, color: _carbonDim),
        paperColor: _carbonBase,
        inkColor: _carbonInk,
        accentBarColor: _cyan,
        background: TicketBackground.carbonWeave,
        defaultStub: const TicketStub.serialCode(),
        defaultOrnament: TicketOrnament.none,
        innerFrame: true,
        defaultIllustrationAsset: 'assets/ornament_car.svg',
        paperGradient: const [_carbonTop, _carbonBase],
        topGlowColor: _cyan,
        accentBarGlow: true,
      );

    case TicketStyle.pitWallTelemetry:
      // Pit-wall timing screen: deep navy paper under a faint data grid,
      // amber readout numerals, and a red pit-marker striped bar.
      return TicketStyleTokens(
        title: GoogleFonts.oswald(fontSize: 30, height: 0.88, letterSpacing: 1.5, fontWeight: FontWeight.w600, color: _carbonInk),
        subtitle: GoogleFonts.ibmPlexMono(fontSize: 9, letterSpacing: 3, fontWeight: FontWeight.w700, color: _navyInk),
        meta: GoogleFonts.ibmPlexMono(fontSize: 9, letterSpacing: 2, fontWeight: FontWeight.w700, color: _navyInk),
        dataValue: const TextStyle(fontFamily: 'Stampete', fontSize: 18, letterSpacing: 1, color: _amber),
        dataLabel: GoogleFonts.ibmPlexMono(fontSize: 9, letterSpacing: 2, fontWeight: FontWeight.w700, color: _navyInk),
        paperColor: _navyBase,
        inkColor: _navyInk,
        accentBarColor: _timingRed,
        background: TicketBackground.telemetryGrid,
        defaultStub: const TicketStub.serialCode(),
        defaultOrnament: TicketOrnament.none,
        innerFrame: false,
        defaultIllustrationAsset: 'assets/ornament_car.svg',
        paperGradient: const [_navyTop, _navyBase],
        accentBarColor2: _timingRedDeep,
      );

    case TicketStyle.asphaltStencil:
      // Trackside tarmac: speckled asphalt paper, a heavy Anton stencil
      // headline, and a vermilion/black hazard-tape accent bar.
      return TicketStyleTokens(
        title: GoogleFonts.anton(fontSize: 33, height: 0.9, letterSpacing: 0.5, color: _asphaltInk),
        subtitle: GoogleFonts.ibmPlexMono(fontSize: 9, letterSpacing: 3, fontWeight: FontWeight.w700, color: _asphaltDim),
        meta: GoogleFonts.ibmPlexMono(fontSize: 9, letterSpacing: 2, fontWeight: FontWeight.w700, color: _asphaltDim),
        dataValue: const TextStyle(fontFamily: 'Stampete', fontSize: 18, letterSpacing: 1, color: _asphaltInk),
        dataLabel: GoogleFonts.ibmPlexMono(fontSize: 9, letterSpacing: 2, fontWeight: FontWeight.w700, color: _asphaltDim),
        paperColor: _asphaltBase,
        inkColor: _asphaltInk,
        accentBarColor: _vermilion,
        background: TicketBackground.asphaltSpeckle,
        defaultStub: const TicketStub.serialCode(),
        defaultOrnament: TicketOrnament.none,
        innerFrame: false,
        defaultIllustrationAsset: 'assets/ornament_car.svg',
        paperGradient: const [_asphaltTop, _asphaltBase],
        accentBarColor2: _asphaltBase,
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
