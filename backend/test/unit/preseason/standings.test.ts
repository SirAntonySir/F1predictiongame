import { describe, it, expect } from 'vitest'
import { scoreStandings } from '../../../src/preseason/standings.js'

describe('scoreStandings', () => {
  const truthDrivers = [
    { position: 1, entityId: 'VER' },
    { position: 2, entityId: 'HAM' },
    { position: 3, entityId: 'NOR' },
    { position: 4, entityId: 'PIA' },
    { position: 5, entityId: 'RUS' }
  ]
  const truthTeams = [
    { position: 1, entityId: 'red_bull' },
    { position: 2, entityId: 'mercedes' },
    { position: 3, entityId: 'mclaren' }
  ]

  it('all 5 drivers correct + all 3 teams correct = 5*3 + 3*4 = 27', () => {
    const b = scoreStandings(
      [
        { position: 1, entityId: 'VER' },
        { position: 2, entityId: 'HAM' },
        { position: 3, entityId: 'NOR' },
        { position: 4, entityId: 'PIA' },
        { position: 5, entityId: 'RUS' }
      ],
      [
        { position: 1, entityId: 'red_bull' },
        { position: 2, entityId: 'mercedes' },
        { position: 3, entityId: 'mclaren' }
      ],
      truthDrivers, truthTeams
    )
    expect(b.pointsTotal).toBe(27)
    expect(b.rule).toBe('preseason-standings-v1')
    expect(b.perPosition).toHaveLength(8)
  })

  it('drivers all wrong + teams half correct', () => {
    const b = scoreStandings(
      [
        { position: 1, entityId: 'ZZZ' },
        { position: 2, entityId: 'ZZZ' },
        { position: 3, entityId: 'ZZZ' },
        { position: 4, entityId: 'ZZZ' },
        { position: 5, entityId: 'ZZZ' }
      ],
      [
        { position: 1, entityId: 'red_bull' },     // correct
        { position: 2, entityId: 'mclaren' },      // wrong
        { position: 3, entityId: 'mercedes' }      // wrong
      ],
      truthDrivers, truthTeams
    )
    // 0 driver points; 1 team correct = 4
    expect(b.pointsTotal).toBe(4)
  })

  it('shorter picks than truth: only scored positions count', () => {
    const b = scoreStandings(
      [{ position: 1, entityId: 'VER' }],
      [{ position: 1, entityId: 'red_bull' }],
      truthDrivers, truthTeams
    )
    expect(b.pointsTotal).toBe(3 + 4)  // 1 driver correct + 1 team correct
  })

  it('positions in pick missing from truth score 0 (but track)', () => {
    const b = scoreStandings(
      [{ position: 99, entityId: 'VER' }],
      [{ position: 99, entityId: 'red_bull' }],
      truthDrivers, truthTeams
    )
    expect(b.pointsTotal).toBe(0)
  })

  it('empty picks: 0', () => {
    const b = scoreStandings([], [], truthDrivers, truthTeams)
    expect(b.pointsTotal).toBe(0)
    expect(b.perPosition).toEqual([])
  })

  it('empty truth: 0 (e.g. season hasn\'t finished)', () => {
    const b = scoreStandings(
      [{ position: 1, entityId: 'VER' }],
      [{ position: 1, entityId: 'red_bull' }],
      [], []
    )
    expect(b.pointsTotal).toBe(0)
  })
})
