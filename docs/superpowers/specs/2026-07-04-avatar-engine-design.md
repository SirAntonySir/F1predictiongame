# Avatar Engine — Design

Date: 2026-07-04. Approved by Anton in-session.

## Goal

Recolorable driver avatars power the loading screen (full pose) and the app
icon (upper body, preset liveries only). Users configure the avatar in a
builder screen inside Settings: team presets plus a per-region color picker.

## Context

`avatar-engine-handoff/` contains a "rainbow master" SVG (`sim1.svg`): every
semantic region of a cel-shaded driver is encoded as a distinct hue band
(red=chest, orange=sleeves, yellow=helmet stripe, lime=collar/belt,
green=legs, teal=helmet, blue=boots, purple=side stripes, magenta=gloves;
desaturated or very dark colors = line art, never recolored). `teamskin.py`
holds working hue-bin classification and Ferrari/McLaren/Mercedes palettes.

Key decision: the handoff doc proposed a raster mask compositor, but the app
already ships an SVG paint engine (`PaintedSplash` / `SplashArt`) that parses
and animates exactly this trace format at 60fps. We recolor the parsed art at
load time instead — no new pipeline, no baked mask assets.

## Decisions (from brainstorming)

- App icon: pre-baked preset variants only (iOS/Android require bundled
  icons). Custom colors apply to the splash only.
- Persistence: local device (`SharedPreferences`), like `ThemeController`.
- `sim1.svg` (as `assets/avatar/pose1.svg`, background stripped) replaces
  `astonmartin.svg` as the splash artwork.
- One active config; built-in presets are starting points. No user-named
  preset library in v1.
- Default preset: "Undercut" in brand colors. Fourth chip next to
  Ferrari/McLaren/Mercedes (fictional names in UI; no team trademarks).
- Builder preview replays the sketch-draw animation on preset switch.

## Components

### `lib/avatar/avatar_palette.dart`
Port of `teamskin.py`. `AvatarRegion` enum (9 regions), hue-bin classifier
(`s < 0.15 || v < 0.22` → untouched line art), two ops:
`hue(targetH, sScale)` preserving the master's shading ladder, and
`neutral(sFixed, vA, vB)` (`v' = a + b·v`) for silver/white/black. Built-in
presets as `{region: op}` maps. Derivation of an op from a picked color:
saturated pick → hue op, low-saturation pick → neutral op. A recolor function
maps a parsed `SplashArt` to a recolored copy (paths/metrics shared, colors
remapped; classification runs once per unique color).

### `lib/avatar/avatar_config.dart` + `lib/state/avatar_controller.dart`
`AvatarConfig { presetId?, overrides: {region: color}, iconVariant }`,
JSON-serialized. Controller mirrors `ThemeController`: `load()`, setters,
`notifyListeners`, prefs-backed.

### Splash integration
`PaintedSplash` loads `assets/avatar/pose1.svg` and applies the saved config
(prefs read directly during boot; Undercut preset when unset). Draw animation
and `BoxFit.contain` scaling unchanged. `astonmartin.svg` removed.

### Builder screen (`lib/screens/avatar_screen.dart`, route `/avatar`)
Settings card (title + subtitle, no leading icon) → screen with:
live preview (same painter, replay on preset change), 4 preset chips,
9 region rows (name + swatch) opening a `BrandedSheet` color picker
(hue slider + shade square + quick swatches), reset-to-preset row,
app-icon variant picker (4 baked options).

### Dynamic app icon
4 icon PNG sets baked at dev time from the upper-body crop of pose1 per
preset, rendered through the same test-render pipeline used for splash review
frames. iOS: `CFBundleIcons` alternate icons; Android: `activity-alias`.
Switching via `flutter_dynamic_icon_plus`. iOS shows a mandatory system alert
on switch — accepted.

## Amendments (same day, during build)

- Pose 2 ("Arms crossed", sim1pose2.svg) was delivered mid-build and is in
  v1: `AvatarPose` enum, pose chips in the builder, pose persisted in the
  config, splash uses the chosen pose. Icons stay pose-1-only.
- The app-icon picker offers "Classic" (the shipped ticket icon, primary)
  plus the four avatar liveries as alternates; `iconVariant` defaults to
  `classic` so installing the update never silently changes the icon.
- Pose 3 ("Kneeling", sim1pose3.svg) added: splash + builder. Its trace
  has more shades per region (48 distinct fills vs 22) — the hue-bin
  classifier handles that unchanged, verified by rendered review frames.
  `AvatarPose.hasBakedIcons` gates the icon gallery, `iconVariants`, and
  `validIconVariant` to poses with a baked, natively-registered icon set.
- All launcher icons rebaked (current palette — the original bake predated
  the white helmet-stripe presets) including pose 3, in TWO background sets:
  dark #2E2C31 (`poseN_livery`, unchanged ids) and ticket-cream #EFEAE0
  (`poseN_livery_light`) for light-mode home screens — 72 variants total,
  selected via a DARK/LIGHT toggle in the gallery. Alternate icons are loose
  PNGs (legacy CFBundleIcons), so they cannot auto-switch with the OS
  appearance; the light set is a manual choice. The repeatable bake lives in
  test/tools/bake_icons_test.dart (`--dart-define=BAKE=true`) with per-pose
  crop squares; pose 1 keeps the original square so the primary icon stays
  in sync with `pose1_undercut`.

## Out of scope (v1)

Decals, driver numbers, helmet designs, backend sync,
tap-region-to-select on the preview, user-named preset library.

## Testing

- Palette unit tests: hue-bin edges, both ops, preset snapshots, op
  derivation from picked colors, line-art immunity.
- Controller tests: round-trip persistence, defaults.
- Widget tests: builder screen interactions (preset switch, picker, reset).
- Visual: render all presets to /tmp via the existing review-frame test
  pattern and inspect.
