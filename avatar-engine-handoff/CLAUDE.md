# Racing Avatar Engine — Project Context

## What this is
A Flutter app with a 2D racing-avatar creation engine (Bitmoji/Snapchat-style, racing theme).
Users customize a cel-shaded cartoon race driver: colors per region, poses, decals/numbers.
Also used to generate alternate app icons (F1-team-style liveries) via dynamic icon switching.

## Core architecture decisions (already made)
1. **No runtime AI generation.** AI (Gemini/Nano Banana) produces source art offline;
   the app is a layer compositor.
2. **Asset pipeline: "rainbow master" SVGs.**
   - Each pose is generated as a cel-shaded character where every semantic region has a
     distinct hue (rainbow encoding): red=chest, orange=sleeves, yellow=helmet stripe,
     lime=collar/belt, green=legs, teal=helmet, blue=boots, purple=side stripes,
     magenta=gloves. Desaturated (s<0.15) or very dark (v<0.22) colors = line art /
     visor / background → never recolored.
   - Gemini vectorizes the raster to SVG (auto-trace: ~1.4k–3.6k anonymous paths,
     quantized flat fills, no groups/ids — semantics come ONLY from hue).
   - `teamskin.py` (in this folder, working, tested) classifies every color by hue bin
     and applies team palettes. Two operations per region:
     - `('hue', target_h, s_scale)` — hue shift, preserves shade ladder
     - `('neutral', s_fixed, v_a, v_b)` — v' = a + b*v, for silver/white/black/anthracite
3. **Runtime rendering: raster compositor, not runtime SVG.**
   - Build time: render per-region alpha masks + shading + line art PNGs from the SVGs
     (or bake full team variants).
   - Flutter: CustomPainter; per region drawImageRect with
     ColorFilter(color, BlendMode.srcIn), shading via BlendMode.multiply,
     highlights via screen, line art on top. Composite → cache → PNG export
     (stickers, app icons).
   - Avatar = data: {poseId, colors: {region: hex}, helmetDesignId, decalIds, number}.
   - All layers of a pose share identical dimensions/alignment (one srcRect).
4. **Rive**: evaluated, deferred. No AI art/rig import; only useful later for animated
   pose transitions (would require manual vector rig). Rive Editor MCP server exists for
   state-machine automation if we go there.

## Known issues / tuning notes
- Hue bins currently: red ≥0.97|<0.028, orange <0.088, yellow <0.155, lime <0.243,
  green <0.400, teal <0.548, blue <0.660, purple <0.830, magenta rest.
  Teal helmet vs blue boots is the tightest boundary — future masters should use
  violet-blue boots for margin.
- Per-region brightness is inherited from the master (Ferrari legs darker than chest
  because master's green legs were darker than red chest). Fix: per-region v-boost in
  palette config, or regenerate master with uniform mid-brightness regions.
- Generation prompt template (Gemini/AI Studio, attach base sticker as Image 1):
  same character/pose/style, fictional generic driver (opaque visor, no real logos),
  each region in its distinct rainbow hue, flat cel shading, plain grey background,
  square format. New poses: same prompt + pose description; keep framing/scale identical.

## Legal constraints (decided)
- Ship only fictional liveries: NO team names, team/sponsor logos, or exact
  driver-number+color combos (App Store 5.2 / Play trademark policy / Markengesetz).
  Color schemes alone are fine. Faceless helmets = no personality-rights issue.

## Dynamic app icon (secondary feature)
- Icons must be bundled at build time on both platforms.
- iOS: setAlternateIconName, CFBundleIcons in Info.plist, mandatory system alert.
- Android: activity-alias per icon, launcher refresh/app kill quirks, OEM issues (Xiaomi).
- Package: flutter_dynamic_icon_plus (or dynamic_icon_changer for Android relaunch).

## Next steps (suggested order)
1. Port teamskin.py palette math to Dart (HSVColor) OR keep it as build-time asset step.
2. Build-time script: rainbow-master SVGs → per-region mask PNGs + shading + line art
   + JSON manifest (regions, decal anchor transforms per pose).
3. Flutter compositor (CustomPainter as above) + color picker UI;
   tap-to-select-region via mask alpha lookup.
4. Export pipeline: PictureRecorder → toImage → PNG (stickers/icons).
5. Generate remaining poses as rainbow masters; run pipeline.

## Files in this handoff
- teamskin.py — working classifier + Ferrari/Mercedes/McLaren palettes (cairosvg to render)
- sim1.svg — rainbow master, pose 1 (source of truth for region encoding)
