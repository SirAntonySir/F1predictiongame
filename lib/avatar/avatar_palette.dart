import 'package:flutter/material.dart';

import '../components/painted_splash.dart';

/// Recolor engine for the "rainbow master" avatar artwork.
///
/// Port of avatar-engine-handoff/teamskin.py. The master SVG encodes each
/// semantic region as a distinct hue band (red chest, orange sleeves, …);
/// desaturated or very dark colors are line art / visor and are never
/// touched. Recoloring classifies every color by hue bin and applies a
/// per-region operation that preserves the master's shading ladder.
///
/// Hues are stored as fractions (0..1, like teamskin.py) so the tuned
/// constants can be compared against the Python original verbatim.

/// The available artwork poses. All poses share the same rainbow region
/// encoding, so one config recolors any of them.
enum AvatarPose {
  pose1('Victory', 'assets/avatar/pose1.svg', hasBakedIcons: true),
  pose2('Arms crossed', 'assets/avatar/pose2.svg', hasBakedIcons: true),
  pose3('Kneeling', 'assets/avatar/pose3.svg', hasBakedIcons: true);

  final String label;
  final String asset;

  /// Whether launcher-icon PNGs for this pose are baked into the app and
  /// registered natively (Info.plist / AndroidManifest). Poses without baked
  /// icons are splash/builder-only and don't appear in the icon gallery.
  final bool hasBakedIcons;
  const AvatarPose(this.label, this.asset, {this.hasBakedIcons = false});

  static AvatarPose byName(String? name) => AvatarPose.values
      .firstWhere((p) => p.name == name, orElse: () => AvatarPose.pose1);
}

enum AvatarRegion {
  helmet('Helmet', 0.50),
  helmetStripe('Helmet stripe', 0.12),
  chest('Chest', 0.00),
  sleeves('Sleeves', 0.058),
  accents('Collar & belt', 0.20),
  gloves('Gloves', 0.90),
  legs('Legs', 0.33),
  stripes('Side stripes', 0.75),
  boots('Boots', 0.60);

  final String label;

  /// Nominal hue (0..1 fraction) of this region in the rainbow master —
  /// what the region looks like when a preset leaves it untouched.
  final double masterHue;
  const AvatarRegion(this.label, this.masterHue);

  /// Swatch for a region under [ops]: the op's output on a nominal
  /// mid-tone shade, or the master's own color when the region is
  /// untouched.
  Color swatchFor(Map<AvatarRegion, RegionOp> ops) =>
      ops[this]?.swatch ??
      HSVColor.fromAHSV(1, masterHue * 360, 0.9, 0.85).toColor();
}

/// Line-art guard: below these thresholds a color is ink/visor/shadow and
/// must never be recolored, no matter the hue.
const _minSaturation = 0.15;
const _minValue = 0.22;

/// Hue-bin classification of a master color. Returns null for line art.
AvatarRegion? classifyMasterColor(HSVColor c) {
  if (c.saturation < _minSaturation || c.value < _minValue) return null;
  final h = c.hue / 360;
  if (h >= 0.97 || h < 0.028) return AvatarRegion.chest; // red
  if (h < 0.088) return AvatarRegion.sleeves; // orange
  if (h < 0.155) return AvatarRegion.helmetStripe; // yellow
  if (h < 0.243) return AvatarRegion.accents; // lime
  if (h < 0.400) return AvatarRegion.legs; // green
  if (h < 0.548) return AvatarRegion.helmet; // teal
  if (h < 0.660) return AvatarRegion.boots; // blue
  if (h < 0.830) return AvatarRegion.stripes; // purple
  return AvatarRegion.gloves; // magenta
}

/// Fraction of the figure's height below which no genuine helmet exists — the
/// helmet always sits at the top. Poses whose leg/thigh shading strays into
/// the teal "helmet" hue band (pose 3's kneeling crop is the offender) would
/// otherwise follow the helmet color; anything teal-classified below this line
/// is re-read as leg shading. Measured with margin: real helmets bottom out
/// around 0.29 of figure height, the lowest stray thigh streak sits at 0.53.
const double kHelmetMaxYFrac = 0.40;

