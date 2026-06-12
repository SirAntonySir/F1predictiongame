/**
 * Standalone 2025 Tippspiel audit.
 *
 * Runs the CANONICAL scoring engine (src/scoring) over the 2025 sheet and
 * compares engine-computed points to the hand-entered Excel point cells.
 *
 * Unlike importTippspiel/auditTippspiel (which are wired to season 2026, a
 * fixed 11-player roster, the 2026 event spellings, and a live DB), this
 * script is self-contained:
 *   - player names are READ from the sheet (col A at each stride-7 row),
 *   - actual results come from the sheet's own "Korrekt" block (rows 154-158),
 *   - no DB is touched.
 *
 * That makes the comparison apples-to-apples: same picks, same results the
 * maintainer scored against — only the scoring arithmetic differs.
 *
 * Run: npx tsx src/scripts/audit2025.ts [path-to-xlsx]
 */
import xlsxPkg from 'xlsx'
import os from 'node:os'
import path from 'node:path'
import fs from 'node:fs'
import { scoreSession } from '../scoring/index.js'
import type { Pick, Finisher } from '../scoring/types.js'
import type { SessionType } from '../domain/types.js'

const XLSX = xlsxPkg as typeof xlsxPkg & { readFile: (p: string) => xlsxPkg.WorkBook }

// ---- Sheet layout (identical structure to the 2026 parser) ----
const SHEET = 'Tippspiel 2025'
const RACE_HEADER_ROW = 68
const RACE_START_COL = 3
const RACE_COLS_EACH = 6
const PLAYER_FIRST_NAME_ROW = 70
const PLAYER_ROW_STRIDE = 7
const Q_OFF = 2, S_OFF = 3, R_OFF = 4
const PLAYER_COUNT = 12
const KORREKT_NAME_ROW = 154

// 2025 driver -> constructor. Only used for the team bonus. The constructor id
// value is arbitrary; only equality between two drivers matters. Swap-seat
// backmarkers (TSU/LAW/DOO/COL) are never P1 picks or race winners in 2025, so
// a static map is exact for every team-bonus evaluation that can occur.
const TEAM: Record<string, string> = {
  NOR: 'mclaren', PIA: 'mclaren',
  VER: 'red_bull',
  RUS: 'mercedes', ANT: 'mercedes',
  LEC: 'ferrari', HAM: 'ferrari',
  ALO: 'aston', STR: 'aston',
  GAS: 'alpine', DOO: 'alpine', COL: 'alpine',
  ALB: 'williams', SAI: 'williams',
  HUL: 'sauber', BOR: 'sauber',
  OCO: 'haas', BEA: 'haas',
  HAD: 'rb', LAW: 'rb', TSU: 'red_bull'
}
const ALL_DRIVERS = Object.keys(TEAM)
const teamOf = (code: string): string => TEAM[code] ?? `unknown_${code}`

type Sheet = xlsxPkg.WorkSheet
function readCell(ws: Sheet, row: number, col: number): string | null {
  const ref = XLSX.utils.encode_cell({ r: row - 1, c: col - 1 })
  const cell = (ws as Record<string, xlsxPkg.CellObject | undefined>)[ref]
  if (!cell || cell.v === null || cell.v === undefined) return null
  const s = String(cell.v).trim()
  return s.length === 0 ? null : s
}
function readNum(ws: Sheet, row: number, col: number): number {
  const s = readCell(ws, row, col)
  if (s === null) return 0
  const n = Number(s)
  return Number.isFinite(n) ? n : 0
}
const SKIP = (s: string | null) => s === null || s === '---'
const code = (s: string) => s.trim().toUpperCase()

/** Read an ordered pick/finisher list. [] = skipped. {partial:true} if half-filled. */
function readList(ws: Sheet, row: number, cols: number[], startPos: number):
  { picks: Pick[]; partial: boolean } {
  const cells = cols.map((c) => readCell(ws, row, c))
  if (cells.every(SKIP)) return { picks: [], partial: false }
  const picks: Pick[] = []
  let partial = false
  cells.forEach((c, i) => {
    if (SKIP(c)) { partial = true; return }
    picks.push({ position: startPos + i, driverCode: code(c!) })
  })
  return { picks, partial }
}

/** Build a finishers array from a Korrekt pick list, padded with all other
 *  drivers at a sentinel position so the engine can resolve any picked driver's
 *  team for the bonus without those padding rows affecting exact/wrong-pos. */
