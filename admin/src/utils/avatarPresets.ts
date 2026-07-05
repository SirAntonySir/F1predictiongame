// TS port of the app's avatar recolor ops + built-in presets
// (lib/avatar/avatar_palette.dart — keep in sync). Powers the admin preset
// editor: live preview of a livery on a loaded pose master, color-pick
// editing per region, and export of a paste-ready Dart AvatarPreset literal.
// The app itself never reads these at runtime — the Dart file stays the
// single source of truth (launcher icons are baked from it).

import {
  AVATAR_REGIONS,
  hexToHsv,
  hsvToHex,
  type Hsv,
  type RegionKey
} from './avatarRegions'

export type RegionOp =
  | { kind: 'hue'; targetHue: number; sScale: number; vScale?: number }
  | { kind: 'neutral'; sFixed: number; vA: number; vB: number }

export type PresetDef = {
  id: string
  name: string
  ops: Record<RegionKey, RegionOp>
}

const MIN_SATURATION = 0.15

/** Apply a region op to a color, mirroring HueOp/NeutralOp.apply. */
export function applyOp(op: RegionOp, c: Hsv): Hsv {
  if (op.kind === 'hue') {
    return {
      h: (op.targetHue * 360) % 360,
      s: Math.min(1, Math.max(0, c.s * op.sScale)),
      v: Math.min(1, Math.max(0, c.v * (op.vScale ?? 1)))
    }
  }
  return {
    h: c.h,
    s: Math.min(1, Math.max(0, op.sFixed)),
    v: Math.min(1, Math.max(0, op.vA + op.vB * c.v))
  }
}

/** Recolor one master color under a preset, given its (effective) region. */
export function recolorHex(
  hex: string,
  region: RegionKey | null,
  ops: Partial<Record<RegionKey, RegionOp>>
): string {
  if (region == null) return hex
  const op = ops[region]
  if (op == null) return hex
  return hsvToHex(applyOp(op, hexToHsv(hex)))
}

/** The color an op produces on the nominal mid-tone — the UI swatch. */
export function opSwatchHex(op: RegionOp): string {
  const nominal: Hsv =
    op.kind === 'hue' ? { h: (op.targetHue * 360) % 360, s: 0.9, v: 0.85 } : { h: 0, s: 0.9, v: 0.85 }
  return hsvToHex(applyOp(op, nominal))
}

/** Derive an op from a picked color, mirroring opForPickedColor. */
export function opForPickedColor(hex: string): RegionOp {
  const c = hexToHsv(hex)
  if (c.s < MIN_SATURATION) {
    // Spread shrinks toward black so dark picks go properly dark
    // (#000 → 0.15 ladder) while white keeps the 0.45 spread.
    const spread = 0.15 + 0.3 * c.v
    const base = Math.min(1, Math.max(0, c.v - spread * 0.85))
    return { kind: 'neutral', sFixed: c.s, vA: base, vB: spread }
  }
  return {
    kind: 'hue',
    targetHue: c.h / 360,
    sScale: Math.min(1.5, c.s / 0.9),
    vScale: Math.min(1.2, Math.max(0.2, c.v / 0.85))
  }
}

/** Dart double literal: at least one decimal, up to 4 significant decimals. */
function dartNum(n: number): string {
  const s = n.toFixed(4).replace(/0+$/, '').replace(/\.$/, '.0')
  return s
}

/** Paste-ready Dart AvatarPreset literal, regions in the app's enum order. */
export function presetToDart(preset: PresetDef): string {
  const lines = [`AvatarPreset('${preset.id}', '${preset.name}', {`]
  for (const r of AVATAR_REGIONS) {
    const op = preset.ops[r.key]
    if (op.kind === 'hue') {
      const args = [dartNum(op.targetHue), dartNum(op.sScale)]
      if (op.vScale != null && op.vScale !== 1) args.push(dartNum(op.vScale))
      lines.push(`  AvatarRegion.${r.key}: HueOp(${args.join(', ')}),`)
    } else {
      lines.push(
        `  AvatarRegion.${r.key}: NeutralOp(${dartNum(op.sFixed)}, ${dartNum(op.vA)}, ${dartNum(op.vB)}),`
      )
    }
  }
  lines.push('}),')
  return lines.join('\n')
}