/// Region for a master color with the vertical-position override applied.
/// [belowHelmet] is true when the path lies below [kHelmetMaxYFrac] of the
/// figure — where a teal color is leg shading, not a helmet.
AvatarRegion? regionForColor(HSVColor c, {required bool belowHelmet}) {
  final region = classifyMasterColor(c);
  if (belowHelmet && region == AvatarRegion.helmet) return AvatarRegion.legs;
  return region;
}

/// A per-region recolor operation. Applied to every master color classified
/// into the region; the master's value (shade) ladder carries the shading.
sealed class RegionOp {
  const RegionOp();
  HSVColor apply(HSVColor c);

  /// The color this op produces on a nominal mid-tone master shade —
  /// what a swatch in the UI should show for the region.
  Color get swatch => apply(const HSVColor.fromAHSV(1, 0, 0.9, 0.85)).toColor();
}

/// Shift the region to a target hue, keeping the shade ladder.
/// [targetHue] is a 0..1 fraction; [sScale]/[vScale] scale the master's
/// saturation/value (vScale is this port's fix for the handoff's known
/// "region brightness inherited from master" issue).
class HueOp extends RegionOp {
  final double targetHue;
  final double sScale;
  final double vScale;
  const HueOp(this.targetHue, this.sScale, [this.vScale = 1.0]);

  @override
  HSVColor apply(HSVColor c) => HSVColor.fromAHSV(
        c.alpha,
        (targetHue * 360) % 360,
        (c.saturation * sScale).clamp(0.0, 1.0),
        (c.value * vScale).clamp(0.0, 1.0),
      );

  @override
  Color get swatch =>
      apply(HSVColor.fromAHSV(1, targetHue * 360, 0.9, 0.85)).toColor();
}

/// Remap the region onto a neutral (white/silver/black) ladder:
/// s is fixed, v' = vA + vB * v.
class NeutralOp extends RegionOp {
  final double sFixed;
  final double vA;
  final double vB;
  const NeutralOp(this.sFixed, this.vA, this.vB);

  @override
  HSVColor apply(HSVColor c) => HSVColor.fromAHSV(
        c.alpha,
        c.hue,
        sFixed.clamp(0.0, 1.0),
        (vA + vB * c.value).clamp(0.0, 1.0),
      );
}

/// Derive the op for a user-picked color: gray-ish picks become a neutral
/// ladder anchored near the picked brightness, saturated picks become a hue
/// shift scaled relative to the master's nominal mid-tone (s≈0.9, v≈0.85).
RegionOp opForPickedColor(Color picked) {
  final c = HSVColor.fromColor(picked);
  if (c.saturation < _minSaturation) {
    // Anchor the ladder so a nominal mid-tone (v≈0.85) lands on the picked
    // brightness; the spread shrinks toward black so dark suits keep only
    // subtle highlights (teamskin: white 0.55/0.45, silver 0.42/0.50,
    // black 0.03/0.38).
    final spread = 0.25 + 0.2 * c.value;
    final base = (c.value - spread * 0.85).clamp(0.0, 1.0);
    return NeutralOp(c.saturation, base, spread);
  }
  return HueOp(
    c.hue / 360,
    (c.saturation / 0.9).clamp(0.0, 1.5),
    (c.value / 0.85).clamp(0.2, 1.2),
  );
}

/// A named, complete livery: one op per region.
class AvatarPreset {
  final String id;
  final String name;
  final Map<AvatarRegion, RegionOp> ops;
  const AvatarPreset(this.id, this.name, this.ops);

  /// Chip color for the preset row in the builder.
  Color get swatch => ops[AvatarRegion.chest]!.swatch;
}

// Palette constants ported from teamskin.py (hue fractions verbatim), plus
// hues derived from the curated team colors in theme/team_colors.dart for
// the liveries teamskin.py never defined.
// Colorways track the eleven 2026 grid suits, but display names are
// fictional — shipping real team names is a trademark problem (see handoff
// legal notes); the colorways speak for themselves.
const _red = 0.995;
const _papaya = 0.058;
const _petronas = 0.49;
const _brandRed = 0.0044; // BrandColors.accent #E10600
const _navy = 0.62; // deep racing navy (also royal blue at full value)
const _yellow = 0.145;
const _astonGreen = 0.44; // #229971
const _lime = 0.177; // #CEDC00
const _alpineBlue = 0.547; // #0093CC
const _pink = 0.884; // #FD4BC7
const _skyBlue = 0.563; // #64C4FF
const _neonGreen = 0.333; // #52E252
const _audiRed = 0.965; // #F50537

