import { Avatar, Badge, Box, Flex, Heading, Table, Text } from '@radix-ui/themes'
import { useAdminConstructors } from '../api/reference'

export function Constructors() {
  const { data, isLoading, error } = useAdminConstructors()

  return (
    <Flex direction="column" gap="4">
      <Heading size="6" className="display">Constructors</Heading>

      {isLoading && <Text size="2">Loading…</Text>}
      {error && <Text size="2" color="red">Failed to load constructors.</Text>}

      {data && (
        <>
          <Text size="1" className="label">{data.length} constructor{data.length === 1 ? '' : 's'}</Text>
          <Table.Root variant="surface">
            <Table.Header>
              <Table.Row>
                <Table.ColumnHeaderCell>Constructor</Table.ColumnHeaderCell>
                <Table.ColumnHeaderCell>Colour</Table.ColumnHeaderCell>
                <Table.ColumnHeaderCell>Nationality</Table.ColumnHeaderCell>
                <Table.ColumnHeaderCell>Image</Table.ColumnHeaderCell>
              </Table.Row>
            </Table.Header>
            <Table.Body>
              {data.map((c) => (
                <Table.Row key={c.id}>
                  <Table.Cell>
                    <Flex align="center" gap="2">
                      <Avatar size="1" radius="full" src={c.image ?? undefined} fallback={c.name[0] ?? '?'} />
                      {c.name}
                    </Flex>
                  </Table.Cell>
                  <Table.Cell>
                    {c.teamColour ? (
                      <Flex align="center" gap="2">
                        <Box
                          style={{
                            width: 14, height: 14, borderRadius: 4,
                            background: `#${c.teamColour}`, border: '1px solid var(--stroke)'
                          }}
                        />
                        <Text size="1" color="gray">#{c.teamColour}</Text>
                      </Flex>
                    ) : '—'}
                  </Table.Cell>
                  <Table.Cell>{c.nationality ?? '—'}</Table.Cell>
                  <Table.Cell>
                    {c.image
                      ? <Badge color={c.imageUrlOverride ? 'amber' : 'green'}>{c.imageUrlOverride ? 'override' : 'auto'}</Badge>
                      : <Badge color="gray">none</Badge>}
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
