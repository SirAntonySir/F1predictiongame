import { describe, it, expect } from 'vitest'
import { pickCurrentLayoutId } from '../../src/circuits/crawler.js'
import type { UpstreamCircuit } from '../../src/circuits/client.js'

const c = (layouts: { layoutId: string; seasons: string }[]): UpstreamCircuit => ({
  id: 'x', name: 'X', countryId: null, latitude: 0, longitude: 0, layouts
})

describe('pickCurrentLayoutId', () => {
  it('picks the layout with the highest single year', () => {
    expect(pickCurrentLayoutId(c([
      { layoutId: 'x-1', seasons: '1995-2003' },
      { layoutId: 'x-2', seasons: '2004-2024' }
    ]))).toBe('x-2')
  })

  it('handles comma-separated season strings (max wins)', () => {
    expect(pickCurrentLayoutId(c([
      { layoutId: 'x-1', seasons: '1995,2026' },
      { layoutId: 'x-2', seasons: '2004-2020' }
    ]))).toBe('x-1')
  })

  it('returns null for an empty layout list', () => {
    expect(pickCurrentLayoutId(c([]))).toBeNull()
  })

  it('ignores malformed season tokens', () => {
    expect(pickCurrentLayoutId(c([
      { layoutId: 'x-1', seasons: 'soon' },
      { layoutId: 'x-2', seasons: '2026' }
    ]))).toBe('x-2')
  })
})