const avatarPresets = <AvatarPreset>[
  AvatarPreset('undercut', 'Undercut', {
    AvatarRegion.helmet: HueOp(_brandRed, 1.0),
    AvatarRegion.helmetStripe: NeutralOp(0.03, 0.55, 0.45),
    AvatarRegion.chest: NeutralOp(0.06, 0.03, 0.38),
    AvatarRegion.sleeves: NeutralOp(0.06, 0.03, 0.38),
    AvatarRegion.accents: HueOp(_brandRed, 1.0),
    AvatarRegion.gloves: NeutralOp(0.06, 0.03, 0.38),
    AvatarRegion.legs: NeutralOp(0.06, 0.03, 0.38),
    AvatarRegion.stripes: HueOp(_brandRed, 1.0),
    AvatarRegion.boots: NeutralOp(0.06, 0.02, 0.35),
  }),
  AvatarPreset('rosso', 'Rosso', {
    // Red suit, white collar and side stripes, red boots.
    AvatarRegion.chest: HueOp(_red, 1.0),
    AvatarRegion.sleeves: HueOp(_red, 1.0),
    AvatarRegion.legs: HueOp(_red, 1.0),
    AvatarRegion.gloves: HueOp(_red, 1.0),
    AvatarRegion.helmet: HueOp(_red, 1.0),
    AvatarRegion.accents: NeutralOp(0.03, 0.55, 0.45),
    AvatarRegion.stripes: NeutralOp(0.03, 0.55, 0.45),
    AvatarRegion.helmetStripe: NeutralOp(0.03, 0.55, 0.45),
    AvatarRegion.boots: HueOp(_red, 1.0, 0.85),
  }),
  AvatarPreset('papaya', 'Papaya', {
    // Papaya suit head to toe, anthracite collar and side stripes.
    AvatarRegion.chest: HueOp(_papaya, 1.0),
    AvatarRegion.sleeves: HueOp(_papaya, 1.0),
    AvatarRegion.helmet: HueOp(_papaya, 1.0),
    AvatarRegion.legs: HueOp(_papaya, 1.0),
    AvatarRegion.gloves: NeutralOp(0.07, 0.03, 0.38),
    AvatarRegion.boots: NeutralOp(0.07, 0.02, 0.35),
    AvatarRegion.accents: NeutralOp(0.07, 0.06, 0.42),
    AvatarRegion.stripes: NeutralOp(0.07, 0.06, 0.42),
    AvatarRegion.helmetStripe: NeutralOp(0.08, 0.05, 0.40),
  }),
  AvatarPreset('silver', 'Silver', {
    // Black suit with silver sleeves, teal piping, bright blue boots.
    AvatarRegion.chest: NeutralOp(0.06, 0.03, 0.38),
    AvatarRegion.sleeves: NeutralOp(0.05, 0.42, 0.50),
    AvatarRegion.helmet: NeutralOp(0.05, 0.42, 0.50),
    AvatarRegion.legs: NeutralOp(0.06, 0.03, 0.38),
    AvatarRegion.gloves: NeutralOp(0.06, 0.03, 0.38),
    AvatarRegion.boots: HueOp(_skyBlue, 1.0),
    AvatarRegion.accents: HueOp(_petronas, 0.95),
    AvatarRegion.stripes: HueOp(_petronas, 0.95),
    AvatarRegion.helmetStripe: HueOp(_petronas, 0.95),
  }),
  AvatarPreset('bolt', 'Bolt', {
    // Navy suit, red collar & belt, yellow side stripes, silver helmet stripe.
    AvatarRegion.chest: HueOp(_navy, 0.95, 0.5),
    AvatarRegion.sleeves: HueOp(_navy, 0.95, 0.5),
    AvatarRegion.legs: HueOp(_navy, 0.95, 0.5),
    AvatarRegion.gloves: HueOp(_navy, 0.95, 0.5),
    AvatarRegion.helmet: HueOp(_navy, 0.95, 0.5),
    AvatarRegion.boots: HueOp(_navy, 0.9, 0.4),
    AvatarRegion.accents: HueOp(_red, 1.0),
    AvatarRegion.stripes: HueOp(_yellow, 1.0),
    AvatarRegion.helmetStripe: NeutralOp(0.04, 0.35, 0.45),
  }),
  AvatarPreset('verde', 'Verde', {
    // Racing green suit, lime piping, black side stripes and boots.
    AvatarRegion.chest: HueOp(_astonGreen, 1.0, 0.85),
    AvatarRegion.sleeves: HueOp(_astonGreen, 1.0, 0.85),
    AvatarRegion.legs: HueOp(_astonGreen, 1.0, 0.85),
    AvatarRegion.gloves: HueOp(_astonGreen, 1.0, 0.85),
    AvatarRegion.helmet: HueOp(_astonGreen, 1.0, 0.85),
    AvatarRegion.accents: HueOp(_lime, 1.0),
    AvatarRegion.stripes: NeutralOp(0.06, 0.03, 0.38),
    AvatarRegion.helmetStripe: HueOp(_lime, 1.0),
    AvatarRegion.boots: NeutralOp(0.08, 0.02, 0.40),
  }),
  AvatarPreset('azur', 'Azur', {
    // Pink top over navy sleeves and legs, bright blue boots.
    AvatarRegion.chest: HueOp(_pink, 1.0),
    AvatarRegion.sleeves: HueOp(_navy, 0.95, 0.5),
    AvatarRegion.legs: HueOp(_navy, 0.95, 0.5),
    AvatarRegion.gloves: HueOp(_navy, 0.95, 0.5),
    AvatarRegion.helmet: HueOp(_pink, 1.0),
    AvatarRegion.accents: HueOp(_pink, 1.0),
    AvatarRegion.stripes: HueOp(_pink, 1.0),
    AvatarRegion.helmetStripe: HueOp(_navy, 0.95, 0.5),
    AvatarRegion.boots: HueOp(_alpineBlue, 1.0),
  }),
  AvatarPreset('atlantic', 'Atlantic', {
    // White suit with royal-blue side stripes, navy cuffs.
    AvatarRegion.chest: NeutralOp(0.03, 0.55, 0.45),
    AvatarRegion.sleeves: NeutralOp(0.03, 0.55, 0.45),
    AvatarRegion.helmet: NeutralOp(0.03, 0.55, 0.45),
    AvatarRegion.legs: NeutralOp(0.03, 0.55, 0.45),
    AvatarRegion.gloves: HueOp(_navy, 0.95, 0.5),
    AvatarRegion.boots: NeutralOp(0.03, 0.45, 0.45),
    AvatarRegion.accents: HueOp(_navy, 1.0),
    AvatarRegion.stripes: HueOp(_navy, 1.0),
    AvatarRegion.helmetStripe: HueOp(_navy, 1.0),
  }),
  AvatarPreset('frost', 'Frost', {
    // White suit, royal-blue sleeves, neon-green piping.
    AvatarRegion.chest: NeutralOp(0.03, 0.55, 0.45),
    AvatarRegion.sleeves: HueOp(_navy, 1.0),
    AvatarRegion.legs: NeutralOp(0.03, 0.55, 0.45),
    AvatarRegion.helmet: NeutralOp(0.03, 0.55, 0.45),
    AvatarRegion.gloves: HueOp(_navy, 0.95, 0.5),
    AvatarRegion.accents: HueOp(_neonGreen, 1.0),
    AvatarRegion.stripes: HueOp(_navy, 1.0),
    AvatarRegion.helmetStripe: HueOp(_neonGreen, 1.0),
    AvatarRegion.boots: NeutralOp(0.03, 0.45, 0.45),
  }),
  AvatarPreset('ivory', 'Ivory', {
    // White sleeves over a black chest and legs, red details.
    AvatarRegion.chest: NeutralOp(0.06, 0.03, 0.38),
    AvatarRegion.sleeves: NeutralOp(0.03, 0.55, 0.45),
    AvatarRegion.helmet: NeutralOp(0.03, 0.55, 0.45),
    AvatarRegion.legs: NeutralOp(0.06, 0.03, 0.38),
    AvatarRegion.gloves: NeutralOp(0.06, 0.03, 0.38),
    AvatarRegion.boots: NeutralOp(0.06, 0.02, 0.35),
    AvatarRegion.accents: HueOp(_red, 1.0),
    AvatarRegion.stripes: NeutralOp(0.03, 0.55, 0.45),
    AvatarRegion.helmetStripe: HueOp(_red, 1.0),
  }),
  AvatarPreset('titan', 'Titan', {
    // Black top over titanium legs, red helmet and details.
    AvatarRegion.chest: NeutralOp(0.06, 0.03, 0.38),
    AvatarRegion.sleeves: NeutralOp(0.06, 0.03, 0.38),
    AvatarRegion.helmet: HueOp(_audiRed, 1.0),
    AvatarRegion.legs: NeutralOp(0.05, 0.30, 0.45),
    AvatarRegion.gloves: NeutralOp(0.06, 0.03, 0.38),
    AvatarRegion.boots: NeutralOp(0.05, 0.10, 0.40),
    AvatarRegion.accents: HueOp(_audiRed, 1.0),
    AvatarRegion.stripes: NeutralOp(0.05, 0.42, 0.50),
    AvatarRegion.helmetStripe: NeutralOp(0.05, 0.42, 0.50),
  }),
  AvatarPreset('midnight', 'Midnight', {
    // Black suit with white shoulder and side details.
    AvatarRegion.chest: NeutralOp(0.03, 0.03, 0.38),
    AvatarRegion.sleeves: NeutralOp(0.00, 0.00, 0.38),
    AvatarRegion.legs: NeutralOp(0.00, 0.00, 0.38),
    AvatarRegion.gloves: NeutralOp(0.00, 0.00, 0.38),
    AvatarRegion.helmet: NeutralOp(0.00, 0.00, 0.38),
    AvatarRegion.boots: NeutralOp(0.00, 0.00, 0.38),
    AvatarRegion.accents: NeutralOp(0.00, 0.00, 0.38),
    AvatarRegion.stripes: NeutralOp(0.00, 0.00, 0.38),
    AvatarRegion.helmetStripe: NeutralOp(0.00, 0.00, 0.38),
  }),
];

