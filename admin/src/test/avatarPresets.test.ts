import { describe, it, expect } from 'vitest'
import { classifyHex, hexToHsv } from '../utils/avatarRegions'
import {
  AVATAR_PRESETS,
  applyOp,
  opForPickedColor,
  opSwatchHex,
  presetToDart,
  recolorHex
} from '../utils/avatarPresets'

describe('AVATAR_PRESETS port', () => {
  it('carries all 12 liveries with a full 9-region op map each', () => {
    expect(AVATAR_PRESETS).toHaveLength(12)
    expect(AVATAR_PRESETS.map((p) => p.id)).toContain('undercut')
    expect(AVATAR_PRESETS.map((p) => p.id)).toContain('midnight')
    for (const p of AVATAR_PRESETS) {
      expect(Object.keys(p.ops)).toHaveLength(9)
    }
  })
})

describe('applyOp', () => {
  it('HueOp shifts hue and preserves the shade ladder', () => {
    const dark = applyOp({ kind: 'hue', targetHue: 0.995, sScale: 1 }, { h: 180, s: 0.9, v: 0.4 })
    const light = applyOp({ kind: 'hue', targetHue: 0.995, sScale: 1 }, { h: 180, s: 0.9, v: 0.9 })
    expect(dark.h).toBeCloseTo(0.995 * 360, 3)
    expect(light.h).toBeCloseTo(0.995 * 360, 3)
    expect(dark.v).toBeCloseTo(0.4)
    expect(light.v).toBeCloseTo(0.9)
  })

  it('NeutralOp fixes saturation and remaps value linearly', () => {
    const out = applyOp({ kind: 'neutral', sFixed: 0.03, vA: 0.55, vB: 0.45 }, { h: 120, s: 0.8, v: 0.6 })
    expect(out.s).toBeCloseTo(0.03)
    expect(out.v).toBeCloseTo(0.55 + 0.45 * 0.6)
  })
})

describe('recolorHex', () => {
  it('rosso turns a teal helmet shade red and a lime accent white-ish', () => {
    const rosso = AVATAR_PRESETS.find((p) => p.id === 'rosso')!
    const helmet = recolorHex('#13cadc', 'helmet', rosso.ops)
    expect(classifyHex(helmet)).toBe('chest') // red band
    const accents = recolorHex('#77962b', 'accents', rosso.ops)
    const hsv = hexToHsv(accents)
    expect(hsv.s).toBeLessThan(0.1) // whitened
    expect(hsv.v).toBeGreaterThan(0.5)
  })

  it('line art passes through untouched', () => {
    const rosso = AVATAR_PRESETS.find((p) => p.id === 'rosso')!
    expect(recolorHex('#30090c', null, rosso.ops)).toBe('#30090c')
  })
})

describe('opForPickedColor', () => {
  it('saturated pick derives a hue op at the picked hue', () => {
    const op = opForPickedColor('#0090ff')
    expect(op.kind).toBe('hue')
    if (op.kind === 'hue') {
      expect(op.targetHue).toBeCloseTo(hexToHsv('#0090ff').h / 360, 3)
    }
  })

  it('gray pick derives a neutral ladder', () => {
    const op = opForPickedColor('#b8b8b8')
    expect(op.kind).toBe('neutral')
  })

  it('a black pick derives a properly dark ladder (mid-tone ≈ #212121)', () => {
    const op = opForPickedColor('#000000')
    expect(op.kind).toBe('neutral')
    expect(hexToHsv(opSwatchHex(op)).v).toBeCloseTo(0.1275, 2)
  })

  it('round-trips through the swatch: picked color ≈ swatch of derived op', () => {
    for (const hex of ['#0090ff', '#e10600', '#b8b8b8', '#f2f2f2']) {
      const swatch = opSwatchHex(opForPickedColor(hex))
      const a = hexToHsv(hex)
      const b = hexToHsv(swatch)
      expect(Math.abs(a.v - b.v)).toBeLessThan(0.06)
      expect(Math.abs(a.s - b.s)).toBeLessThan(0.06)
    }
  })
})

describe('presetToDart', () => {
  it('emits a paste-ready AvatarPreset literal in enum order', () => {
    const rosso = AVATAR_PRESETS.find((p) => p.id === 'rosso')!
    const dart = presetToDart(rosso)
    expect(dart).toContain(`AvatarPreset('rosso', 'Rosso', {`)
    expect(dart).toContain('AvatarRegion.helmet: HueOp(0.9815, 1.0651, 0.7797),')
    expect(dart).toContain('AvatarRegion.helmetStripe: NeutralOp(0.0084, 0.5708, 0.4312),')
    expect(dart).toContain('AvatarRegion.boots: NeutralOp(0.0, 0.0, 0.17),')
    expect(dart.trim().endsWith('}),')).toBe(true)
    // Regions appear in the app's enum order.
    const helmetPos = dart.indexOf('AvatarRegion.helmet:')
    const bootsPos = dart.indexOf('AvatarRegion.boots:')
    expect(helmetPos).toBeGreaterThan(-1)
    expect(helmetPos).toBeLessThan(bootsPos)
  })
})
