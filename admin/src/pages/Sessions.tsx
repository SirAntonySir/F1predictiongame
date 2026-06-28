import { Link } from 'react-router-dom'
import { Badge, Flex, Heading, Table, Text } from '@radix-ui/themes'
import { useAdminSessions } from '../api/sessions'

export function Sessions() {
  const { data, isLoading, error } = useAdminSessions()
  return (
    <Flex direction="column" gap="4">
      <Heading size="6" className="display">Sessions</Heading>
      {isLoading && <Text size="2">Loading…</Text>}
      {error && <Text size="2" color="red">Failed to load sessions.</Text>}
      {data && (
        <Table.Root variant="surface">
          <Table.Header>
            <Table.Row>
              <Table.ColumnHeaderCell>Round</Table.ColumnHeaderCell>
              <Table.ColumnHeaderCell>Event</Table.ColumnHeaderCell>
              <Table.ColumnHeaderCell>Type</Table.ColumnHeaderCell>
              <Table.ColumnHeaderCell>Status</Table.ColumnHeaderCell>
              <Table.ColumnHeaderCell>Results</Table.ColumnHeaderCell>
            </Table.Row>
          </Table.Header>
          <Table.Body>
            {data.map((s) => (
              <Table.Row key={s.id}>
                <Table.Cell>{s.round}</Table.Cell>
                <Table.Cell><Link to={`/sessions/${s.id}`}>{s.eventName}</Link></Table.Cell>
                <Table.Cell>{s.type}</Table.Cell>
                <Table.Cell>
                  <Flex gap="1">
                    <Badge color={s.status === 'finished' ? 'gray' : 'blue'}>{s.status}</Badge>
                    {s.provisional && <Badge color="orange">provisional</Badge>}
                  </Flex>
                </Table.Cell>
                <Table.Cell>{s.resultCount}</Table.Cell>
              </Table.Row>
            ))}
          </Table.Body>
        </Table.Root>
      )}
    </Flex>
  )
}
