import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/avatar/avatar_palette.dart';
import 'package:predictiongame/components/painted_splash.dart';

HSVColor _hsv(double h01, double s, double v) =>
    HSVColor.fromAHSV(1, (h01 * 360) % 360, s, v);

void main() {
  group('classifyMasterColor', () {
    test('maps each rainbow band to its region (teamskin.py bins)', () {
      expect(classifyMasterColor(_hsv(0.00, 0.9, 0.8)), AvatarRegion.chest);
      expect(classifyMasterColor(_hsv(0.98, 0.9, 0.8)), AvatarRegion.chest);
      expect(classifyMasterColor(_hsv(0.05, 0.9, 0.8)), AvatarRegion.sleeves);
      expect(
          classifyMasterColor(_hsv(0.12, 0.9, 0.8)), AvatarRegion.helmetStripe);
      expect(classifyMasterColor(_hsv(0.20, 0.9, 0.8)), AvatarRegion.accents);
      expect(classifyMasterColor(_hsv(0.33, 0.9, 0.8)), AvatarRegion.legs);
      expect(classifyMasterColor(_hsv(0.50, 0.9, 0.8)), AvatarRegion.helmet);
      expect(classifyMasterColor(_hsv(0.60, 0.9, 0.8)), AvatarRegion.boots);
      expect(classifyMasterColor(_hsv(0.75, 0.9, 0.8)), AvatarRegion.stripes);
      expect(classifyMasterColor(_hsv(0.90, 0.9, 0.8)), AvatarRegion.gloves);
    });

    test('bin edges: helmet/boots boundary at 0.548', () {
      expect(classifyMasterColor(_hsv(0.547, 0.9, 0.8)), AvatarRegion.helmet);
      expect(classifyMasterColor(_hsv(0.548, 0.9, 0.8)), AvatarRegion.boots);
    });

    test('line art is immune: low saturation or low value', () {
      expect(classifyMasterColor(_hsv(0.5, 0.14, 0.8)), isNull);
      expect(classifyMasterColor(_hsv(0.5, 0.9, 0.21)), isNull);
    });
  });

  group('legs/helmet positional disambiguation', () {
    test('a teal color is helmet up top but legs down low', () {
      final teal = _hsv(0.45, 0.6, 0.5); // teal-green, helmet bin by hue
      expect(classifyMasterColor(teal), AvatarRegion.helmet);
      expect(regionForColor(teal, belowHelmet: false), AvatarRegion.helmet);
      // Same color low on the figure is leg/thigh shading, not a helmet.
      expect(regionForColor(teal, belowHelmet: true), AvatarRegion.legs);
    });

    test('non-helmet regions are unaffected by vertical position', () {
      final green = _hsv(0.33, 0.9, 0.6); // legs
      final blue = _hsv(0.60, 0.9, 0.6); // boots
      expect(regionForColor(green, belowHelmet: true), AvatarRegion.legs);
      expect(regionForColor(blue, belowHelmet: true), AvatarRegion.boots);
    });

    testWidgets('pose3 thigh streaks recolor with the legs op, not helmet',
        (tester) async {
      final text = await tester.runAsync(
          () => rootBundle.loadString('assets/avatar/pose3.svg'));
      final art = SplashArt.parse(text!);
      final floorY =
          art.contentBounds.top + art.contentBounds.height * kHelmetMaxYFrac;

      // Distinct ops: helmet → red, legs → green. A misclassified thigh streak
      // would come out red without the fix.
      final ops = {
        AvatarRegion.helmet: const HueOp(0.0, 1.0), // red
        AvatarRegion.legs: const HueOp(0.33, 1.0), // green
      };
      final recolored = recolorArt(art, ops);

      // A helmet-bin fill whose center sits below the helmet floor = a thigh
      // streak. There must be some (that's the bug), and each must be green.
      var found = 0;
      for (var i = 0; i < art.fills.length; i++) {
        final f = art.fills[i];
        if (classifyMasterColor(HSVColor.fromColor(f.color)) !=
            AvatarRegion.helmet) continue;
        if (f.path.getBounds().center.dy <= floorY) continue;
        found++;
        final h = HSVColor.fromColor(recolored.fills[i].color).hue / 360;
        // green (~0.33), not red (~0.0)
        expect(h, closeTo(0.33, 0.05),
            reason: 'thigh streak #$i should recolor as legs');
      }
      expect(found, greaterThan(0),
          reason: 'pose3 must have helmet-bin paths below the floor');
    });
  });

  group('ops', () {
    test('HueOp shifts hue, scales saturation, keeps shade ladder', () {
      const op = HueOp(0.995, 1.0);
      final dark = op.apply(_hsv(0.5, 0.9, 0.4));
      final light = op.apply(_hsv(0.5, 0.9, 0.9));
      expect(dark.hue, closeTo(0.995 * 360, 0.01));
      expect(dark.value, 0.4); // ladder preserved
      expect(light.value, 0.9);
    });

    test('HueOp vScale lifts or drops the ladder, clamped', () {
      const op = HueOp(0.5, 1.0, 1.5);
      expect(op.apply(_hsv(0, 0.9, 0.5)).value, closeTo(0.75, 1e-9));
      expect(op.apply(_hsv(0, 0.9, 0.9)).value, 1.0); // clamped
    });

    test('NeutralOp remaps to v\' = a + b*v with fixed saturation', () {
      const op = NeutralOp(0.05, 0.42, 0.50); // mercedes silver
      final out = op.apply(_hsv(0.0, 0.95, 0.8));
      expect(out.saturation, 0.05);
      expect(out.value, closeTo(0.42 + 0.50 * 0.8, 1e-9));
    });
  });

  group('opForPickedColor', () {
    test('saturated pick becomes a HueOp at the picked hue', () {
      final op = opForPickedColor(const Color(0xFFE10600));
      expect(op, isA<HueOp>());
      final applied = op.apply(_hsv(0.5, 0.9, 0.85));
      expect(applied.hue, closeTo(HSVColor.fromColor(const Color(0xFFE10600)).hue, 0.5));
    });

    test('gray pick becomes a NeutralOp anchored near picked brightness', () {
      final white = opForPickedColor(const Color(0xFFF2F2F2));
      expect(white, isA<NeutralOp>());
      // Nominal mid-tone master shade should come out bright.
      expect(HSVColor.fromColor(white.swatch).value, greaterThan(0.85));

      // Cartoon black keeps subtle shading highlights, so "black" reads as
      // a dark ladder rather than flat #000 (compare teamskin 0.03/0.38).
      final black = opForPickedColor(const Color(0xFF141414));
      expect(HSVColor.fromColor(black.swatch).value, lessThan(0.28));
    });

    test('round-trip: swatch of the derived op is close to the pick', () {
      const picked = Color(0xFFFF8000);
      final op = opForPickedColor(picked);
      final sw = HSVColor.fromColor(op.swatch);
      final want = HSVColor.fromColor(picked);
      expect(sw.hue, closeTo(want.hue, 1.0));
      expect(sw.value, closeTo(want.value, 0.05));
    });
  });

  group('presets', () {
    test('all liveries exist with full region coverage where it matters', () {
      expect(avatarPresets.map((p) => p.id), [
        'undercut',
        'rosso',
        'papaya',
        'silver',
        'bolt',
        'verde',
        'azur',
        'atlantic',
        'frost',
        'ivory',
        'titan',
        'midnight',
      ]);
      // Undercut covers every region explicitly.
      expect(presetById('undercut').ops.length, AvatarRegion.values.length);
      // Every added livery covers all nine regions.
      for (final p in avatarPresets.skip(4)) {
        expect(p.ops.length, AvatarRegion.values.length,
            reason: '${p.id} should cover every region');
      }
    });

    test('presetById falls back to the default preset', () {
      expect(presetById('nonsense').id, 'undercut');
      expect(presetById(null).id, 'undercut');
    });

    test('rosso turns the teal helmet red and whitens the accents', () {
      final ops = presetById('rosso').ops;
      final helmet = ops[AvatarRegion.helmet]!.apply(_hsv(0.5, 0.9, 0.8));
      expect(helmet.hue, closeTo(0.995 * 360, 0.01));
      final accents = ops[AvatarRegion.accents]!.apply(_hsv(0.2, 0.9, 0.8));
      expect(accents.saturation, closeTo(0.03, 1e-9));
      expect(accents.value, greaterThan(0.8));
    });
  });

  group('recolorArt', () {
    SplashArt art(Color fill, Color stroke) => SplashArt.parse('''
<svg viewBox="0 0 10 10">
<g stroke-width="2.00" fill="none">
<path stroke="#${stroke.toARGB32().toRadixString(16).substring(2)}" d="M 0 0 L 10 10"/>
</g>
<path fill="#${fill.toARGB32().toRadixString(16).substring(2)}" d="M 0 0 L 10 0 L 10 10 Z"/>
</svg>''');

    test('recolors classified fills and strokes, leaves line art alone', () {
      // Teal (helmet region) fill; near-black line-art stroke.
      final src = art(const Color(0xFF20B2AA), const Color(0xFF201C1D));
      final out = recolorArt(src, presetById('rosso').ops);
      final fillHue = HSVColor.fromColor(out.fills.single.color).hue;
      expect(fillHue, closeTo(0.995 * 360, 0.5));
      expect(out.strokes.single.color, src.strokes.single.color);
      // Geometry is shared, not copied.
      expect(identical(out.fills.single.path, src.fills.single.path), isTrue);
      expect(
          identical(out.strokes.single.metrics, src.strokes.single.metrics),
          isTrue);
    });

    test('empty ops map is a no-op recolor', () {
      final src = art(const Color(0xFF20B2AA), const Color(0xFF404040));
      final out = recolorArt(src, const {});
      expect(out.fills.single.color, src.fills.single.color);
    });
  });
}
