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
  // Only pose1 carries baked icons — and since the helmet-only icon set they
  // are HELMET art reusing the pose1_* variant ids (see bake_icons_test.dart).
  // pose2/pose3 ids remain registered natively but are hidden from the icon
  // gallery; saved selections of them migrate to the default icon.
  pose1('Victory', 'assets/avatar/pose1.svg', hasBakedIcons: true),
  pose2('Arms crossed', 'assets/avatar/pose2.svg'),
  pose3('Kneeling', 'assets/avatar/pose3.svg');

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
    // brightness; the spread shrinks toward black so dark suits go properly
    // dark while keeping subtle highlights (picked #000 → 0.15 ladder,
    // mid-tone ≈ #212121; white keeps the teamskin-like 0.45 spread).
    final spread = 0.15 + 0.3 * c.value;
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

// Sole surviving hue constant — every livery except ivory is now hand-tuned
// with raw ops pasted from the admin tuner, so the old teamskin-derived hue
// palette is gone. Colorways track the 2026 grid suits; display names are
// fictional (shipping real team names is a trademark problem).
const _red = 0.995;

// Neutral ladders, one shared definition per shade. Each is exactly
// opForPickedColor(target) under the current (darker) color space, so the
// liveries sit in the same space as a hand-picked color — the old teamskin
// ramps floored too high and rendered "black" suits as mid-grey. Targets:
// black #000000, white #FFFFFF, silver #D8D8D8, titanium #AEAEAE,
// anthracite #6B6B6B. (v' = base + spread·masterV; see avatarNeutralTargets.)
const _black = NeutralOp(0.0, 0.0, 0.15); // mid-tone ≈ #212121
const _white = NeutralOp(0.0, 0.6175, 0.45); // mid-tone ≈ #FFFFFF
const _silver = NeutralOp(0.0, 0.5036, 0.4041); // mid-tone ≈ #D8D8D8
const _titanium = NeutralOp(0.0, 0.3809, 0.3547); // mid-tone ≈ #AEAEAE
const _anthracite = NeutralOp(0.0, 0.1851, 0.2759); // mid-tone ≈ #6B6B6B

/// The pure target color each neutral ladder is derived from — the reference
/// for regression-checking that the constants stay `opForPickedColor(target)`.
const avatarNeutralTargets = <NeutralOp, Color>{
  _black: Color(0xFF000000),
  _white: Color(0xFFFFFFFF),
  _silver: Color(0xFFD8D8D8),
  _titanium: Color(0xFFAEAEAE),
  _anthracite: Color(0xFF6B6B6B),
};

