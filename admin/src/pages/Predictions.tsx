import { useState } from 'react'
import { Flex, Heading, Select, Table, Text } from '@radix-ui/themes'
import { useSeasons, useAdminSessions } from '../api/sessions'
import { useAdminPredictions } from '../api/admin'

// Only these session types are predictable, so only they have predictions.
const SCORABLE = new Set(['race', 'qualifying', 'sprint', 'sprint_quali'])

export function Predictions() {
  const seasonsQ = useSeasons()
  const season = seasonsQ.data?.find((s) => s.isCurrent)?.year
  const sessionsQ = useAdminSessions(season)
  const [picked, setPicked] = useState<string | null>(null)

  const scorable = (sessionsQ.data ?? [])
    .filter((s) => SCORABLE.has(s.type))
    .sort((a, b) => a.scheduledStart.localeCompare(b.scheduledStart))
  // Default to the most recent finished scorable session (most likely to hold picks).
  const finished = scorable.filter((s) => s.status === 'finished')
  const autoId = finished.length ? String(finished[finished.length - 1].id) : ''
  const sessionId = picked ?? autoId

  const predsQ = useAdminPredictions(sessionId)
  const selected = scorable.find((s) => String(s.id) === sessionId)

  return (
    <Flex direction="column" gap="4">
      <Flex align="center" justify="between" gap="3" wrap="wrap">
        <Heading size="6" className="display">Predictions</Heading>
        {scorable.length > 0 && (
          <Select.Root value={sessionId || undefined} onValueChange={setPicked}>
            <Select.Trigger placeholder="Pick a session" aria-label="Session" />
            <Select.Content>
              {scorable.map((s) => (
                <Select.Item key={s.id} value={String(s.id)}>
                  R{s.round} · {s.eventName} · {s.type}{s.status === 'finished' ? '' : ' (upcoming)'}
                </Select.Item>
              ))}
            </Select.Content>
          </Select.Root>
        )}
      </Flex>

      {!sessionId && <Text size="2" color="gray">Pick a session to view its predictions.</Text>}
      {selected && <Text size="1" className="label">{selected.eventName} · {selected.type}</Text>}
      {predsQ.isLoading && <Text size="2">Loading…</Text>}
      {predsQ.error && <Text size="2" color="red">Failed to load predictions.</Text>}

      {predsQ.data && (
        <>
          <Text size="1" className="label">{predsQ.data.predictions.length} prediction{predsQ.data.predictions.length === 1 ? '' : 's'}</Text>
          <Table.Root variant="surface">
            <Table.Header>
              <Table.Row>
                <Table.ColumnHeaderCell>Player</Table.ColumnHeaderCell>
                <Table.ColumnHeaderCell>Source</Table.ColumnHeaderCell>
                <Table.ColumnHeaderCell>Picks</Table.ColumnHeaderCell>
              </Table.Row>
            </Table.Header>
            <Table.Body>
              {predsQ.data.predictions.map((p) => (
                <Table.Row key={p.predictionId}>
                  <Table.Cell>{p.displayName}</Table.Cell>
                  <Table.Cell><Text size="1" color="gray">{p.source}</Text></Table.Cell>
                  <Table.Cell>
                    {p.picks.map((pk) => `P${pk.position} ${pk.driverCode}`).join(' · ') || '—'}
                  </Table.Cell>
                </Table.Row>
              ))}
            </Table.Body>
          </Table.Root>
        </>
      )}
    </Flex>
  )
}
