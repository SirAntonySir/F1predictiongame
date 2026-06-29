import { useState } from 'react'
import { AlertDialog, Button, Flex, Heading, Select, Table, Text } from '@radix-ui/themes'
import { useSeasons, useAdminSessions } from '../api/sessions'
import { useAdminPredictions, useDeletePrediction } from '../api/admin'
import { PredictionEditDialog } from '../components/PredictionEditDialog'
import { PredictionAddDialog } from '../components/PredictionAddDialog'
import type { AdminPrediction } from '../api/types'

// Picks required per session type — only these types are predictable/scorable.
const PICKS_REQUIRED: Record<string, number> = { qualifying: 2, sprint_quali: 1, sprint: 3, race: 5 }
const SCORABLE = new Set(Object.keys(PICKS_REQUIRED))

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
  const del = useDeletePrediction(sessionId)
  const [editing, setEditing] = useState<AdminPrediction | null>(null)
  const [adding, setAdding] = useState(false)
  const existingUserIds = new Set((predsQ.data?.predictions ?? []).map((p) => p.userId))

  return (
    <Flex direction="column" gap="4">
      <Flex align="center" justify="between" gap="3" wrap="wrap">
        <Heading size="6" className="display">Predictions</Heading>
        <Flex align="center" gap="2">
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
          <Button size="2" disabled={!sessionId} onClick={() => setAdding(true)}>Add prediction</Button>
        </Flex>
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
                <Table.ColumnHeaderCell>Actions</Table.ColumnHeaderCell>
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
                  <Table.Cell>
                    <Flex gap="1">
                      <Button size="1" variant="soft" disabled={p.picks.length === 0} onClick={() => setEditing(p)}>Edit</Button>
                      <AlertDialog.Root>
                        <AlertDialog.Trigger>
                          <Button size="1" variant="soft" color="red">Delete</Button>
                        </AlertDialog.Trigger>
                        <AlertDialog.Content maxWidth="400px">
                          <AlertDialog.Title>Delete {p.displayName}&rsquo;s prediction?</AlertDialog.Title>
                          <AlertDialog.Description size="2">
                            Clears their picks for this session and re-scores it. This changes live data.
                          </AlertDialog.Description>
                          <Flex gap="2" mt="3" justify="end">
                            <AlertDialog.Cancel><Button variant="soft" color="gray">Cancel</Button></AlertDialog.Cancel>
                            <AlertDialog.Action><Button color="red" onClick={() => del.mutate(p.userId)}>Delete</Button></AlertDialog.Action>
                          </Flex>
                        </AlertDialog.Content>
                      </AlertDialog.Root>
                    </Flex>
                  </Table.Cell>
                </Table.Row>
              ))}
            </Table.Body>
          </Table.Root>
        </>
      )}

      {editing && (
        <PredictionEditDialog sessionId={sessionId} prediction={editing} onClose={() => setEditing(null)} />
      )}

      {adding && selected && (
        <PredictionAddDialog
          sessionId={sessionId}
          picksRequired={PICKS_REQUIRED[selected.type] ?? 0}
          existingUserIds={existingUserIds}
          onClose={() => setAdding(false)}
        />
      )}
    </Flex>
  )
}
