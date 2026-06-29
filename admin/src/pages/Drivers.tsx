import { useState } from 'react'
import { Avatar, Badge, Flex, Heading, Table, Text, TextField } from '@radix-ui/themes'
import { useAdminDrivers } from '../api/reference'

export function Drivers() {
  const { data, isLoading, error } = useAdminDrivers()
  const [query, setQuery] = useState('')

  const q = query.trim().toLowerCase()
  const drivers = (data ?? []).filter(
    (d) => !q || `${d.givenName} ${d.familyName} ${d.code}`.toLowerCase().includes(q)
  )

  return (
    <Flex direction="column" gap="4">
      <Flex align="center" justify="between" gap="3">
        <Heading size="6" className="display">Drivers</Heading>
        <TextField.Root
          aria-label="Search drivers"
          placeholder="Search name or code"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          style={{ width: 240 }}
        />
      </Flex>

      {isLoading && <Text size="2">Loading…</Text>}
      {error && <Text size="2" color="red">Failed to load drivers.</Text>}

      {data && (
        <>
          <Text size="1" className="label">{drivers.length} driver{drivers.length === 1 ? '' : 's'}</Text>
          <Table.Root variant="surface">
            <Table.Header>
              <Table.Row>
                <Table.ColumnHeaderCell>Driver</Table.ColumnHeaderCell>
                <Table.ColumnHeaderCell>Code</Table.ColumnHeaderCell>
                <Table.ColumnHeaderCell>No.</Table.ColumnHeaderCell>
                <Table.ColumnHeaderCell>Nationality</Table.ColumnHeaderCell>
                <Table.ColumnHeaderCell>Image</Table.ColumnHeaderCell>
              </Table.Row>
            </Table.Header>
            <Table.Body>
              {drivers.map((d) => (
                <Table.Row key={d.code}>
                  <Table.Cell>
                    <Flex align="center" gap="2">
                      <Avatar
                        size="1"
                        radius="full"
                        src={d.image ?? undefined}
                        fallback={(d.givenName[0] ?? '') + (d.familyName[0] ?? '')}
                      />
                      {d.givenName} {d.familyName}
                    </Flex>
                  </Table.Cell>
                  <Table.Cell><Text size="1" color="gray">{d.code}</Text></Table.Cell>
                  <Table.Cell>{d.permanentNumber ?? '—'}</Table.Cell>
                  <Table.Cell>{d.nationality ?? '—'}</Table.Cell>
                  <Table.Cell>
                    {d.image
                      ? <Badge color={d.imageUrlOverride ? 'amber' : 'green'}>{d.imageUrlOverride ? 'override' : 'auto'}</Badge>
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
