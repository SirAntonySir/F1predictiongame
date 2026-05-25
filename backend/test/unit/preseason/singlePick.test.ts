import { describe, it, expect } from 'vitest'
import { scoreSinglePick } from '../../../src/preseason/singlePick.js'

describe('scoreSinglePick', () => {
  it('both match: driver +4, team +4 = 8', () => {
    const b = scoreSinglePick('surprise',
      { driverCode: 'VER', constructorId: 'red_bull' },
      { driverCode: 'VER', constructorId: 'red_bull' })
    expect(b.driver).toEqual({ picked: 'VER', truth: 'VER', correct: true, points: 4 })
    expect(b.team).toEqual({ picked: 'red_bull', truth: 'red_bull', correct: true, points: 4 })
    expect(b.pointsTotal).toBe(8)
    expect(b.rule).toBe('preseason-surprise-v1')
  })

  it('driver only match: 4', () => {
    const b = scoreSinglePick('dnf',
      { driverCode: 'VER', constructorId: 'red_bull' },
      { driverCode: 'VER', constructorId: 'mercedes' })
    expect(b.driver?.points).toBe(4)
    expect(b.team?.points).toBe(0)
    expect(b.pointsTotal).toBe(4)
    expect(b.rule).toBe('preseason-dnf-v1')
  })

  it('team only match: 4', () => {
    const b = scoreSinglePick('poles',
      { driverCode: 'HAM', constructorId: 'red_bull' },
      { driverCode: 'VER', constructorId: 'red_bull' })
    expect(b.driver?.points).toBe(0)
    expect(b.team?.points).toBe(4)
    expect(b.pointsTotal).toBe(4)
  })

  it('neither matches: 0', () => {
    const b = scoreSinglePick('fastest_lap',
      { driverCode: 'HAM', constructorId: 'mercedes' },
      { driverCode: 'VER', constructorId: 'red_bull' })
    expect(b.pointsTotal).toBe(0)
  })

  it('null truth (e.g. subjective not set yet): 0', () => {
    const b = scoreSinglePick('surprise',
      { driverCode: 'VER', constructorId: 'red_bull' },
      { driverCode: null, constructorId: null })
    expect(b.pointsTotal).toBe(0)
    expect(b.driver?.correct).toBe(false)
    expect(b.team?.correct).toBe(false)
  })

  it('null pick (user didn\'t pick): 0', () => {
    const b = scoreSinglePick('wdc_wcc',
      { driverCode: null, constructorId: null },
      { driverCode: 'VER', constructorId: 'red_bull' })
    expect(b.pointsTotal).toBe(0)
  })

  it('partial pick (driver only) with full truth: scores the matching half', () => {
    const b = scoreSinglePick('wdc_wcc',
      { driverCode: 'VER', constructorId: null },
      { driverCode: 'VER', constructorId: 'red_bull' })
    expect(b.driver?.points).toBe(4)
    expect(b.team?.points).toBe(0)
    expect(b.pointsTotal).toBe(4)
  })

  it('uses correct rule string per category', () => {
    expect(scoreSinglePick('surprise',       { driverCode: null, constructorId: null }, { driverCode: null, constructorId: null }).rule).toBe('preseason-surprise-v1')
    expect(scoreSinglePick('disappointment', { driverCode: null, constructorId: null }, { driverCode: null, constructorId: null }).rule).toBe('preseason-disappointment-v1')
    expect(scoreSinglePick('dnf',            { driverCode: null, constructorId: null }, { driverCode: null, constructorId: null }).rule).toBe('preseason-dnf-v1')
    expect(scoreSinglePick('poles',          { driverCode: null, constructorId: null }, { driverCode: null, constructorId: null }).rule).toBe('preseason-poles-v1')
    expect(scoreSinglePick('fastest_lap',    { driverCode: null, constructorId: null }, { driverCode: null, constructorId: null }).rule).toBe('preseason-fastest-lap-v1')
    expect(scoreSinglePick('wdc_wcc',        { driverCode: null, constructorId: null }, { driverCode: null, constructorId: null }).rule).toBe('preseason-wdc-wcc-v1')
  })
})