function finishers(korrekt: Pick[]): Finisher[] {
  const out: Finisher[] = korrekt.map((p) => ({
    position: p.position, driverCode: p.driverCode, constructorId: teamOf(p.driverCode)
  }))
  const present = new Set(out.map((f) => f.driverCode))
  for (const d of ALL_DRIVERS) {
    if (!present.has(d)) out.push({ position: 99, driverCode: d, constructorId: teamOf(d) })
  }
  return out
}

const total = (bd: { perPosition: { points: number }[]; teamBonus: { points: number } }) =>
  bd.perPosition.reduce((a, p) => a + p.points, 0) + bd.teamBonus.points

type Kind = 'quali' | 'sprintQuali' | 'sprint' | 'race'
const STYPE: Record<Kind, SessionType> = {
  quali: 'qualifying', sprintQuali: 'sprint_quali', sprint: 'sprint', race: 'race'
}
const EXPECT: Record<Kind, number> = { quali: 2, sprintQuali: 1, sprint: 3, race: 5 }

type RowResult = {
  player: string; event: string; kind: Kind
  picks: Pick[]; computed: number | null; note?: string
  breakdown?: ReturnType<typeof scoreSession>
}
type Bucket = {
  player: string; event: string
  exQuali: number; exSprint: number; exRace: number
  cQuali: number; cSprintQuali: number; cSprint: number; cRace: number
  hasSprint: boolean
}

