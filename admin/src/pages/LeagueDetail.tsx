import { useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { AlertDialog, Badge, Button, Card, Flex, Heading, Table, Text, TextField } from '@radix-ui/themes'
import {
  useAdminLeague, useUpdateLeague, useRegenerateCode, useDeleteLeague, useKickMember
} from '../api/leagues'

export function LeagueDetail() {
  const { id = '' } = useParams()
  const navigate = useNavigate()
  const detail = useAdminLeague(id)
  const update = useUpdateLeague(id)
  const regen = useRegenerateCode(id)
  const del = useDeleteLeague(id)
  const kick = useKickMember(id)
  const [name, setName] = useState('')
  const [password, setPassword] = useState('')

  const league = detail.data?.league
  const members = detail.data?.members ?? []

  return (
    <Flex direction="column" gap="4">
      <Heading size="6" className="display">League</Heading>
      {detail.isLoading && <Text size="2">Loading…</Text>}
      {detail.error && <Text size="2" color="red">Failed to load league.</Text>}
      {league && (
        <>
          <Card size="2">
            <Flex direction="column" gap="3">
              <Flex gap="3" align="center" wrap="wrap">
                <Heading size="4">{league.name}</Heading>
                <Badge color="gray">code: {league.joinCode}</Badge>
                {league.hasPassword && <Badge color="gray">🔒 password set</Badge>}
              </Flex>

              <Text size="1" className="label">Edit</Text>
              <Flex gap="2" wrap="wrap" align="end">
                <label>
                  <Text size="1" className="label">Name</Text>
                  <TextField.Root mt="1" aria-label="Name" value={name} placeholder={league.name} onChange={(e) => setName(e.target.value)} />
                </label>
                <label>
                  <Text size="1" className="label">Set password</Text>
                  <TextField.Root mt="1" aria-label="Set password" type="password" value={password} placeholder="(unchanged)" onChange={(e) => setPassword(e.target.value)} />
                </label>
                <Button
                  disabled={update.isPending}
                  onClick={() => update.mutate(
                    { ...(name ? { name } : {}), ...(password ? { password } : {}) },
                    { onSuccess: () => { setName(''); setPassword('') } }
                  )}
                >Save</Button>
                {league.hasPassword && (
                  <Button variant="soft" color="gray" disabled={update.isPending} onClick={() => update.mutate({ password: null })}>
                    Clear password
                  </Button>
                )}
              </Flex>

              <Flex gap="2">
                <Button variant="surface" disabled={regen.isPending} onClick={() => regen.mutate()}>Regenerate code</Button>
                <AlertDialog.Root>
                  <AlertDialog.Trigger>
                    <Button color="red" variant="soft">Delete league</Button>
                  </AlertDialog.Trigger>
                  <AlertDialog.Content maxWidth="440px">
                    <AlertDialog.Title>Delete &ldquo;{league.name}&rdquo;?</AlertDialog.Title>
                    <AlertDialog.Description size="2">
                      Permanently deletes the league and all its memberships, predictions and imports. This changes live data and can&rsquo;t be undone.
                    </AlertDialog.Description>
                    <Flex gap="2" mt="3" justify="end">
                      <AlertDialog.Cancel><Button variant="soft" color="gray">Cancel</Button></AlertDialog.Cancel>
                      <AlertDialog.Action>
                        <Button color="red" onClick={() => del.mutate(undefined, { onSuccess: () => navigate('/leagues') })}>Delete</Button>
                      </AlertDialog.Action>
                    </Flex>
                  </AlertDialog.Content>
                </AlertDialog.Root>
              </Flex>
            </Flex>
          </Card>

          <Text size="2" className="label">Members ({members.length})</Text>
          <Table.Root variant="surface">
            <Table.Header>
              <Table.Row>
                <Table.ColumnHeaderCell>Name</Table.ColumnHeaderCell>
                <Table.ColumnHeaderCell>Email</Table.ColumnHeaderCell>
                <Table.ColumnHeaderCell>Role</Table.ColumnHeaderCell>
                <Table.ColumnHeaderCell>Actions</Table.ColumnHeaderCell>
              </Table.Row>
            </Table.Header>
            <Table.Body>
              {members.map((m) => (
                <Table.Row key={m.userId}>
                  <Table.Cell>{m.displayName}</Table.Cell>
                  <Table.Cell><Text size="1" color="gray">{m.email}</Text></Table.Cell>
                  <Table.Cell><Badge color={m.role === 'owner' ? 'orange' : 'gray'}>{m.role}</Badge></Table.Cell>
                  <Table.Cell>
                    {m.role === 'owner' ? (
                      <Text size="1" color="gray">—</Text>
                    ) : (
                      <AlertDialog.Root>
                        <AlertDialog.Trigger>
                          <Button size="1" variant="soft" color="red">Kick</Button>
                        </AlertDialog.Trigger>
                        <AlertDialog.Content maxWidth="380px">
                          <AlertDialog.Title>Remove {m.displayName}?</AlertDialog.Title>
                          <AlertDialog.Description size="2">They&rsquo;ll be removed from this league.</AlertDialog.Description>
                          <Flex gap="2" mt="3" justify="end">
                            <AlertDialog.Cancel><Button variant="soft" color="gray">Cancel</Button></AlertDialog.Cancel>
                            <AlertDialog.Action><Button color="red" onClick={() => kick.mutate(m.userId)}>Kick</Button></AlertDialog.Action>
                          </Flex>
                        </AlertDialog.Content>
                      </AlertDialog.Root>
                    )}
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
