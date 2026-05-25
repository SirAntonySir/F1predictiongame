import { describe, it, expect } from 'vitest'
import { scorePreseasonCategory } from '../../../src/preseason/index.js'

describe('scorePreseasonCategory dispatcher', () => {
  it('dispatches to scoreSinglePick for surprise', () => {
    const b = scorePreseasonCategory('surprise',
      { driverCode: 'VER', constructorId: 'red_bull' },
      { driverCode: 'VER', constructorId: 'red_bull' })
    expect(b.rule).toBe('preseason-surprise-v1')
  })

  it('dispatches for each of the 6 single-pick categories', () => {
    const cats = ['surprise', 'disappointment', 'dnf', 'poles', 'fastest_lap', 'wdc_wcc'] as const
    for (const c of cats) {
      const b = scorePreseasonCategory(c,
        { driverCode: null, constructorId: null },
        { driverCode: null, constructorId: null })
      expect(b.rule).toContain('preseason-')
    }
  })

  it('throws on unknown category', () => {
    expect(() => scorePreseasonCategory('not_a_real_cat' as any,
      { driverCode: null, constructorId: null },
      { driverCode: null, constructorId: null })).toThrow(/unknown/i)
  })
})
