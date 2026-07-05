import { useEffect, useMemo, useRef, useState } from 'react'
import {
  Badge, Box, Button, Flex, Heading, SegmentedControl, Select, Table, Text, TextField
} from '@radix-ui/themes'
import {
  AVATAR_REGIONS,
  customRegionsToDart,
  displaySvg,
  effectiveBaseColor,
  effectiveRegion,
  hexToHsv,
  INK_REGION,
  REMOVED_REGION,
  makeCustomRegion,
  normalizeHex,
  parseAvatarSvg,
  regionOverlayColor,
  rewriteSvg,
  splitColor,
  type AvatarSvgDoc,
  type CustomRegion,
  type RegionKey,
  type SvgEdits
} from '../utils/avatarRegions'
import {
  AVATAR_PRESETS,
  cloneOps,
  makeRecolorer,
  opForPickedColor,
  opSwatchHex,
  presetToDart,
  type PresetDef,
  type RegionOp
} from '../utils/avatarPresets'

type Loaded = { name: string; svg: string; doc: AvatarSvgDoc }
type View = { scale: number; x: number; y: number }

const FIT: View = { scale: 1, x: 0, y: 0 }

/**
 * Native color swatch + hex text field, kept in sync. Typing commits as soon
 * as the text parses (`abc`, `#aabbcc`, …); the draft survives until blur so
 * a committed value that normalizes differently (e.g. a preset swatch derived
 * from the picked color) doesn't yank the text mid-edit.
 */
function HexColorField({
  value,
  onChange,
  label
}: {
  value: string
  onChange: (hex: string) => void
  label: string
}) {
  const [draft, setDraft] = useState<string | null>(null)
  return (
    <>
      <input
        type="color"
        aria-label={label}
        value={value}
        onChange={(e) => {
          setDraft(null)
          onChange(e.target.value)
        }}
        style={{
          width: 26, height: 26, padding: 0,
          border: '1px solid var(--stroke)', borderRadius: 6, background: 'none'
        }}
      />
      <TextField.Root
        size="1"
        aria-label={`${label} hex`}
        value={draft ?? value}
        onChange={(e) => {
          setDraft(e.target.value)
          const hex = normalizeHex(e.target.value)
          if (hex) onChange(hex)
        }}
        onBlur={() => setDraft(null)}
        onKeyDown={(e) => {
          if (e.key === 'Enter') (e.target as HTMLInputElement).blur()
        }}
        style={{ width: 76, fontFamily: 'monospace' }}
      />
    </>
  )
}

/**
 * Avatar rainbow-master editor. The app derives recolor regions FROM segment
 * hues, so "moving a segment to another group" = rewriting its color into the
 * target region's hue band. Splitting a color group gives the split segments a
 * visually identical but unique color, so they become separately editable.
 * Custom regions are new hue bands — real in the app once their exported Dart
 * (enum entry + classifier line) is pasted into avatar_palette.dart.
 */
