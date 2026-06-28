import { useParams } from 'react-router-dom'
import { Flex, Heading, Table, Text } from '@radix-ui/themes'
import { useSession, useSessionResults } from '../api/sessions'
import { ActionButton } from '../components/ActionButton'

export function SessionDetail() {
  const { id: idParam } = useParams()
  const id = Number(idParam)
  const session = useSession(id)
  const results = useSessionResults(id)
  const resultsKey: string[][] = [['session-results', String(id)]]

  return (
    <Flex direction="column" gap="4">
      <Heading size="6" className="display">Session #{id}</Heading>
      {session.data && (
        <Text size="2" className="label">{session.data.type} · {session.data.status}</Text>
      )}
      <Flex gap="2">
        <ActionButton label="Re-fetch" path={`/admin/refetch-session/${id}`} successMessage="Session re-fetched" invalidateKeys={resultsKey} />
        <ActionButton label="Re-score" path={`/admin/rescore-session/${id}`} successMessage="Session re-scored" />
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
              </Table.Row>
            ))}
          </Table.Body>
        </Table.Root>
      )}
    </Flex>
  )
}
