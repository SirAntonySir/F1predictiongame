import { Flex, Text } from '@radix-ui/themes'
import type { ScoreBreakdown as ScoreBreakdownType, SessionResultRow } from '../api/types'

type Props = {
  breakdown: ScoreBreakdownType
  results: SessionResultRow[]
  pointsTotal: number | null
}

// exact = correct driver at that position; wrong = correct driver but a
// different position (still inside the top N); miss = driver outside the top N.
const OUTCOME = {
  exact: { label: 'exact', color: 'green' as const },
  wrong: { label: 'wrong', color: 'amber' as const },
  miss: { label: 'miss', color: 'gray' as const }
}

/**
 * Renders a single prediction's scoring calculation: one line per pick showing
 * the picked driver against the actual finisher, the outcome, and the points —
 * then the team bonus and the total. Every number comes straight from the
 * stored `breakdown`; `results` is used only to make each verdict legible.
 */
export function ScoreBreakdown({ breakdown, results, pointsTotal }: Props) {
  const finisherAt = (position: number) => results.find((r) => r.position === position)
  const finishOf = (driverCode: string) => results.find((r) => r.driverCode === driverCode)?.position

  const computed = breakdown.perPosition.reduce((s, p) => s + p.points, 0) + breakdown.teamBonus.points
  const total = pointsTotal ?? computed

  const tb = breakdown.teamBonus
  // "P1 result" = the driver in the top spot (race/sprint winner, or pole in
  // qualifying) — the neutral phrasing holds across every scorable session type.
  const teamBonusText = tb.applied
    ? `Team bonus +${tb.points} — P1 pick's team matched the P1 result`
    : `Team bonus +${tb.points} — P1 pick's team didn't match the P1 result`

  return (
    <Flex direction="column" gap="1" py="1">
      {breakdown.perPosition.map((p) => {
        const outcome = p.exact ? OUTCOME.exact : p.wrongPos ? OUTCOME.wrong : OUTCOME.miss
        const actual = finisherAt(p.position)
        const actualText = actual ? `actual ${actual.driverCode}` : 'no result'
        // For a non-exact hit, show where the picked driver actually finished so
        // the wrong / miss verdict explains itself.
        const finishedAt = finishOf(p.driverCode)
        const note = !p.exact && finishedAt ? ` (${p.driverCode} finished P${finishedAt})` : ''
        const line = `P${p.position} ${p.driverCode} · ${actualText}${note} · ${outcome.label} +${p.points}`
        return <Text key={p.position} size="1" color={outcome.color}>{line}</Text>
      })}
      <Text size="1" color={tb.applied ? 'green' : 'gray'}>{teamBonusText}</Text>
      <Text size="1" weight="bold">Total {total} pts</Text>
    </Flex>
  )
}
