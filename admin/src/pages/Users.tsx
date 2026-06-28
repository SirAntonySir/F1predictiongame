import { useState } from 'react'
import { AlertDialog, Button, Flex, Heading, Table, Text, TextField } from '@radix-ui/themes'
import { useAdminUsers, useDeleteUser } from '../api/admin'
import { UserEditDialog } from '../components/UserEditDialog'
import type { AdminUserRow } from '../api/types'

export function Users() {
  const [query, setQuery] = useState('')
  const { data, isLoading, error } = useAdminUsers(query)
  const del = useDeleteUser()
  const [editing, setEditing] = useState<AdminUserRow | null>(null)

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
                <Table.ColumnHeaderCell>Actions</Table.ColumnHeaderCell>
              </Table.Row>
            </Table.Header>
            <Table.Body>
              {data.users.map((u) => (
                <Table.Row key={u.id}>
                  <Table.Cell>{u.displayName}</Table.Cell>
                  <Table.Cell><Text size="1" color="gray">{u.email}</Text></Table.Cell>
                  <Table.Cell>{u.leagueCount}</Table.Cell>
                  <Table.Cell>
                    <Flex gap="1">
                      <Button size="1" variant="soft" onClick={() => setEditing(u)}>Edit</Button>
                      <AlertDialog.Root>
                        <AlertDialog.Trigger>
                          <Button size="1" variant="soft" color="red">Delete</Button>
                        </AlertDialog.Trigger>
                        <AlertDialog.Content maxWidth="460px">
                          <AlertDialog.Title>Delete {u.displayName}?</AlertDialog.Title>
                          <AlertDialog.Description size="2">
                            This permanently deletes the user and cascades: any league they own (and all of
                            its members&rsquo; predictions &amp; scores), plus their own predictions, scores and
                            devices. This changes live data and can&rsquo;t be undone.
                          </AlertDialog.Description>
                          <Flex gap="2" mt="3" justify="end">
                            <AlertDialog.Cancel><Button variant="soft" color="gray">Cancel</Button></AlertDialog.Cancel>
                            <AlertDialog.Action><Button color="red" onClick={() => del.mutate(u.id)}>Delete</Button></AlertDialog.Action>
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

      {editing && <UserEditDialog user={editing} onClose={() => setEditing(null)} />}
    </Flex>
  )
}
