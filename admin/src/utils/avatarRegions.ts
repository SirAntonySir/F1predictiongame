// Avatar "rainbow master" SVG region tooling.
//
// The Flutter app derives an avatar's recolorable regions FROM the segment
// colors: every semantic region lives in a hue band (red=chest, teal=helmet,
// …) and desaturated/dark colors are line art that never recolors. This module
// mirrors that classifier (lib/avatar/avatar_palette.dart — keep in sync) so
// the admin editor can visualize the groups and FIX a master by rewriting a
// segment's hue into the target region's band. The app itself needs no
// override data — the corrected SVG is the single source of truth.

export type RegionKey =
  | 'helmet'
  | 'helmetStripe'
  | 'chest'
  | 'sleeves'
  | 'accents'
  | 'gloves'
  | 'legs'
  | 'stripes'
  | 'boots'

export type AvatarRegion = {
  key: RegionKey
  label: string
  /** Nominal hue (0..1) of the region in the master — the band's anchor. */
  masterHue: number
}

// Order mirrors the app's AvatarRegion enum.
export const AVATAR_REGIONS: AvatarRegion[] = [
  { key: 'helmet', label: 'Helmet', masterHue: 0.5 },
  { key: 'helmetStripe', label: 'Helmet stripe', masterHue: 0.12 },
  { key: 'chest', label: 'Chest', masterHue: 0.0 },
  { key: 'sleeves', label: 'Sleeves', masterHue: 0.058 },
  { key: 'accents', label: 'Collar & belt', masterHue: 0.2 },
  { key: 'gloves', label: 'Gloves', masterHue: 0.9 },
  { key: 'legs', label: 'Legs', masterHue: 0.33 },
  { key: 'stripes', label: 'Side stripes', masterHue: 0.75 },
  { key: 'boots', label: 'Boots', masterHue: 0.6 }
]

const REGION_BY_KEY = new Map(AVATAR_REGIONS.map((r) => [r.key, r]))

// Line-art guard: below these thresholds a color is ink/visor/shadow.
const MIN_SATURATION = 0.15
const MIN_VALUE = 0.22

export type Hsv = { h: number; s: number; v: number }

export function hexToHsv(hex: string): Hsv {
  const m = /^#?([0-9a-f]{6})$/i.exec(hex.trim())
  if (!m) throw new Error(`not a hex color: ${hex}`)
  const n = parseInt(m[1]!, 16)
  const r = ((n >> 16) & 0xff) / 255
  const g = ((n >> 8) & 0xff) / 255
  const b = (n & 0xff) / 255
  const max = Math.max(r, g, b)
  const min = Math.min(r, g, b)
  const d = max - min
  let h = 0
  if (d !== 0) {
    if (max === r) h = ((g - b) / d) % 6
    else if (max === g) h = (b - r) / d + 2
    else h = (r - g) / d + 4
    h *= 60
    if (h < 0) h += 360
  }
  return { h, s: max === 0 ? 0 : d / max, v: max }
}

/** Normalize user hex input (`abc`, `#abc`, `AABBCC`, …) to `#rrggbb`, or null. */
export function normalizeHex(input: string): string | null {
  const m = /^#?([0-9a-f]{3}|[0-9a-f]{6})$/i.exec(input.trim())
  if (!m) return null
  const raw = m[1]!.toLowerCase()
  return `#${raw.length === 3 ? [...raw].map((c) => c + c).join('') : raw}`
}

export function hsvToHex({ h, s, v }: Hsv): string {
  const c = v * s
  const x = c * (1 - Math.abs(((h / 60) % 2) - 1))
  const m = v - c
  let r = 0, g = 0, b = 0
  if (h < 60) [r, g, b] = [c, x, 0]
  else if (h < 120) [r, g, b] = [x, c, 0]
  else if (h < 180) [r, g, b] = [0, c, x]
  else if (h < 240) [r, g, b] = [0, x, c]
  else if (h < 300) [r, g, b] = [x, 0, c]
  else [r, g, b] = [c, 0, x]
  const to = (u: number) => Math.round((u + m) * 255).toString(16).padStart(2, '0')
  return `#${to(r)}${to(g)}${to(b)}`
}

/**
 * A user-defined region: a named hue band carved out of the wheel. Custom
 * bands are checked BEFORE the built-in bins, so they shadow a slice of the
 * band they were carved from. Becomes real in the app only when its exported
 * Dart (enum entry + classifier line) is pasted into avatar_palette.dart.
 */
