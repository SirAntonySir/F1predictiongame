import { describe, it, expect } from 'vitest'
import { formatComparisonTable, type ComparisonRow } from '../../../src/scripts/tippspiel/validator.js'

describe('formatComparisonTable', () => {
  it('renders headers + one row per player with X/Y per event', () => {
    const rows: ComparisonRow[] = [
      {
        excelName: 'Jan',
        perEvent: {
          'Australia':       { excel: 13, app: 13, hasApp: true },
          'Australian GP':   { excel: 0, app: 0, hasApp: false } // hasApp=false → "n/a"
        },
        excelTotal: 13,
        appTotal:   13
      }
    ]
    const events = ['Australia', 'Australian GP']
    const out = formatComparisonTable(rows, events)
    expect(out).toMatch(/Jan/)
    expect(out).toMatch(/13\/13/)
    expect(out).toMatch(/n\/a/)
    expect(out).toMatch(/Σ Excel/)
    expect(out).toMatch(/Total mismatches:/)
  })

  it('reports mismatches in the trailing summary line', () => {
    const rows: ComparisonRow[] = [
      {
        excelName: 'Lukas',
        perEvent: { 'China': { excel: 16, app: 12, hasApp: true } },
        excelTotal: 16,
        appTotal: 12
      }
    ]
    const out = formatComparisonTable(rows, ['China'])
    expect(out).toMatch(/Total mismatches: 1/)
  })
})
