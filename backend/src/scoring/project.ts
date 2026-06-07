import type { SessionResultRow, SessionType } from '../domain/types.js'
import type { Finisher, Pick } from './types.js'
import { scoreSession, picksRequiredFor } from './index.js'

/** Project a point total from a (possibly live) order, using the canonical
 *  backend scoring engine. Returns null when the type isn't scorable or the
 *  pick count doesn't match what the type expects (so partial/empty picks
 *  don't throw). The order is treated as the finishers. */
export function projectTotal(
  type: SessionType,
  picks: Pick[],
  order: SessionResultRow[]
): number | null {
  const required = picksRequiredFor(type)
  if (required == null) return null
  if (picks.length !== required) return null
  const finishers: Finisher[] = order.map((r) => ({
    position: r.position, driverCode: r.driverCode, constructorId: r.constructorId
  }))
  const b = scoreSession(type, picks, finishers)
  return b.perPosition.reduce((s, x) => s + x.points, 0) + b.teamBonus.points
}