export type CustomRegion = {
  /** camelCase identifier — the future AvatarRegion enum entry name. */
  key: string
  label: string
  /** Anchor hue (0..1) — segments assigned here are rewritten to it. */
  masterHue: number
  /** Half-open band [lo, hi) that classifies into this region. */
  bandLo: number
  bandHi: number
}

/** Default half-width of the band carved around a new region's anchor hue. */
export const CUSTOM_BAND_HALF_WIDTH = 0.015

export function makeCustomRegion(key: string, label: string, masterHue: number): CustomRegion {
  return {
    key,
    label,
    masterHue,
    bandLo: Math.max(0, masterHue - CUSTOM_BAND_HALF_WIDTH),
    bandHi: Math.min(1, masterHue + CUSTOM_BAND_HALF_WIDTH)
  }
}

/**
 * Hue-bin classification (port of classifyMasterColor), extended with
 * user-defined bands which take precedence. Null = line art.
 */
export function classifyHex(hex: string, customs: CustomRegion[] = []): string | null {
  const { h: hue, s, v } = hexToHsv(hex)
  if (s < MIN_SATURATION || v < MIN_VALUE) return null
  const h = hue / 360
  for (const c of customs) {
    if (h >= c.bandLo && h < c.bandHi) return c.key
  }
  if (h >= 0.97 || h < 0.028) return 'chest' // red
  if (h < 0.088) return 'sleeves' // orange
  if (h < 0.155) return 'helmetStripe' // yellow
  if (h < 0.243) return 'accents' // lime
  if (h < 0.4) return 'legs' // green
  if (h < 0.548) return 'helmet' // teal
  if (h < 0.66) return 'boots' // blue
  if (h < 0.83) return 'stripes' // purple
  return 'gloves' // magenta
}

function regionHue(region: string, customs: CustomRegion[]): number {
  const custom = customs.find((c) => c.key === region)
  if (custom) return custom.masterHue
  const builtin = REGION_BY_KEY.get(region as RegionKey)
  if (!builtin) throw new Error(`unknown region: ${region}`)
  return builtin.masterHue
}

/**
 * Rewrite a color into [region]'s hue band, keeping its shade ladder (s/v).
 * Line-art colors are lifted just above the classifier guards — assigning a
 * segment to a region means it must become recolorable.
 */
export function reassignHex(hex: string, region: string, customs: CustomRegion[] = []): string {
  const { s, v } = hexToHsv(hex)
  return hsvToHex({
    h: (regionHue(region, customs) * 360) % 360,
    s: Math.max(s, MIN_SATURATION + 0.05),
    v: Math.max(v, MIN_VALUE + 0.08)
  })
}

/** Flat, vivid color used to paint a region's segments in the Regions view. */
export function regionOverlayColor(region: string, customs: CustomRegion[] = []): string {
  return hsvToHex({ h: (regionHue(region, customs) * 360) % 360, s: 0.85, v: 0.9 })
}

/**
 * A fresh color for a group split: nudge the base value one step at a time
 * until the hex is unused, without changing how it classifies. The split
 * segments become their own color group — separately selectable, separately
 * reassignable — while looking identical to the eye (Δv ≤ a few /255).
 */
export function splitColor(
  base: string,
  used: ReadonlySet<string>,
  customs: CustomRegion[] = []
): string {
  const { h, s, v } = hexToHsv(base)
  const baseRegion = classifyHex(base, customs)
  for (let step = 1; step < 64; step++) {
    for (const dir of [1, -1]) {
      const cand = hsvToHex({ h, s, v: Math.min(1, Math.max(0, v + (dir * step) / 255)) })
      if (used.has(cand) || cand === base) continue
      if (classifyHex(cand, customs) !== baseRegion) continue
      return cand
    }
  }
  throw new Error('no free split color near ' + base)
}

/**
 * Paste-ready Dart for custom regions: the enum entries for AvatarRegion and
 * the classifier lines to insert at the TOP of classifyMasterColor's bins
 * (customs must win over the built-in bands, same as in this tool).
 */
export function customRegionsToDart(customs: CustomRegion[]): string {
  if (customs.length === 0) return ''
  const lines = ['// AvatarRegion enum entries:']
  for (const c of customs) {
    lines.push(`${c.key}('${c.label}', ${c.masterHue}),`)
  }
  lines.push('', '// classifyMasterColor — insert BEFORE the built-in bins:')
  for (const c of customs) {
    lines.push(`if (h >= ${c.bandLo} && h < ${c.bandHi}) return AvatarRegion.${c.key};`)
  }
  return lines.join('\n')
}

