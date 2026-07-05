import { describe, it, expect } from 'vitest'
import {
  AVATAR_REGIONS,
  classifyHex,
  customRegionsToDart,
  displaySvg,
  hexToHsv,
  hsvToHex,
  makeCustomRegion,
  normalizeHex,
  parseAvatarSvg,
  reassignHex,
  rewriteSvg,
  regionOverlayColor,
  splitColor,
  type SvgEdits
} from '../utils/avatarRegions'

const edits = (
  regionEdits: [number, string][] = [],
  colorEdits: [number, string][] = []
): SvgEdits => ({ regionEdits: new Map(regionEdits), colorEdits: new Map(colorEdits) })

// Minimal rainbow-master-like fixture: a teal helmet path, a green legs path,
// a dark ink path (line art), and a magenta gloves rect.
const FIXTURE = `<?xml version="1.0"?>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0.00 0.00 100.00 200.00">
<g stroke-width="2.00">
<path stroke="#0db5c2" vector-effect="non-scaling-stroke" d="M 10 10 L 20 20"/>
</g>
<path fill="#13cadc" d="M 0 0 L 10 0 L 10 10 Z"/>
<path fill="#2b9c38" d="M 0 100 L 10 100 L 10 110 Z"/>
<path fill="#30090c" d="M 5 5 L 6 6 L 5 6 Z"/>
<rect fill="#e21fbc" x="50" y="50" width="10" height="10"/>
</svg>`

describe('classifyHex', () => {
  it('maps rainbow bands to regions and guards line art', () => {
    expect(classifyHex('#13cadc')).toBe('helmet') // teal
    expect(classifyHex('#2b9c38')).toBe('legs') // green
    expect(classifyHex('#e21fbc')).toBe('gloves') // magenta
    expect(classifyHex('#dc2926')).toBe('chest') // red
    expect(classifyHex('#30090c')).toBeNull() // too dark → ink
    expect(classifyHex('#7c6b6c')).toBeNull() // desaturated → ink
  })
})

describe('normalizeHex', () => {
  it('accepts 3/6 digits with or without # and normalizes to #rrggbb', () => {
    expect(normalizeHex('#13cadc')).toBe('#13cadc')
    expect(normalizeHex('13CADC')).toBe('#13cadc')
    expect(normalizeHex('#abc')).toBe('#aabbcc')
    expect(normalizeHex(' e10600 ')).toBe('#e10600')
  })

  it('rejects anything else', () => {
    expect(normalizeHex('')).toBeNull()
    expect(normalizeHex('#12')).toBeNull()
    expect(normalizeHex('#1234')).toBeNull()
    expect(normalizeHex('red')).toBeNull()
    expect(normalizeHex('#gg0000')).toBeNull()
  })
})

describe('hex/hsv round trip', () => {
  it('round-trips colors within 1/255 per channel', () => {
    for (const hex of ['#13cadc', '#2b9c38', '#e21fbc', '#ffffff', '#000000']) {
      expect(hsvToHex(hexToHsv(hex))).toBe(hex)
    }
  })
})

describe('parseAvatarSvg', () => {
  it('finds colored elements with group color and classification', () => {
    const doc = parseAvatarSvg(FIXTURE)
    expect(doc.viewBox).toEqual({ width: 100, height: 200 })
    // 5 colored elements: 1 stroke path + 3 fill paths + 1 rect.
    expect(doc.elements).toHaveLength(5)
    const regions = doc.elements.map((e) => e.region)
    expect(regions).toEqual(['helmet', 'helmet', 'legs', null, 'gloves'])
    // Stroke elements are grouped by their stroke color.
    expect(doc.elements[0]!.colorAttr).toBe('stroke')
    expect(doc.elements[1]!.colorAttr).toBe('fill')
  })
})