export function AvatarRegions() {
  const fileRef = useRef<HTMLInputElement>(null)
  const canvasRef = useRef<HTMLDivElement>(null)
  const [loaded, setLoaded] = useState<Loaded | null>(null)
  const [mode, setMode] = useState<'artwork' | 'regions' | 'preset'>('regions')
  const [pickMode, setPickMode] = useState<'group' | 'segment'>('group')
  const [selected, setSelected] = useState<Set<number>>(new Set())
  const [regionEdits, setRegionEdits] = useState<Map<number, string>>(new Map())
  const [colorEdits, setColorEdits] = useState<Map<number, string>>(new Map())
  const [customs, setCustoms] = useState<CustomRegion[]>([])
  const [newRegionName, setNewRegionName] = useState('')
  const [newRegionHue, setNewRegionHue] = useState('#40e0d0')
  // Pan/zoom viewport. Wheel zooms around the cursor; drag pans; a drag that
  // never exceeds the threshold falls through to click-selection.
  const [view, setView] = useState<View>(FIT)
  const panRef = useRef<{ x: number; y: number; viewX: number; viewY: number; moved: boolean } | null>(null)
  const [preset, setPreset] = useState<PresetDef>(() => ({
    ...AVATAR_PRESETS[0]!,
    ops: cloneOps(AVATAR_PRESETS[0]!.ops)
  }))
  const [copied, setCopied] = useState<'preset' | 'regions' | null>(null)

  const edits: SvgEdits = useMemo(() => ({ regionEdits, colorEdits }), [regionEdits, colorEdits])
  const editCount = regionEdits.size + colorEdits.size

  async function onFile(file: File | undefined) {
    if (!file) return
    const svg = await file.text()
    const doc = parseAvatarSvg(svg)
    setLoaded({ name: file.name, svg, doc })
    setSelected(new Set())
    setRegionEdits(new Map())
    setColorEdits(new Map())
    setView(FIT)
  }

  const html = useMemo(() => {
    if (!loaded) return ''
    // Preset preview respects pending edits (splits + region moves), so a
    // region fix and a livery can be validated together before export.
    const recolor = makeRecolorer(preset.ops, (index) => {
      const r = effectiveRegion(loaded.doc.elements[index]!, edits, customs)
      // Custom regions have no preset op yet → master color passes through,
      // matching how the app treats a region absent from a preset.
      return (r as RegionKey | null)
    })
    return displaySvg(loaded.svg, loaded.doc, { mode, edits, selected, customs, recolor })
  }, [loaded, mode, edits, selected, customs, preset])

  // Distinct color groups by EFFECTIVE base color, so splits show up as their
  // own row immediately.
  const groups = useMemo(() => {
    if (!loaded) return []
    const byColor = new Map<string, { color: string; indices: number[] }>()
    for (const el of loaded.doc.elements) {
      const c = effectiveBaseColor(el, edits)
      const g = byColor.get(c) ?? { color: c, indices: [] }
      g.indices.push(el.index)
      byColor.set(c, g)
    }
    return [...byColor.values()].sort((a, b) => b.indices.length - a.indices.length)
  }, [loaded, edits])

  const regionOf = (idx: number): string | null =>
    effectiveRegion(loaded!.doc.elements[idx]!, edits, customs)

  const regionCounts = useMemo(() => {
    const counts = new Map<string, number>()
    if (!loaded) return counts
    for (const el of loaded.doc.elements) {
      const r = effectiveRegion(el, edits, customs) ?? 'ink'
      counts.set(r, (counts.get(r) ?? 0) + 1)
    }
    return counts
  }, [loaded, edits, customs])

  // Selection facts driving the Split button: all selected segments share one
  // base color, and they're a proper subset of that group.
  const splittable = useMemo(() => {
    if (!loaded || selected.size === 0) return false
    const colors = new Set([...selected].map((i) => effectiveBaseColor(loaded.doc.elements[i]!, edits)))
    if (colors.size !== 1) return false
    const [color] = colors
    const groupSize = loaded.doc.elements.filter(
      (el) => effectiveBaseColor(el, edits) === color
    ).length
    return selected.size < groupSize
  }, [loaded, selected, edits])

  // ---- canvas interactions ----

  function onPointerDown(e: React.PointerEvent) {
    panRef.current = { x: e.clientX, y: e.clientY, viewX: view.x, viewY: view.y, moved: false }
  }

  function onPointerMove(e: React.PointerEvent) {
    const pan = panRef.current
    if (!pan) return
    const dx = e.clientX - pan.x
    const dy = e.clientY - pan.y
    if (!pan.moved && Math.hypot(dx, dy) < 4) return
    pan.moved = true
    setView((v) => ({ ...v, x: pan.viewX + dx, y: pan.viewY + dy }))
  }

  function onPointerUp(e: React.PointerEvent) {
    const pan = panRef.current
    panRef.current = null
    if (!loaded || (pan && pan.moved)) return // was a pan, not a click
    const hit = (e.target as Element).closest('[data-idx]')
    if (!hit) return
    const idx = Number(hit.getAttribute('data-idx'))
    const el = loaded.doc.elements[idx]
    if (!el) return
    const next =
      pickMode === 'group'
        ? loaded.doc.elements
            .filter((x) => effectiveBaseColor(x, edits) === effectiveBaseColor(el, edits))
            .map((x) => x.index)
        : [idx]
    setSelected((cur) => {
      if (e.shiftKey) {
        // Shift extends/toggles — the multi-select for split workflows.
        const merged = new Set(cur)
        const allIn = next.every((i) => merged.has(i))
        for (const i of next) allIn ? merged.delete(i) : merged.add(i)
        return merged
      }
      const same = next.every((i) => cur.has(i)) && cur.size === next.length
      return same ? new Set() : new Set(next)
    })
  }

  // Non-passive wheel listener — React's synthetic onWheel can't preventDefault.
  useEffect(() => {
    const node = canvasRef.current
    if (!node) return
    const onWheel = (e: WheelEvent) => {
      e.preventDefault()
      const rect = node.getBoundingClientRect()
      const px = e.clientX - rect.left
      const py = e.clientY - rect.top
      setView((v) => {
        const factor = e.deltaY < 0 ? 1.15 : 1 / 1.15
        const scale = Math.min(24, Math.max(0.2, v.scale * factor))
        const applied = scale / v.scale
        return { scale, x: px - (px - v.x) * applied, y: py - (py - v.y) * applied }
      })
    }
    node.addEventListener('wheel', onWheel, { passive: false })
    return () => node.removeEventListener('wheel', onWheel)
  }, [loaded])

  function zoomBy(factor: number) {
    const node = canvasRef.current
    const cx = node ? node.clientWidth / 2 : 0
    const cy = node ? node.clientHeight / 2 : 0
    setView((v) => {
      const scale = Math.min(24, Math.max(0.2, v.scale * factor))
      const applied = scale / v.scale
      return { scale, x: cx - (cx - v.x) * applied, y: cy - (cy - v.y) * applied }
    })
  }

  // ---- edit operations ----

  function assign(region: string) {
    if (selected.size === 0) return
    setRegionEdits((cur) => {
      const next = new Map(cur)
      for (const i of selected) next.set(i, region)
      return next
    })
    setSelected(new Set())
  }

  function splitSelection() {
    if (!loaded || !splittable) return
    const base = effectiveBaseColor(loaded.doc.elements[[...selected][0]!]!, edits)
    const used = new Set<string>([
      ...loaded.doc.elements.map((el) => el.color),
      ...colorEdits.values()
    ])
    const fresh = splitColor(base, used, customs)
    setColorEdits((cur) => {
      const next = new Map(cur)
      for (const i of selected) next.set(i, fresh)
      return next
    })
    // Keep the selection — the natural next step is assigning the new group.
  }

  function clearEditsOnSelection() {
    setRegionEdits((cur) => {
      const next = new Map(cur)
      for (const i of selected) next.delete(i)
      return next
    })
    setColorEdits((cur) => {
      const next = new Map(cur)
      for (const i of selected) next.delete(i)
      return next
    })
  }

  function addCustomRegion() {
    const label = newRegionName.trim()
    if (!label) return
    const key = label
      .replace(/[^a-zA-Z0-9 ]/g, '')
      .split(/\s+/)
      .map((w, i) => (i === 0 ? w.charAt(0).toLowerCase() + w.slice(1) : w.charAt(0).toUpperCase() + w.slice(1)))
      .join('')
    if (!key || AVATAR_REGIONS.some((r) => r.key === key) || customs.some((c) => c.key === key)) return
    const hue = hexToHsv(newRegionHue).h / 360
    setCustoms((cur) => [...cur, makeCustomRegion(key, label, Number(hue.toFixed(3)))])
    setNewRegionName('')
  }

  function download() {
    if (!loaded) return
    const out = rewriteSvg(loaded.svg, loaded.doc, edits, customs)
    const url = URL.createObjectURL(new Blob([out], { type: 'image/svg+xml' }))
    const a = document.createElement('a')
    a.href = url
    a.download = loaded.name
    a.click()
    URL.revokeObjectURL(url)
  }

  function seedPreset(id: string) {
    const src = AVATAR_PRESETS.find((p) => p.id === id)!
    setPreset({ ...src, ops: cloneOps(src.ops) })
  }

  function setRegionColor(region: RegionKey, hex: string) {
    setPreset((cur) => ({
      ...cur,
      ops: { ...cur.ops, [region]: opForPickedColor(hex) satisfies RegionOp }
    }))
  }

  async function copy(kind: 'preset' | 'regions') {
    await navigator.clipboard.writeText(
      kind === 'preset' ? presetToDart(preset) : customRegionsToDart(customs)
    )
    setCopied(kind)
    setTimeout(() => setCopied(null), 1500)
  }

  const regionLabel = (r: string | null) =>
    r == null || r === INK_REGION
      ? 'Line art'
      : r === REMOVED_REGION
        ? 'Removed (background)'
        : AVATAR_REGIONS.find((x) => x.key === r)?.label ??
          customs.find((c) => c.key === r)?.label ??
          r

  const allRegions: { key: string; label: string }[] = [
    ...AVATAR_REGIONS,
    ...customs.map((c) => ({ key: c.key, label: c.label }))
  ]

  return (
    <Flex direction="column" gap="4">
      <Flex align="center" justify="between" gap="3">
        <Heading size="6" className="display">Avatar regions</Heading>
        <Flex gap="2" align="center">
          {loaded && (
            <Button variant="soft" color="gray" onClick={() => fileRef.current?.click()}>
              Load other SVG
            </Button>
          )}
          <Button onClick={download} disabled={!loaded || editCount === 0}>
            Download corrected SVG{editCount > 0 ? ` (${editCount})` : ''}
          </Button>
        </Flex>
      </Flex>
      <Text size="2" color="gray">
        Regions are derived from segment hues (the rainbow-master pipeline). Reassigning a
        segment rewrites its hue into the target region's band — download the corrected SVG
        and replace the pose asset in <code>assets/avatar/</code>. Scroll to zoom, drag to
        pan, shift-click to multi-select.
      </Text>

      <input
        ref={fileRef}
        type="file"
        accept=".svg,image/svg+xml"
        aria-label="Load pose SVG"
        style={{ display: loaded ? 'none' : undefined }}
        onChange={(e) => void onFile(e.target.files?.[0])}
      />

      {loaded && (
        <Flex gap="4" align="start">
          {/* Canvas */}
          <Flex direction="column" gap="2" style={{ flex: 1, minWidth: 0 }}>
            <Flex gap="3" align="center" wrap="wrap">
              <SegmentedControl.Root value={mode} onValueChange={(v) => setMode(v as typeof mode)}>
                <SegmentedControl.Item value="regions">Regions</SegmentedControl.Item>
                <SegmentedControl.Item value="artwork">Artwork</SegmentedControl.Item>
                <SegmentedControl.Item value="preset">Preset</SegmentedControl.Item>
              </SegmentedControl.Root>
              <SegmentedControl.Root value={pickMode} onValueChange={(v) => setPickMode(v as typeof pickMode)}>
                <SegmentedControl.Item value="group">Pick color group</SegmentedControl.Item>
                <SegmentedControl.Item value="segment">Pick segment</SegmentedControl.Item>
              </SegmentedControl.Root>
              <Flex gap="1" align="center">
                <Button size="1" variant="soft" aria-label="Zoom out" onClick={() => zoomBy(1 / 1.4)}>−</Button>
                <Button size="1" variant="soft" aria-label="Zoom in" onClick={() => zoomBy(1.4)}>+</Button>
                <Button size="1" variant="soft" aria-label="Fit" onClick={() => setView(FIT)}>Fit</Button>
                <Text size="1" color="gray">{Math.round(view.scale * 100)}%</Text>
              </Flex>
              <Text size="1" color="gray">{loaded.name} · {loaded.doc.elements.length} segments</Text>
            </Flex>
            <Box
              ref={canvasRef}
              onPointerDown={onPointerDown}
              onPointerMove={onPointerMove}
              onPointerUp={onPointerUp}
              style={{
                border: '2px solid var(--stroke)',
                borderRadius: 'var(--radius-card)',
                background: '#1b1b1e',
                height: '72vh',
                overflow: 'hidden',
                cursor: 'crosshair',
                touchAction: 'none'
              }}
            >
              <div
                style={{
                  transform: `translate(${view.x}px, ${view.y}px) scale(${view.scale})`,
                  transformOrigin: '0 0'
                }}
                // The display SVG is derived from the loaded file text — same
                // trust level as rendering the asset itself.
                dangerouslySetInnerHTML={{ __html: html }}
              />
            </Box>
          </Flex>

          {/* Side panel */}
          <Flex direction="column" gap="4" style={{ width: 400 }}>
            <Box>
              <Text size="1" className="label">SELECTION</Text>
              {selected.size === 0 ? (
                <Text as="p" size="2" color="gray">
                  Click the artwork to select a {pickMode === 'group' ? 'color group' : 'segment'};
                  shift-click adds to the selection.
                </Text>
              ) : (
                <Flex direction="column" gap="2" mt="1">
                  <Text size="2">
                    {selected.size} segment{selected.size === 1 ? '' : 's'} selected · currently{' '}
                    <b>{regionLabel(regionOf([...selected][0]!))}</b>
                  </Text>
                  <Flex wrap="wrap" gap="1">
                    {allRegions.map((r) => (
                      <Button key={r.key} size="1" variant="soft" onClick={() => assign(r.key)}>
                        <span
                          style={{
                            width: 10, height: 10, borderRadius: 99,
                            background: regionOverlayColor(r.key, customs), display: 'inline-block'
                          }}
                        />
                        {r.label}
                      </Button>
                    ))}
                  </Flex>
                  <Flex gap="1" wrap="wrap">
                    <Button size="1" variant="soft" color="gray" onClick={() => assign(INK_REGION)}>
                      Line art
                    </Button>
                    <Button size="1" variant="soft" color="red" onClick={() => assign(REMOVED_REGION)}>
                      Remove (background)
                    </Button>
                    <Button size="1" variant="soft" disabled={!splittable} onClick={splitSelection}>
                      Split into new group
                    </Button>
                    <Button size="1" variant="soft" color="gray" onClick={clearEditsOnSelection}>
                      Revert edit
                    </Button>
                  </Flex>
                </Flex>
              )}
            </Box>

            <Box>
              <Text size="1" className="label">REGIONS</Text>
              <Flex wrap="wrap" gap="1" mt="1">
                {allRegions.map((r) => (
                  <Badge key={r.key} variant="soft" color="gray">
                    <span
                      style={{
                        width: 9, height: 9, borderRadius: 99,
                        background: regionOverlayColor(r.key, customs), display: 'inline-block'
                      }}
                    />
                    {r.label} · {regionCounts.get(r.key) ?? 0}
                  </Badge>
                ))}
                <Badge variant="soft" color="gray">Line art · {regionCounts.get('ink') ?? 0}</Badge>
                {(regionCounts.get(REMOVED_REGION) ?? 0) > 0 && (
                  <Badge variant="soft" color="red">Removed · {regionCounts.get(REMOVED_REGION)}</Badge>
                )}
              </Flex>
              <Flex gap="1" mt="2" align="center">
                <HexColorField
                  label="New region hue"
                  value={newRegionHue}
                  onChange={setNewRegionHue}
                />
                <TextField.Root
                  aria-label="New region name"
                  placeholder="New region name"
                  value={newRegionName}
                  onChange={(e) => setNewRegionName(e.target.value)}
                  style={{ flex: 1 }}
                />
                <Button size="1" variant="soft" onClick={addCustomRegion} disabled={!newRegionName.trim()}>
                  Add region
                </Button>
              </Flex>
              {customs.length > 0 && (
                <Flex mt="2" align="center" justify="between">
                  <Text size="1" color="gray">
                    Custom regions need their Dart pasted into avatar_palette.dart.
                  </Text>
                  <Button size="1" variant="soft" onClick={() => void copy('regions')}>
                    {copied === 'regions' ? 'Copied!' : 'Copy Dart (regions)'}
                  </Button>
                </Flex>
              )}
            </Box>

            <Box>
              <Flex align="center" justify="between">
                <Text size="1" className="label">PRESET EDITOR</Text>
                <Button size="1" variant="soft" onClick={() => void copy('preset')}>
                  {copied === 'preset' ? 'Copied!' : 'Copy Dart'}
                </Button>
              </Flex>
              <Flex direction="column" gap="2" mt="1">
                <Flex gap="2">
                  <Select.Root value={preset.id} onValueChange={seedPreset}>
                    <Select.Trigger aria-label="Seed preset" style={{ flex: 1 }} />
                    <Select.Content>
                      {AVATAR_PRESETS.map((p) => (
                        <Select.Item key={p.id} value={p.id}>{p.name}</Select.Item>
                      ))}
                    </Select.Content>
                  </Select.Root>
                  <TextField.Root
                    aria-label="Preset id"
                    value={preset.id}
                    onChange={(e) => setPreset((c) => ({ ...c, id: e.target.value }))}
                    style={{ width: 110 }}
                  />
                  <TextField.Root
                    aria-label="Preset name"
                    value={preset.name}
                    onChange={(e) => setPreset((c) => ({ ...c, name: e.target.value }))}
                    style={{ width: 110 }}
                  />
                </Flex>
                <Flex wrap="wrap" gap="2">
                  {AVATAR_REGIONS.map((r) => (
                    <label
                      key={r.key}
                      style={{ display: 'flex', alignItems: 'center', gap: 6, cursor: 'pointer' }}
                    >
                      <HexColorField
                        label={`${r.label} color`}
                        value={opSwatchHex(preset.ops[r.key])}
                        onChange={(hex) => setRegionColor(r.key, hex)}
                      />
                      <Text size="1">{r.label}</Text>
                    </label>
                  ))}
                </Flex>
                <Text size="1" color="gray">
                  Switch the canvas to <b>Preset</b> to preview. Colors derive ops the same way
                  the app's picker does; hand-tuned ops from the palette file are shown as their
                  swatch and re-derived on change. Copy the Dart and paste it into
                  avatarPresets in avatar_palette.dart.
                </Text>
              </Flex>
            </Box>

            <Box>
              <Text size="1" className="label">COLOR GROUPS</Text>
              <Table.Root size="1" variant="surface" style={{ marginTop: 4 }}>
                <Table.Body>
                  {groups.map((g) => {
                    const region = regionOf(g.indices[0]!)
                    const edited = g.indices.some((i) => regionEdits.has(i) || colorEdits.has(i))
                    return (
                      <Table.Row
                        key={g.color}
                        style={{ cursor: 'pointer' }}
                        onClick={() => setSelected(new Set(g.indices))}
                      >
                        <Table.Cell>
                          <Flex align="center" gap="2">
                            <span
                              style={{
                                width: 14, height: 14, borderRadius: 4,
                                background: g.color, border: '1px solid var(--stroke)',
                                display: 'inline-block'
                              }}
                            />
                            <Text size="1" style={{ fontFamily: 'monospace' }}>{g.color}</Text>
                          </Flex>
                        </Table.Cell>
                        <Table.Cell><Text size="1" color="gray">{g.indices.length}</Text></Table.Cell>
                        <Table.Cell>
                          <Text size="1">
                            {regionLabel(region)}
                            {edited && <Badge ml="1" color="red" variant="soft">edited</Badge>}
                          </Text>
                        </Table.Cell>
                      </Table.Row>
                    )
                  })}
                </Table.Body>
              </Table.Root>
            </Box>
          </Flex>
        </Flex>
      )}
    </Flex>
  )
}