function main(): number {
  const xlsxPath = process.argv[2] ?? path.join(os.homedir(), 'Downloads', 'Tippspiel-25.xlsx')
  if (!fs.existsSync(xlsxPath)) { console.error(`Not found: ${xlsxPath}`); return 2 }
  const wb = XLSX.readFile(xlsxPath)
  const ws = wb.Sheets[SHEET]
  if (!ws) { console.error(`Sheet "${SHEET}" not found`); return 2 }

  // Event header columns
  const events: { col: number; name: string }[] = []
  for (let col = RACE_START_COL; ; col += RACE_COLS_EACH) {
    const h = readCell(ws, RACE_HEADER_ROW, col)
    if (h === null) break
    events.push({ col, name: h })
  }

  // Players (names read from the sheet)
  const players: { name: string; nameRow: number }[] = []
  for (let i = 0; i < PLAYER_COUNT; i++) {
    const nameRow = PLAYER_FIRST_NAME_ROW + i * PLAYER_ROW_STRIDE
    const name = readCell(ws, nameRow, 1)
    if (name) players.push({ name, nameRow })
  }

  // Per-event Korrekt finishers
  const truth = new Map<string, { quali: Finisher[]; sprintQuali: Finisher[]; sprint: Finisher[]; race: Finisher[] }>()
  for (const ev of events) {
    const c = ev.col
    const kq  = readList(ws, KORREKT_NAME_ROW + Q_OFF, [c, c + 1], 1).picks
    const ksq = readList(ws, KORREKT_NAME_ROW + S_OFF, [c], 1).picks
    const ksr = readList(ws, KORREKT_NAME_ROW + S_OFF, [c + 2, c + 3, c + 4], 1).picks
    const kr  = readList(ws, KORREKT_NAME_ROW + R_OFF, [c, c + 1, c + 2, c + 3, c + 4], 1).picks
    truth.set(ev.name, {
      quali: finishers(kq), sprintQuali: finishers(ksq), sprint: finishers(ksr), race: finishers(kr)
    })
  }

  const rows: RowResult[] = []
  const buckets: Bucket[] = []
  const warnings: string[] = []

  for (const pl of players) {
    for (const ev of events) {
      const c = ev.col
      const qRow = pl.nameRow + Q_OFF, sRow = pl.nameRow + S_OFF, rRow = pl.nameRow + R_OFF
      const lists: Record<Kind, { picks: Pick[]; partial: boolean }> = {
        quali:       readList(ws, qRow, [c, c + 1], 1),
        sprintQuali: readList(ws, sRow, [c], 1),
        sprint:      readList(ws, sRow, [c + 2, c + 3, c + 4], 1),
        race:        readList(ws, rRow, [c, c + 1, c + 2, c + 3, c + 4], 1)
      }
      const ex = { quali: readNum(ws, qRow, c + 5), sprint: readNum(ws, sRow, c + 5), race: readNum(ws, rRow, c + 5) }
      const tr = truth.get(ev.name)!
      const finMap: Record<Kind, Finisher[]> = {
        quali: tr.quali, sprintQuali: tr.sprintQuali, sprint: tr.sprint, race: tr.race
      }

      const b: Bucket = {
        player: pl.name, event: ev.name,
        exQuali: ex.quali, exSprint: ex.sprint, exRace: ex.race,
        cQuali: 0, cSprintQuali: 0, cSprint: 0, cRace: 0, hasSprint: false
      }
      let any = false
      for (const kind of ['quali', 'sprintQuali', 'sprint', 'race'] as const) {
        const { picks, partial } = lists[kind]
        const fin = finMap[kind]
        if (picks.length === 0) continue
        any = true
        if (partial || picks.length !== EXPECT[kind]) {
          rows.push({ player: pl.name, event: ev.name, kind, picks, computed: null,
            note: `not scored: ${picks.length}/${EXPECT[kind]} picks` })
          warnings.push(`${pl.name} ${ev.name} ${kind}: ${picks.length}/${EXPECT[kind]} picks (partial)`)
          continue
        }
        if (fin.length === 0 || fin.every((f) => f.position === 99)) {
          rows.push({ player: pl.name, event: ev.name, kind, picks, computed: null, note: 'no Korrekt result' })
          continue
        }
        const bd = scoreSession(STYPE[kind], picks, fin)
        const t = total(bd)
        rows.push({ player: pl.name, event: ev.name, kind, picks, computed: t, breakdown: bd })
        if (kind === 'quali') b.cQuali = t
        else if (kind === 'sprintQuali') { b.cSprintQuali = t; b.hasSprint = true }
        else if (kind === 'sprint') { b.cSprint = t; b.hasSprint = true }
        else b.cRace = t
      }
      if (any) buckets.push(b)
    }
  }

  // ---- Aggregate ----
  const bByPE = new Map<string, Bucket>()
  for (const b of buckets) bByPE.set(`${b.player}|${b.event}`, b)
  const rByPE = new Map<string, RowResult[]>()
  for (const r of rows) {
    const k = `${r.player}|${r.event}`; const l = rByPE.get(k) ?? []; l.push(r); rByPE.set(k, l)
  }

  type T = { excel: number; comp: number }
  const totals = new Map<string, T>()
  let qD = 0, sD = 0, rD = 0, qDiff = 0, sDiff = 0, rDiff = 0, qC = 0, sC = 0, rC = 0
  for (const pl of players) {
    let e = 0, cp = 0
    for (const ev of events) {
      const b = bByPE.get(`${pl.name}|${ev.name}`); if (!b) continue
      const cSprint = b.cSprintQuali + b.cSprint
      const dq = b.cQuali - b.exQuali, ds = cSprint - b.exSprint, dr = b.cRace - b.exRace
      qC++; rC++
      if (dq === 0) qD++; else qDiff += Math.abs(dq)
      if (dr === 0) rD++; else rDiff += Math.abs(dr)
      if (b.hasSprint || b.exSprint > 0) { sC++; if (ds === 0) sD++; else sDiff += Math.abs(ds) }
      e += b.exQuali + b.exSprint + b.exRace
      cp += b.cQuali + cSprint + b.cRace
    }
    totals.set(pl.name, { excel: e, comp: cp })
  }

  // ---- Markdown ----
  const o: string[] = []
  o.push('# Tippspiel 2025 — engine vs Excel audit', '')
  o.push(`**Source:** \`${xlsxPath}\` · sheet \`${SHEET}\`  `)
  o.push(`**Players:** ${players.length} · **Events:** ${events.length} · **Truth:** sheet "Korrekt" block (rows 154–158)  `, '')
  o.push('## Headline', '')
  o.push(`- **Score-cell deltas** (engine − Excel): quali Σ|Δ|=${qDiff} (${qC - qD}/${qC} differ) · sprint-row Σ|Δ|=${sDiff} (${sC - sD}/${sC}) · race Σ|Δ|=${rDiff} (${rC - rD}/${rC}).`)
  if (warnings.length) o.push(`- **Unscoreable rows (partial picks):** ${warnings.length} — listed in footer.`)
  o.push('', '## Per-player totals', '', '| Player | Excel | Engine | Δ |', '|:---|---:|---:|---:|')
  for (const pl of players) {
    const t = totals.get(pl.name)!; const d = t.comp - t.excel
    o.push(`| ${pl.name} | ${t.excel} | ${t.comp} | **${d === 0 ? '0' : (d > 0 ? '+' : '') + d}** |`)
  }
  o.push('', '**Scoring rules (canonical engine):**', '')
  o.push('| Session | Exact | Wrong-pos | Team bonus |', '|:---|:---:|:---:|:---:|')
  o.push('| Qualifying (2) | 3 | 1 | +1 |', '| Sprint shootout (1) | 1 | — | +1 |', '| Sprint race (3) | 2 | 1 | +1 |', '| Race (5) | 3 | 1 | +2 |', '', '---', '')

  const fmtPicks = (p: Pick[]) => p.map((x) => x.driverCode).join(', ')
  const fmtBd = (bd?: ReturnType<typeof scoreSession>) => {
    if (!bd) return { perPos: '', tb: 0 }
    const perPos = bd.perPosition.map((x) => `${x.exact ? 'e' : x.wrongPos ? 'w' : '–'}(${x.driverCode})`).join(' ')
    return { perPos, tb: bd.teamBonus.applied ? bd.teamBonus.points : 0 }
  }
  const label: Record<Kind, string> = { quali: 'Quali', sprintQuali: 'Sprint Shootout', sprint: 'Sprint Race', race: 'Race' }

  for (const pl of players) {
    const t = totals.get(pl.name)!; const d = t.comp - t.excel
    const lines: string[] = []
    let anyEv = false
    for (const ev of events) {
      const list = rByPE.get(`${pl.name}|${ev.name}`); const b = bByPE.get(`${pl.name}|${ev.name}`)
      if (!list || !b) continue
      anyEv = true
      const cSprint = b.cSprintQuali + b.cSprint
      const sumE = b.exQuali + b.exSprint + b.exRace, sumC = b.cQuali + cSprint + b.cRace
      const sd = sumC - sumE
      lines.push(`#### ${ev.name} · Excel ${sumE} → Engine ${sumC} (Δ ${sd === 0 ? '0' : (sd > 0 ? '+' : '') + sd})`, '')
      lines.push('| Session | Picks | Breakdown | TB | Excel | Engine | Δ |', '|:---|:---|:---|:---:|---:|---:|---:|')
      const byKind = new Map<Kind, RowResult>(); for (const r of list) byKind.set(r.kind, r)
      for (const kind of ['quali', 'sprintQuali', 'sprint', 'race'] as const) {
        const r = byKind.get(kind); if (!r) continue
        const { perPos, tb } = fmtBd(r.breakdown)
        let exC = '', coC = '', dC = ''
        if (kind === 'quali') { const dd = b.cQuali - b.exQuali; exC = `${b.exQuali}`; coC = `${b.cQuali}`; dC = dd === 0 ? '0' : (dd > 0 ? '+' : '') + dd }
        else if (kind === 'race') { const dd = b.cRace - b.exRace; exC = `${b.exRace}`; coC = `${b.cRace}`; dC = dd === 0 ? '0' : (dd > 0 ? '+' : '') + dd }
        else if (kind === 'sprintQuali') { const dd = cSprint - b.exSprint; exC = `${b.exSprint} *row*`; coC = `${cSprint}`; dC = dd === 0 ? '0' : (dd > 0 ? '+' : '') + dd }
        else { exC = '↳'; coC = '↳'; dC = '↳' }
        const note = r.note ? ` _(${r.note})_` : ''
        lines.push(`| ${label[kind]} | ${fmtPicks(r.picks)}${note} | ${perPos} | ${tb} | ${exC} | ${coC} | ${dC} |`)
      }
      lines.push('')
    }
    if (anyEv) { o.push(`## ${pl.name} — Excel ${t.excel} / Engine ${t.comp} (Δ **${d === 0 ? '0' : (d > 0 ? '+' : '') + d}**)`, ''); o.push(...lines) }
  }
  if (warnings.length) { o.push('---', '', '### Unscoreable (partial pick lists)', ''); for (const w of warnings) o.push(`- ${w}`) }

  const outPath = path.join(process.cwd(), 'tippspiel-2025-audit.md')
  fs.writeFileSync(outPath, o.join('\n'))

  // Console summary
  console.log(`Wrote ${outPath}`)
  console.log(`\nPer-player Excel vs Engine:`)
  for (const pl of players) {
    const t = totals.get(pl.name)!; const d = t.comp - t.excel
    console.log(`  ${pl.name.padEnd(8)} excel=${String(t.excel).padStart(4)} engine=${String(t.comp).padStart(4)} Δ=${d === 0 ? '0' : (d > 0 ? '+' : '') + d}`)
  }
  console.log(`\nScore-cell deltas (engine−excel): quali Σ|Δ|=${qDiff} (${qC - qD}/${qC}), sprint Σ|Δ|=${sDiff} (${sC - sD}/${sC}), race Σ|Δ|=${rDiff} (${rC - rD}/${rC})`)
  console.log(`Unscoreable partial rows: ${warnings.length}`)
  return 0
}

process.exit(main())
