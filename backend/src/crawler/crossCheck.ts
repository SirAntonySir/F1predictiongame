import type { SessionResultRow } from '../domain/types.js'

export type CrossCheckResult =
  | { kind: 'match' }
  | { kind: 'length-differs'; jolpicaLength: number; openf1Length: number }
  | { kind: 'position-differs'; differences: Array<{ position: number; jolpica: string; openf1: string }> }

export function compareClassifications(
  jolpica: SessionResultRow[],
  openf1: SessionResultRow[]
): CrossCheckResult {
  if (jolpica.length !== openf1.length) {
    return { kind: 'length-differs', jolpicaLength: jolpica.length, openf1Length: openf1.length }
  }
  const jByPos = new Map(jolpica.map((r) => [r.position, r.driverCode]))
  const oByPos = new Map(openf1.map((r) => [r.position, r.driverCode]))
  const diffs: Array<{ position: number; jolpica: string; openf1: string }> = []
  for (const [pos, j] of jByPos) {
    const o = oByPos.get(pos)
    if (o && o !== j) diffs.push({ position: pos, jolpica: j, openf1: o })
  }
  return diffs.length === 0 ? { kind: 'match' } : { kind: 'position-differs', differences: diffs }
}
