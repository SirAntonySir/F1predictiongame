import { useState } from 'react'
import { Flex, Heading, Table, Text, TextField } from '@radix-ui/themes'
import { useAdminUsers } from '../api/admin'

export function Users() {
  const [query, setQuery] = useState('')
  const { data, isLoading, error } = useAdminUsers(query)
  return (
    <Flex direction="column" gap="4">
      <Flex align="center" justify="between" gap="3">
        <Heading size="6" className="display">Users</Heading>
        <TextField.Root
          aria-label="Search users"
          placeholder="Search name or email"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          style={{ width: 240 }}
        />
      </Flex>

      {isLoading && <Text size="2">Loading…</Text>}
      {error && <Text size="2" color="red">Failed to load users.</Text>}

      {data && (
        <>
          <Text size="1" className="label">{data.total} user{data.total === 1 ? '' : 's'}</Text>
          <Table.Root variant="surface">
            <Table.Header>
              <Table.Row>
                <Table.ColumnHeaderCell>Name</Table.ColumnHeaderCell>
                <Table.ColumnHeaderCell>Email</Table.ColumnHeaderCell>
                <Table.ColumnHeaderCell>Leagues</Table.ColumnHeaderCell>
              </Table.Row>
            </Table.Header>
            <Table.Body>
              {data.users.map((u) => (
                <Table.Row key={u.id}>
                  <Table.Cell>{u.displayName}</Table.Cell>
                  <Table.Cell><Text size="1" color="gray">{u.email}</Text></Table.Cell>
                  <Table.Cell>{u.leagueCount}</Table.Cell>
                </Table.Row>
              ))}
            </Table.Body>
          </Table.Root>
        </>
      )}
    </Flex>
  )
}