const avatarPresets = <AvatarPreset>[
  AvatarPreset('undercut', 'Undercut', {
    AvatarRegion.helmet: NeutralOp(0.0, 0.0, 0.1888),
    AvatarRegion.helmetStripe: HueOp(0.0043, 0.9985, 1.0012),
    AvatarRegion.chest: NeutralOp(0.0, 0.0, 0.15),
    AvatarRegion.sleeves: NeutralOp(0.0, 0.0, 0.15),
    AvatarRegion.accents: HueOp(0.0044, 1.0),
    AvatarRegion.gloves: NeutralOp(0.0, 0.0, 0.1888),
    AvatarRegion.legs: NeutralOp(0.0, 0.0, 0.15),
    AvatarRegion.stripes: HueOp(0.0044, 1.0),
    AvatarRegion.boots: NeutralOp(0.0, 0.0, 0.1888),
  }),
  AvatarPreset('rosso', 'Rosso', {
    AvatarRegion.helmet: HueOp(0.9815, 1.0651, 0.7797),
    AvatarRegion.helmetStripe: NeutralOp(0.0084, 0.5708, 0.4312),
    AvatarRegion.chest: HueOp(0.9785, 1.078, 0.7751),
    AvatarRegion.sleeves: HueOp(0.9785, 1.078, 0.7751),
    AvatarRegion.accents: NeutralOp(0.0, 0.6175, 0.45),
    AvatarRegion.gloves: NeutralOp(0.0, 0.0, 0.17),
    AvatarRegion.legs: HueOp(0.9785, 1.078, 0.7751),
    AvatarRegion.stripes: HueOp(0.9785, 1.078, 0.7751),
    AvatarRegion.boots: NeutralOp(0.0, 0.0, 0.17),
  }),
  AvatarPreset('papaya', 'Papaya', {
    AvatarRegion.helmet: HueOp(0.0833, 1.1068, 1.1765),
    AvatarRegion.helmetStripe: NeutralOp(0.0, 0.0, 0.15),
    AvatarRegion.chest: HueOp(0.0833, 1.1068, 1.1765),
    AvatarRegion.sleeves: HueOp(0.0833, 1.1068, 1.1765),
    AvatarRegion.accents: NeutralOp(0.0, 0.0, 0.1888),
    AvatarRegion.gloves: HueOp(0.0833, 1.1068, 1.1765),
    AvatarRegion.legs: NeutralOp(0.0, 0.0, 0.1888),
    AvatarRegion.stripes: HueOp(0.0833, 1.1068, 1.1765),
    AvatarRegion.boots: HueOp(0.0833, 1.1068, 1.1765),
  }),
  AvatarPreset('silver', 'Silver', {
    AvatarRegion.helmet: HueOp(0.5097, 1.1111, 0.3183),
    AvatarRegion.helmetStripe: HueOp(0.4856, 1.0939, 0.5952),
    AvatarRegion.chest: NeutralOp(0.0, 0.0, 0.15),
    AvatarRegion.sleeves: NeutralOp(0.0, 0.0, 0.1888),
    AvatarRegion.accents: HueOp(0.4921, 1.0995, 0.8812),
    AvatarRegion.gloves: NeutralOp(0.0, 0.0, 0.15),
    AvatarRegion.legs: NeutralOp(0.0, 0.0, 0.15),
    AvatarRegion.stripes: HueOp(0.49, 0.95),
    AvatarRegion.boots: NeutralOp(0.0, 0.0, 0.1888),
  }),
  AvatarPreset('bolt', 'Bolt', {
    AvatarRegion.helmet: HueOp(0.6181, 0.7768, 0.5213),
    AvatarRegion.helmetStripe: NeutralOp(0.0052, 0.4334, 0.3759),
    AvatarRegion.chest: HueOp(0.6201, 1.1111, 0.3137),
    AvatarRegion.sleeves: HueOp(0.6201, 1.1111, 0.3137),
    AvatarRegion.accents: HueOp(0.9579, 0.9477, 0.9412),
    AvatarRegion.gloves: HueOp(0.6201, 1.1111, 0.3137),
    AvatarRegion.legs: HueOp(0.6201, 1.1111, 0.3137),
    AvatarRegion.stripes: HueOp(0.1305, 1.085, 1.1765),
    AvatarRegion.boots: HueOp(0.6201, 1.1111, 0.3137),
  }),
  AvatarPreset('verde', 'Verde', {
    AvatarRegion.helmet: HueOp(0.4815, 1.1111, 0.2491),
    AvatarRegion.helmetStripe: HueOp(0.1787, 1.1111, 1.0196),
    AvatarRegion.chest: HueOp(0.4815, 1.1111, 0.2491),
    AvatarRegion.sleeves: HueOp(0.4815, 1.1111, 0.2491),
    AvatarRegion.accents: HueOp(0.4813, 1.0988, 0.4152),
    AvatarRegion.gloves: HueOp(0.4813, 1.0988, 0.4152),
    AvatarRegion.legs: HueOp(0.4815, 1.1111, 0.2491),
    AvatarRegion.stripes: HueOp(0.4815, 1.1111, 0.2491),
    AvatarRegion.boots: HueOp(0.1787, 1.0936, 1.1719),
  }),
  AvatarPreset('azur', 'Azur', {
    AvatarRegion.helmet: HueOp(0.8842, 0.7773, 1.1672),
    AvatarRegion.helmetStripe: HueOp(0.5764, 1.1045, 0.7797),
    AvatarRegion.chest: HueOp(0.8842, 0.7773, 1.1672),
    AvatarRegion.sleeves: HueOp(0.5764, 1.1045, 0.7797),
    AvatarRegion.accents: HueOp(0.8842, 0.7773, 1.1672),
    AvatarRegion.gloves: HueOp(0.5764, 1.1045, 0.7797),
    AvatarRegion.legs: HueOp(0.62, 0.95, 0.5),
    AvatarRegion.stripes: HueOp(0.8842, 0.7773, 1.1672),
    AvatarRegion.boots: HueOp(0.5764, 1.1045, 0.7797),
  }),
  AvatarPreset('atlantic', 'Atlantic', {
    AvatarRegion.helmet: NeutralOp(0.0325, 0.5912, 0.4394),
    AvatarRegion.helmetStripe: HueOp(0.5988, 0.9859, 0.9827),
    AvatarRegion.chest: NeutralOp(0.0325, 0.5912, 0.4394),
    AvatarRegion.sleeves: NeutralOp(0.0325, 0.5912, 0.4394),
    AvatarRegion.accents: HueOp(0.5988, 0.9859, 0.9827),
    AvatarRegion.gloves: HueOp(0.5988, 0.9859, 0.9827),
    AvatarRegion.legs: NeutralOp(0.0325, 0.5912, 0.4394),
    AvatarRegion.stripes: HueOp(0.5988, 0.9859, 0.9827),
    AvatarRegion.boots: NeutralOp(0.0325, 0.5912, 0.4394),
  }),
  AvatarPreset('frost', 'Frost', {
    AvatarRegion.helmet: HueOp(0.6192, 1.1054, 0.895),
    AvatarRegion.helmetStripe: HueOp(0.333, 1.0),
    AvatarRegion.chest: NeutralOp(0.0, 0.6175, 0.45),
    AvatarRegion.sleeves: HueOp(0.62, 1.0),
    AvatarRegion.accents: HueOp(0.333, 1.0),
    AvatarRegion.gloves: HueOp(0.62, 0.95, 0.5),
    AvatarRegion.legs: NeutralOp(0.0, 0.6175, 0.45),
    AvatarRegion.stripes: HueOp(0.62, 1.0),
    AvatarRegion.boots: NeutralOp(0.0, 0.5036, 0.4041),
  }),
  AvatarPreset('ivory', 'Ivory', {
    // White sleeves over a black chest and legs, red details.
    AvatarRegion.chest: _black,
    AvatarRegion.sleeves: _white,
    AvatarRegion.helmet: _white,
    AvatarRegion.legs: _black,
    AvatarRegion.gloves: _black,
    AvatarRegion.boots: _black,
    AvatarRegion.accents: HueOp(_red, 1.0),
    AvatarRegion.stripes: _white,
    AvatarRegion.helmetStripe: HueOp(_red, 1.0),
  }),
  AvatarPreset('titan', 'Titan', {
    AvatarRegion.helmet: HueOp(0.0289, 1.1068, 1.1765),
    AvatarRegion.helmetStripe: NeutralOp(0.0, 0.5036, 0.4041),
    AvatarRegion.chest: NeutralOp(0.0645, 0.0536, 0.2229),
    AvatarRegion.sleeves: NeutralOp(0.0645, 0.0536, 0.2229),
    AvatarRegion.accents: HueOp(0.0289, 1.1068, 1.1765),
    AvatarRegion.gloves: NeutralOp(0.0, 0.0, 0.15),
    AvatarRegion.legs: NeutralOp(0.0645, 0.0536, 0.2229),
    AvatarRegion.stripes: NeutralOp(0.0, 0.5036, 0.4041),
    AvatarRegion.boots: NeutralOp(0.0645, 0.0536, 0.2229),
  }),
  AvatarPreset('midnight', 'Midnight', {
    AvatarRegion.helmet: NeutralOp(0.0327, 0.5883, 0.4382),
    AvatarRegion.helmetStripe: NeutralOp(0.0, 0.0, 0.15),
    AvatarRegion.chest: NeutralOp(0.0, 0.0, 0.15),
    AvatarRegion.sleeves: NeutralOp(0.0, 0.0, 0.15),
    AvatarRegion.accents: NeutralOp(0.0, 0.0, 0.15),
    AvatarRegion.gloves: NeutralOp(0.0327, 0.5883, 0.4382),
    AvatarRegion.legs: NeutralOp(0.0, 0.0, 0.15),
    AvatarRegion.stripes: NeutralOp(0.0327, 0.5883, 0.4382),
    AvatarRegion.boots: NeutralOp(0.0, 0.0, 0.15),
  }),
];

AvatarPreset presetById(String? id) => avatarPresets
    .firstWhere((p) => p.id == id, orElse: () => avatarPresets.first);

/// Recolor a parsed artwork. Paths and metrics are shared with the source;
/// only colors change. Classification runs once per (distinct color, side of
/// the helmet floor) — a teal color reads as helmet up top but leg shading
/// low on the figure (see [kHelmetMaxYFrac]).
///
/// [positionalRules] applies that figure-shaped heuristic. Disable it for
/// non-figure masters — on the standalone helmet asset the "below the helmet
/// floor" test would reclassify the entire lower shell as legs.
SplashArt recolorArt(SplashArt art, Map<AvatarRegion, RegionOp> ops,
    {bool positionalRules = true}) {
  final bounds = art.contentBounds;
  final helmetFloorY = positionalRules
      ? bounds.top + bounds.height * kHelmetMaxYFrac
      : double.infinity;
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
