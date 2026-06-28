import { useState } from 'react'
import { useParams } from 'react-router-dom'
import { Button, Flex, Heading, Table, Text } from '@radix-ui/themes'
import { useSession, useSessionResults, useDeleteResult } from '../api/sessions'
import { ActionButton } from '../components/ActionButton'
import { ResultEditDialog } from '../components/ResultEditDialog'
import type { SessionResultRow } from '../api/types'

export function SessionDetail() {
  const { id: idParam } = useParams()
  const id = Number(idParam)
  const session = useSession(id)
  const results = useSessionResults(id)
  const resultsKey: unknown[][] = [['session-results', String(id)]]
  const del = useDeleteResult(id)
  const [editing, setEditing] = useState<{ mode: 'edit' | 'add'; row?: SessionResultRow } | null>(null)

  return (
    <Flex direction="column" gap="4">
      <Heading size="6" className="display">Session #{id}</Heading>
      {session.data && (
        <Text size="2" className="label">{session.data.type} · {session.data.status}</Text>
      )}
      <Flex gap="2">
        <ActionButton label="Re-fetch" path={`/admin/refetch-session/${id}`} successMessage="Session re-fetched" invalidateKeys={resultsKey} />
        <ActionButton label="Re-score" path={`/admin/rescore-session/${id}`} successMessage="Session re-scored" />
        <Button variant="surface" onClick={() => setEditing({ mode: 'add' })}>Add result</Button>
      </Flex>
      {results.isLoading && <Text size="2">Loading results…</Text>}
      {results.error && <Text size="2" color="red">Failed to load results.</Text>}
      {results.data && (
        <Table.Root variant="surface">
          <Table.Header>
            <Table.Row>
              <Table.ColumnHeaderCell>Pos</Table.ColumnHeaderCell>
              <Table.ColumnHeaderCell>Driver</Table.ColumnHeaderCell>
              <Table.ColumnHeaderCell>Constructor</Table.ColumnHeaderCell>
              <Table.ColumnHeaderCell>Pts</Table.ColumnHeaderCell>
              <Table.ColumnHeaderCell>Status</Table.ColumnHeaderCell>
              <Table.ColumnHeaderCell>Actions</Table.ColumnHeaderCell>
            </Table.Row>
          </Table.Header>
          <Table.Body>
            {results.data.map((r) => (
              <Table.Row key={r.position}>
                <Table.Cell>{r.position}</Table.Cell>
                <Table.Cell>{r.driverName} <Text size="1" color="gray">{r.driverCode}</Text></Table.Cell>
                <Table.Cell>{r.constructorName}</Table.Cell>
                <Table.Cell>{r.points ?? '—'}</Table.Cell>
                <Table.Cell>{r.status ?? '—'}</Table.Cell>
                <Table.Cell>
                  <Flex gap="1">
                    <Button size="1" variant="soft" onClick={() => setEditing({ mode: 'edit', row: r })}>Edit</Button>
                    <Button size="1" variant="soft" color="red" onClick={() => del.mutate(r.position)}>Delete</Button>
                  </Flex>
                </Table.Cell>
              </Table.Row>
            ))}
          </Table.Body>
        </Table.Root>
      )}
      {editing && (
        <ResultEditDialog sessionId={id} mode={editing.mode} initial={editing.row} onClose={() => setEditing(null)} />
      )}
    </Flex>
  )
}
