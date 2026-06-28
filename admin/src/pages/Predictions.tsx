import { useState } from 'react'
import { Flex, Heading, Table, Text, TextField } from '@radix-ui/themes'
import { useAdminPredictions } from '../api/admin'

export function Predictions() {
  const [sessionId, setSessionId] = useState('')
  const { data, isLoading, error } = useAdminPredictions(sessionId)
  return (
    <Flex direction="column" gap="4">
      <Flex align="center" justify="between" gap="3">
        <Heading size="6" className="display">Predictions</Heading>
        <TextField.Root
          aria-label="Session id"
          placeholder="Session id"
          value={sessionId}
          onChange={(e) => setSessionId(e.target.value)}
          style={{ width: 160 }}
        />
      </Flex>

      {!sessionId.trim() && <Text size="2" color="gray">Enter a session id to view its predictions.</Text>}
      {isLoading && <Text size="2">Loading…</Text>}
      {error && <Text size="2" color="red">Failed to load predictions.</Text>}

      {data && (
        <>
          <Text size="1" className="label">{data.predictions.length} prediction{data.predictions.length === 1 ? '' : 's'}</Text>
          <Table.Root variant="surface">
            <Table.Header>
              <Table.Row>
                <Table.ColumnHeaderCell>Player</Table.ColumnHeaderCell>
                <Table.ColumnHeaderCell>Source</Table.ColumnHeaderCell>
                <Table.ColumnHeaderCell>Picks</Table.ColumnHeaderCell>
              </Table.Row>
            </Table.Header>
            <Table.Body>
              {data.predictions.map((p) => (
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