AvatarPreset presetById(String? id) => avatarPresets
    .firstWhere((p) => p.id == id, orElse: () => avatarPresets.first);

/// Recolor a parsed artwork. Paths and metrics are shared with the source;
/// only colors change. Classification runs once per (distinct color, side of
/// the helmet floor) — a teal color reads as helmet up top but leg shading
/// low on the figure (see [kHelmetMaxYFrac]).
SplashArt recolorArt(SplashArt art, Map<AvatarRegion, RegionOp> ops) {
  final bounds = art.contentBounds;
  final helmetFloorY = bounds.top + bounds.height * kHelmetMaxYFrac;
  // Key = color, with the low bit reused to distinguish above/below the floor.
  final cache = <int, Color>{};
  Color map(Color color, double centerY) {
    final below = centerY > helmetFloorY;
    final key = (color.toARGB32() << 1) | (below ? 1 : 0);
    return cache.putIfAbsent(key, () {
      final hsv = HSVColor.fromColor(color);
      final op = switch (regionForColor(hsv, belowHelmet: below)) {
        null => null,
        final region => ops[region],
      };
      return op == null ? color : op.apply(hsv).toColor();
    });
  }

  final strokeCentersY = art.strokeCentersY;
  final fillCentersY = art.fillCentersY;
  return SplashArt(
    width: art.width,
    height: art.height,
    strokes: [
      for (var i = 0; i < art.strokes.length; i++)
        StrokeElement(
          path: art.strokes[i].path,
          color: map(art.strokes[i].color, strokeCentersY[i]),
          width: art.strokes[i].width,
          metrics: art.strokes[i].metrics,
          length: art.strokes[i].length,
        ),
    ],
    fills: [
      for (var i = 0; i < art.fills.length; i++)
        FillElement(
            path: art.fills[i].path,
            color: map(art.fills[i].color, fillCentersY[i])),
    ],
  );
}
