export type Pick = { position: number; driverCode: string }
export type Finisher = { position: number; driverCode: string; constructorId: string }

export type ScoreBreakdownPerPosition = {
  position: number
  exact: boolean
  wrongPos: boolean
  points: number
}

export type ScoreBreakdown = {
  perPosition: ScoreBreakdownPerPosition[]
  teamBonus: { applied: boolean; points: number }
  rule: string
}