export type SvgElement = {
  /** Index into AvatarSvgDoc.elements — stable id for edits. */
  index: number
  tag: string
  /** Offsets of the full element in the source text. */
  start: number
  end: number
  /** Which attribute carries the group color (stroke wins, like the app). */
  colorAttr: 'stroke' | 'fill'
  /** The group color (hex, lowercase). */
  color: string
  /** Built-in classification of the ORIGINAL color (customs not applied). */
  region: string | null
}

export type AvatarSvgDoc = {
  viewBox: { width: number; height: number }
  elements: SvgElement[]
}

const ELEMENT_RE = /<(path|rect|ellipse|circle|polygon|polyline)\b([^>]*?)\/>/gs
const VIEWBOX_RE = /viewBox="\s*[\d.+-]+\s+[\d.+-]+\s+([\d.+-]+)\s+([\d.+-]+)\s*"/

function attrValue(attrs: string, name: string): string | null {
  const m = new RegExp(`${name}="([^"]*)"`).exec(attrs)
  return m ? m[1]! : null
}

/**
 * Parse the colored elements of a trace SVG, mirroring the app's parser:
 * an element with a hex stroke is a stroke element; otherwise a hex fill
 * makes it a fill element; anything else (none/absent) is ignored.
 */
export function parseAvatarSvg(svg: string): AvatarSvgDoc {
  const vb = VIEWBOX_RE.exec(svg)
  const viewBox = {
    width: vb ? parseFloat(vb[1]!) : 100,
    height: vb ? parseFloat(vb[2]!) : 100
  }
  const elements: SvgElement[] = []
  for (const m of svg.matchAll(ELEMENT_RE)) {
    const attrs = m[2]!
    const stroke = attrValue(attrs, 'stroke')
    const fill = attrValue(attrs, 'fill')
    const colorAttr = stroke?.startsWith('#') ? 'stroke' : fill?.startsWith('#') ? 'fill' : null
    if (colorAttr == null) continue
    const color = (colorAttr === 'stroke' ? stroke! : fill!).toLowerCase()
    if (!/^#[0-9a-f]{6}$/.test(color)) continue
    elements.push({
      index: elements.length,
      tag: m[1]!,
      start: m.index!,
      end: m.index! + m[0].length,
      colorAttr,
      color,
      region: classifyHex(color)
    })
  }
  return { viewBox, elements }
}

/**
 * The editor's pending edits. [colorEdits] are group splits (a nudged unique
 * color that makes a sub-selection its own group); [regionEdits] are region
 * reassignments. Both feed one color pipeline: base = split color ?? original,
 * final = region edit ? reassignHex(base) : base.
 */
export type SvgEdits = {
  regionEdits: Map<number, string>
  colorEdits: Map<number, string>
}

export const NO_EDITS: SvgEdits = { regionEdits: new Map(), colorEdits: new Map() }

/**
 * Sentinel "regions" assignable in the editor beyond the real hue bands:
 * [INK_REGION] desaturates the segment below the classifier guards, turning
 * it into line art (never recolored by the app); [REMOVED_REGION] deletes the
 * element from the exported SVG — the background-removal action.
 */
export const INK_REGION = 'ink'
export const REMOVED_REGION = 'removed'

/** Desaturate a color below the line-art guard, keeping its hue + brightness. */
export function inkHex(hex: string): string {
  const { h, v } = hexToHsv(hex)
  return hsvToHex({ h, s: Math.min(0.08, MIN_SATURATION - 0.05), v })
}

/** The element's color after any split, before any region reassignment. */
export function effectiveBaseColor(el: SvgElement, edits: SvgEdits): string {
  return edits.colorEdits.get(el.index) ?? el.color
}

/** The element's final color under the current edits. */
export function effectiveColor(el: SvgElement, edits: SvgEdits, customs: CustomRegion[] = []): string {
  const base = effectiveBaseColor(el, edits)
  const region = edits.regionEdits.get(el.index)
  if (region == null || region === REMOVED_REGION) return base
  if (region === INK_REGION) return inkHex(base)
  return reassignHex(base, region, customs)
}

/** The element's region under the current edits (custom bands included). */
export function effectiveRegion(
  el: SvgElement,
  edits: SvgEdits,
  customs: CustomRegion[] = []
): string | null {
  return edits.regionEdits.get(el.index) ?? classifyHex(effectiveBaseColor(el, edits), customs)
}

/**
 * Apply the pending edits to the source SVG. Each touched element's
 * group-color attribute is replaced with its effective color; elements
 * assigned to [REMOVED_REGION] are deleted outright (background removal);
 * everything else is preserved byte-for-byte.
 */
export function rewriteSvg(
  svg: string,
  doc: AvatarSvgDoc,
  edits: SvgEdits,
  customs: CustomRegion[] = []
): string {
  if (edits.regionEdits.size === 0 && edits.colorEdits.size === 0) return svg
  const parts: string[] = []
  let pos = 0
  for (const el of doc.elements) {
    if (edits.regionEdits.get(el.index) === REMOVED_REGION) {
      parts.push(svg.slice(pos, el.start))
      pos = el.end
      continue
    }
    const newColor = effectiveColor(el, edits, customs)
    if (newColor === el.color) continue
    const raw = svg.slice(el.start, el.end)
    const rewritten = raw.replace(`${el.colorAttr}="${el.color}"`, `${el.colorAttr}="${newColor}"`)
    parts.push(svg.slice(pos, el.start), rewritten)
    pos = el.end
  }
  parts.push(svg.slice(pos))
  return parts.join('')
}

const SELECTION_COLOR = '#ff00aa'

/**
 * Build the display SVG for the editor: every colored element gets a
 * `data-idx` for hit-testing; in the Regions view each element is painted
 * with its (possibly edited) region's flat overlay color, line art dimmed;
 * in the Preset view colors run through [opts.recolor] (the livery preview).
 * Selected elements get a magenta outline copy appended on top (CSS outline
 * doesn't render on SVG shapes, so we draw the highlight as geometry).
 */
export function displaySvg(
  svg: string,
  doc: AvatarSvgDoc,
  opts: {
    mode: 'artwork' | 'regions' | 'preset'
    edits: SvgEdits
    selected: Set<number>
    customs?: CustomRegion[]
    /** Preset-preview color mapper (element index, base color) → display color. */
    recolor?: (index: number, color: string) => string
  }
): string {
  const customs = opts.customs ?? []
  const parts: string[] = []
  const highlights: string[] = []
  let pos = 0
  for (const el of doc.elements) {
    // Removed elements disappear from the canvas (WYSIWYG for the export);
    // their group row in the side panel stays as the way back (Revert edit).
    if (opts.edits.regionEdits.get(el.index) === REMOVED_REGION) {
      parts.push(svg.slice(pos, el.start))
      pos = el.end
      continue
    }
    const original = svg.slice(el.start, el.end)
    let raw = original
    if (opts.mode === 'regions') {
      const region = effectiveRegion(el, opts.edits, customs)
      const color =
        region == null || region === INK_REGION
          ? '#4a4a4a'
          : regionOverlayColor(region, customs)
      raw = raw.replace(`${el.colorAttr}="${el.color}"`, `${el.colorAttr}="${color}"`)
    } else if (opts.mode === 'preset' && opts.recolor != null) {
      const base = effectiveBaseColor(el, opts.edits)
      const display =
        opts.edits.regionEdits.get(el.index) === INK_REGION
          ? inkHex(base)
          : opts.recolor(el.index, base)
      raw = raw.replace(`${el.colorAttr}="${el.color}"`, `${el.colorAttr}="${display}"`)
    } else {
      const color = effectiveColor(el, opts.edits, customs)
      if (color !== el.color) {
        raw = raw.replace(`${el.colorAttr}="${el.color}"`, `${el.colorAttr}="${color}"`)
      }
    }
    raw = raw.replace(`<${el.tag}`, `<${el.tag} data-idx="${el.index}"`)
    parts.push(svg.slice(pos, el.start), raw)
    pos = el.end
    if (opts.selected.has(el.index)) {
      // Outline-only twin: strip color attrs, force a loud stroke.
      const twin = original
        .replace(/\s(?:fill|stroke|stroke-width)="[^"]*"/g, '')
        .replace(
          `<${el.tag}`,
          `<${el.tag} fill="none" stroke="${SELECTION_COLOR}" stroke-width="3" vector-effect="non-scaling-stroke" pointer-events="none"`
        )
      highlights.push(twin)
    }
  }
  // parts covers up to `pos`; append the remainder, then splice highlights
  // in front of the closing tag so they render above everything.
  let out = parts.join('') + svg.slice(pos)
  if (highlights.length > 0) {
    out = out.replace(/<\/svg>\s*$/, `${highlights.join('')}</svg>`)
  }
  return out
}
