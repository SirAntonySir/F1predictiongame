import { Link } from 'react-router-dom'
import { Badge, Flex, Heading, Table, Text } from '@radix-ui/themes'
import { useAdminLeagues } from '../api/leagues'

export function Leagues() {
  const { data, isLoading, error } = useAdminLeagues()
  return (
    <Flex direction="column" gap="4">
      <Heading size="6" className="display">Leagues</Heading>
      {isLoading && <Text size="2">Loading…</Text>}
      {error && <Text size="2" color="red">Failed to load leagues.</Text>}
      {data && (
        <Table.Root variant="surface">
          <Table.Header>
            <Table.Row>
              <Table.ColumnHeaderCell>Name</Table.ColumnHeaderCell>
              <Table.ColumnHeaderCell>Owner</Table.ColumnHeaderCell>
              <Table.ColumnHeaderCell>Members</Table.ColumnHeaderCell>
              <Table.ColumnHeaderCell>Join code</Table.ColumnHeaderCell>
            </Table.Row>
          </Table.Header>
          <Table.Body>
            {data.map((l) => (
              <Table.Row key={l.id}>
                <Table.Cell>
                  <Flex gap="2" align="center">
                    <Link to={`/leagues/${l.id}`}>{l.name}</Link>
                    {l.hasPassword && <Badge color="gray">🔒</Badge>}
                  </Flex>
                </Table.Cell>
                <Table.Cell>{l.ownerDisplayName}</Table.Cell>
                <Table.Cell>{l.memberCount}</Table.Cell>
                <Table.Cell><Text size="1" color="gray">{l.joinCode}</Text></Table.Cell>
              </Table.Row>
            ))}
          </Table.Body>
        </Table.Root>
      )}
    </Flex>
  )
}