/** Cheap per-color memo for full-figure recolors (2–3k elements, ~50 colors). */
export function makeRecolorer(
  ops: Partial<Record<RegionKey, RegionOp>>,
  regionOf: (index: number, color: string) => RegionKey | null
): (index: number, color: string) => string {
  const cache = new Map<string, string>()
  return (index, color) => {
    const region = regionOf(index, color)
    const key = `${region}|${color}`
    const hit = cache.get(key)
    if (hit != null) return hit
    const out = recolorHex(color, region, ops)
    cache.set(key, out)
    return out
  }
}

// ---- Built-in presets, kept in sync with avatar_palette.dart ----

// Only ivory still uses these shared constants; every other livery is
// hand-tuned with raw ops pasted from this tuner.
const RED = 0.995

const hue = (targetHue: number, sScale: number, vScale?: number): RegionOp =>
  vScale == null ? { kind: 'hue', targetHue, sScale } : { kind: 'hue', targetHue, sScale, vScale }
const neutral = (sFixed: number, vA: number, vB: number): RegionOp => ({
  kind: 'neutral',
  sFixed,
  vA,
  vB
})

const BLACK = neutral(0.0, 0.0, 0.15)
const WHITE = neutral(0.0, 0.6175, 0.45)

export const AVATAR_PRESETS: PresetDef[] = [
  // All liveries except ivory are hand-tuned in this tuner and pasted back as
  // raw ops (admin "Copy Dart"), so they don't use the shared constants.
  {
    id: 'undercut', name: 'Undercut',
    ops: {
      helmet: neutral(0.0, 0.0, 0.1888), helmetStripe: hue(0.0043, 0.9985, 1.0012),
      chest: neutral(0.0, 0.0, 0.15), sleeves: neutral(0.0, 0.0, 0.15),
      accents: hue(0.0044, 1.0), gloves: neutral(0.0, 0.0, 0.1888),
      legs: neutral(0.0, 0.0, 0.15), stripes: hue(0.0044, 1.0),
      boots: neutral(0.0, 0.0, 0.1888)
    }
  },
  {
    id: 'rosso', name: 'Rosso',
    ops: {
      helmet: hue(0.9815, 1.0651, 0.7797), helmetStripe: neutral(0.0084, 0.5708, 0.4312),
      chest: hue(0.9785, 1.078, 0.7751), sleeves: hue(0.9785, 1.078, 0.7751),
      accents: neutral(0.0, 0.6175, 0.45), gloves: neutral(0.0, 0.0, 0.17),
      legs: hue(0.9785, 1.078, 0.7751), stripes: hue(0.9785, 1.078, 0.7751),
      boots: neutral(0.0, 0.0, 0.17)
    }
  },
  {
    id: 'papaya', name: 'Papaya',
    ops: {
      helmet: hue(0.0833, 1.1068, 1.1765), helmetStripe: neutral(0.0, 0.0, 0.15),
      chest: hue(0.0833, 1.1068, 1.1765), sleeves: hue(0.0833, 1.1068, 1.1765),
      accents: neutral(0.0, 0.0, 0.1888), gloves: hue(0.0833, 1.1068, 1.1765),
      legs: neutral(0.0, 0.0, 0.1888), stripes: hue(0.0833, 1.1068, 1.1765),
      boots: hue(0.0833, 1.1068, 1.1765)
    }
  },
  {
    id: 'silver', name: 'Silver',
    ops: {
      helmet: hue(0.5097, 1.1111, 0.3183), helmetStripe: hue(0.4856, 1.0939, 0.5952),
      chest: neutral(0.0, 0.0, 0.15), sleeves: neutral(0.0, 0.0, 0.1888),
      accents: hue(0.4921, 1.0995, 0.8812), gloves: neutral(0.0, 0.0, 0.15),
      legs: neutral(0.0, 0.0, 0.15), stripes: hue(0.49, 0.95),
      boots: neutral(0.0, 0.0, 0.1888)
    }
  },
  {
    id: 'bolt', name: 'Bolt',
    ops: {
      helmet: hue(0.6181, 0.7768, 0.5213), helmetStripe: neutral(0.0052, 0.4334, 0.3759),
      chest: hue(0.6201, 1.1111, 0.3137), sleeves: hue(0.6201, 1.1111, 0.3137),
      accents: hue(0.9579, 0.9477, 0.9412), gloves: hue(0.6201, 1.1111, 0.3137),
      legs: hue(0.6201, 1.1111, 0.3137), stripes: hue(0.1305, 1.085, 1.1765),
      boots: hue(0.6201, 1.1111, 0.3137)
    }
  },
  {
    id: 'verde', name: 'Verde',
    ops: {
      helmet: hue(0.4815, 1.1111, 0.2491), helmetStripe: hue(0.1787, 1.1111, 1.0196),
      chest: hue(0.4815, 1.1111, 0.2491), sleeves: hue(0.4815, 1.1111, 0.2491),
      accents: hue(0.4813, 1.0988, 0.4152), gloves: hue(0.4813, 1.0988, 0.4152),
      legs: hue(0.4815, 1.1111, 0.2491), stripes: hue(0.4815, 1.1111, 0.2491),
      boots: hue(0.1787, 1.0936, 1.1719)
    }
  },
  {
    id: 'azur', name: 'Azur',
    ops: {
      helmet: hue(0.8842, 0.7773, 1.1672), helmetStripe: hue(0.5764, 1.1045, 0.7797),
      chest: hue(0.8842, 0.7773, 1.1672), sleeves: hue(0.5764, 1.1045, 0.7797),
      accents: hue(0.8842, 0.7773, 1.1672), gloves: hue(0.5764, 1.1045, 0.7797),
      legs: hue(0.62, 0.95, 0.5), stripes: hue(0.8842, 0.7773, 1.1672),
      boots: hue(0.5764, 1.1045, 0.7797)
    }
  },
  {
    id: 'atlantic', name: 'Atlantic',
    ops: {
      helmet: neutral(0.0325, 0.5912, 0.4394), helmetStripe: hue(0.5988, 0.9859, 0.9827),
      chest: neutral(0.0325, 0.5912, 0.4394), sleeves: neutral(0.0325, 0.5912, 0.4394),
      accents: hue(0.5988, 0.9859, 0.9827), gloves: hue(0.5988, 0.9859, 0.9827),
      legs: neutral(0.0325, 0.5912, 0.4394), stripes: hue(0.5988, 0.9859, 0.9827),
      boots: neutral(0.0325, 0.5912, 0.4394)
    }
  },
  {
    id: 'frost', name: 'Frost',
    ops: {
      helmet: hue(0.6192, 1.1054, 0.895), helmetStripe: hue(0.333, 1.0),
      chest: neutral(0.0, 0.6175, 0.45), sleeves: hue(0.62, 1.0),
      accents: hue(0.333, 1.0), gloves: hue(0.62, 0.95, 0.5),
      legs: neutral(0.0, 0.6175, 0.45), stripes: hue(0.62, 1.0),
      boots: neutral(0.0, 0.5036, 0.4041)
    }
  },
  {
    id: 'ivory', name: 'Ivory',
    ops: {
      helmet: WHITE, helmetStripe: hue(RED, 1), chest: BLACK, sleeves: WHITE,
      accents: hue(RED, 1), gloves: BLACK, legs: BLACK, stripes: WHITE,
      boots: BLACK
    }
  },
  {
    id: 'titan', name: 'Titan',
    ops: {
      helmet: hue(0.0289, 1.1068, 1.1765), helmetStripe: neutral(0.0, 0.5036, 0.4041),
      chest: neutral(0.0645, 0.0536, 0.2229), sleeves: neutral(0.0645, 0.0536, 0.2229),
      accents: hue(0.0289, 1.1068, 1.1765), gloves: neutral(0.0, 0.0, 0.15),
      legs: neutral(0.0645, 0.0536, 0.2229), stripes: neutral(0.0, 0.5036, 0.4041),
      boots: neutral(0.0645, 0.0536, 0.2229)
    }
  },
  {
    id: 'midnight', name: 'Midnight',
    ops: {
      helmet: neutral(0.0327, 0.5883, 0.4382), helmetStripe: neutral(0.0, 0.0, 0.15),
      chest: neutral(0.0, 0.0, 0.15), sleeves: neutral(0.0, 0.0, 0.15),
      accents: neutral(0.0, 0.0, 0.15), gloves: neutral(0.0327, 0.5883, 0.4382),
      legs: neutral(0.0, 0.0, 0.15), stripes: neutral(0.0327, 0.5883, 0.4382),
      boots: neutral(0.0, 0.0, 0.15)
    }
  }
]

/** Deep-clone a preset's ops so the editor can mutate a draft safely. */
export function cloneOps(ops: Record<RegionKey, RegionOp>): Record<RegionKey, RegionOp> {
  return Object.fromEntries(
    Object.entries(ops).map(([k, v]) => [k, { ...v }])
  ) as Record<RegionKey, RegionOp>
}