describe('reassignHex', () => {
  it('moves the hue into the target region band, keeping shade', () => {
    const src = '#13cadc' // teal helmet shade
    const out = reassignHex(src, 'legs')
    expect(classifyHex(out)).toBe('legs')
    const a = hexToHsv(src)
    const b = hexToHsv(out)
    expect(Math.abs(a.s - b.s)).toBeLessThan(0.02)
    expect(Math.abs(a.v - b.v)).toBeLessThan(0.02)
  })

  it('lifts line-art colors above the guards so they become recolorable', () => {
    const out = reassignHex('#30090c', 'chest') // near-black ink
    expect(classifyHex(out)).toBe('chest')
  })
})

describe('rewriteSvg', () => {
  it('rewrites only the edited elements, preserving everything else', () => {
    const doc = parseAvatarSvg(FIXTURE)
    // Move the legs path (#2b9c38, element index 2) to the accents region.
    const out = rewriteSvg(FIXTURE, doc, edits([[2, 'accents']]))
    expect(out).not.toContain('#2b9c38')
    const reparsed = parseAvatarSvg(out)
    expect(reparsed.elements.map((e) => e.region))
      .toEqual(['helmet', 'helmet', 'accents', null, 'gloves'])
    // Untouched colors survive byte-for-byte.
    expect(out).toContain('#13cadc')
    expect(out).toContain('#e21fbc')
    expect(out).toContain('#30090c')
    // Non-element content (header, group tag) intact.
    expect(out).toContain('viewBox="0.00 0.00 100.00 200.00"')
    expect(out).toContain('<g stroke-width="2.00">')
  })

  it('rewrites a stroke element via its stroke attribute', () => {
    const doc = parseAvatarSvg(FIXTURE)
    const out = rewriteSvg(FIXTURE, doc, edits([[0, 'boots']]))
    const reparsed = parseAvatarSvg(out)
    expect(reparsed.elements[0]!.region).toBe('boots')
    // The fill twin of the old teal is untouched.
    expect(out).toContain('#13cadc')
  })

  it('applies split colors, and region edits on top of them', () => {
    const doc = parseAvatarSvg(FIXTURE)
    // Split element 1 out of the teal group, then move it to boots.
    const split = splitColor('#13cadc', new Set(doc.elements.map((e) => e.color)))
    const out = rewriteSvg(FIXTURE, doc, edits([[1, 'boots']], [[1, split]]))
    const reparsed = parseAvatarSvg(out)
    // Element 0 (stroke twin) keeps the original teal; element 1 is now boots.
    expect(reparsed.elements[0]!.color).toBe('#0db5c2')
    expect(reparsed.elements[1]!.region).toBe('boots')
    // The boots hue came from the SPLIT color's shade, not the original.
    expect(reparsed.elements[1]!.color).toBe(reassignHex(split, 'boots'))
  })
})

describe('splitColor', () => {
  it('returns an unused color that classifies identically and is near-identical', () => {
    const used = new Set(['#13cadc'])
    const out = splitColor('#13cadc', used)
    expect(out).not.toBe('#13cadc')
    expect(classifyHex(out)).toBe('helmet')
    const a = hexToHsv('#13cadc')
    const b = hexToHsv(out)
    expect(Math.abs(a.v - b.v)).toBeLessThan(0.03)
    // Successive splits keep producing fresh colors.
    used.add(out)
    const out2 = splitColor('#13cadc', used)
    expect(out2).not.toBe(out)
    expect(classifyHex(out2)).toBe('helmet')
  })
})

describe('ink + removal sentinels', () => {
  it('assigning to line art desaturates below the classifier guard', () => {
    const doc = parseAvatarSvg(FIXTURE)
    const out = rewriteSvg(FIXTURE, doc, edits([[2, 'ink']]))
    const reparsed = parseAvatarSvg(out)
    // Same element count, but the green legs path is now unclassified ink.
    expect(reparsed.elements).toHaveLength(5)
    expect(reparsed.elements[2]!.region).toBeNull()
    // Hue/brightness survive; only saturation drops.
    const a = hexToHsv('#2b9c38')
    const b = hexToHsv(reparsed.elements[2]!.color)
    expect(b.s).toBeLessThan(0.15)
    expect(Math.abs(a.v - b.v)).toBeLessThan(0.02)
  })

  it('assigning to removed deletes the element from the export and the canvas', () => {
    const doc = parseAvatarSvg(FIXTURE)
    const out = rewriteSvg(FIXTURE, doc, edits([[2, 'removed']]))
    const reparsed = parseAvatarSvg(out)
    expect(reparsed.elements).toHaveLength(4)
    expect(out).not.toContain('#2b9c38')
    // Everything else survives byte-for-byte.
    expect(out).toContain('#13cadc')
    expect(out).toContain('<g stroke-width="2.00">')

    const display = displaySvg(FIXTURE, doc, {
      mode: 'artwork', edits: edits([[2, 'removed']]), selected: new Set()
    })
    expect(display).not.toContain('data-idx="2"')
    expect(display).toContain('data-idx="1"')
  })
})

describe('custom regions', () => {
  const visor = makeCustomRegion('visor', 'Visor', 0.31)

  it('classification prefers custom bands over built-in bins', () => {
    // 0.31 is inside the built-in legs band (0.243–0.400).
    const hex = hsvToHex({ h: 0.31 * 360, s: 0.8, v: 0.7 })
    expect(classifyHex(hex)).toBe('legs')
    expect(classifyHex(hex, [visor])).toBe('visor')
  })

  it('reassign + overlay resolve custom regions by anchor hue', () => {
    const out = reassignHex('#13cadc', 'visor', [visor])
    expect(classifyHex(out, [visor])).toBe('visor')
    expect(classifyHex(regionOverlayColor('visor', [visor]), [visor])).toBe('visor')
  })

  it('exports paste-ready Dart enum + classifier lines', () => {
    const dart = customRegionsToDart([visor])
    expect(dart).toContain(`visor('Visor', 0.31),`)
    expect(dart).toContain('if (h >= 0.295 && h < 0.325) return AvatarRegion.visor;')
  })
})

describe('displaySvg', () => {
  it('tags every colored element with data-idx for hit-testing', () => {
    const doc = parseAvatarSvg(FIXTURE)
    const out = displaySvg(FIXTURE, doc, { mode: 'artwork', edits: edits(), selected: new Set() })
    for (let i = 0; i < doc.elements.length; i++) {
      expect(out).toContain(`data-idx="${i}"`)
    }
  })

  it('regions mode paints elements with region overlay colors and dims ink', () => {
    const doc = parseAvatarSvg(FIXTURE)
    const out = displaySvg(FIXTURE, doc, { mode: 'regions', edits: edits(), selected: new Set() })
    expect(out).toContain(regionOverlayColor('helmet'))
    expect(out).toContain(regionOverlayColor('legs'))
    expect(out).toContain('#4a4a4a') // line art
    expect(out).not.toContain('#13cadc')
  })

  it('selection appends a highlight twin above the art', () => {
    const doc = parseAvatarSvg(FIXTURE)
    const out = displaySvg(FIXTURE, doc, { mode: 'artwork', edits: edits(), selected: new Set([2]) })
    expect(out).toContain('stroke="#ff00aa"')
    expect(out.trim().endsWith('</svg>')).toBe(true)
  })

  it('pending edits recolor into the target band in artwork mode', () => {
    const doc = parseAvatarSvg(FIXTURE)
    const out = displaySvg(FIXTURE, doc, {
      mode: 'artwork',
      edits: edits([[2, 'accents']]),
      selected: new Set()
    })
    expect(out).not.toContain('#2b9c38')
    expect(out).toContain(reassignHex('#2b9c38', 'accents'))
  })
})

describe('regionOverlayColor', () => {
  it('provides a distinct overlay color per region that classifies as itself', () => {
    for (const r of AVATAR_REGIONS) {
      expect(classifyHex(regionOverlayColor(r.key))).toBe(r.key)
    }
  })
})
