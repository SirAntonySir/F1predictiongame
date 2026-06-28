import { useState } from 'react'
import { Link } from 'react-router-dom'
import { Badge, Card, Flex, Heading, Select, Table, Text } from '@radix-ui/themes'
import { useAdminSessions, useSeasons } from '../api/sessions'
import type { AdminSessionRow } from '../api/types'

type EventGroup = { round: number; eventName: string; sessions: AdminSessionRow[] }

// Group the flat session list into events (by round), preserving the
// scheduled-start order the API returns within each event.
function groupByEvent(rows: AdminSessionRow[]): EventGroup[] {
  const byRound = new Map<number, EventGroup>()
  for (const s of rows) {
    let g = byRound.get(s.round)
    if (!g) {
      g = { round: s.round, eventName: s.eventName, sessions: [] }
      byRound.set(s.round, g)
    }
    g.sessions.push(s)
  }
  return [...byRound.values()].sort((a, b) => a.round - b.round)
}

export function Sessions() {
  const seasonsQ = useSeasons()
  // null = "follow the current season"; a number = an explicit pick.
  const [picked, setPicked] = useState<number | null>(null)
  const season = picked ?? seasonsQ.data?.find((s) => s.isCurrent)?.year
  const { data, isLoading, error } = useAdminSessions(season)
  const events = groupByEvent(data ?? [])

  return (
    <Flex direction="column" gap="4">
      <Flex align="center" justify="between" gap="3">
        <Heading size="6" className="display">Sessions</Heading>
        {seasonsQ.data && season !== undefined && (
          <Select.Root value={String(season)} onValueChange={(v) => setPicked(Number(v))}>
            <Select.Trigger aria-label="Season" />
            <Select.Content>
              {seasonsQ.data
                .slice()
                .sort((a, b) => b.year - a.year)
                .map((s) => (
                  <Select.Item key={s.year} value={String(s.year)}>
                    {s.year}{s.isCurrent ? ' · current' : ''}
                  </Select.Item>
                ))}
            </Select.Content>
          </Select.Root>
        )}
      </Flex>

      {isLoading && <Text size="2">Loading…</Text>}
      {error && <Text size="2" color="red">Failed to load sessions.</Text>}

      {data && events.map((ev) => (
        <Card key={ev.round} size="2">
          <Flex direction="column" gap="2">
            <Text size="2" className="label">R{ev.round} · {ev.eventName}</Text>
            <Table.Root>
              <Table.Body>
                {ev.sessions.map((s) => (
                  <Table.Row key={s.id}>
                    <Table.Cell><Link to={`/sessions/${s.id}`}>{s.type}</Link></Table.Cell>
                    <Table.Cell>
                      <Flex gap="1">
                        <Badge color={s.status === 'finished' ? 'gray' : 'blue'}>{s.status}</Badge>
                        {s.provisional && <Badge color="orange">provisional</Badge>}
                      </Flex>
                    </Table.Cell>
                    <Table.Cell>{s.resultCount} result{s.resultCount === 1 ? '' : 's'}</Table.Cell>
                  </Table.Row>
                ))}
              </Table.Body>
            </Table.Root>
          </Flex>
        </Card>
      ))}
    </Flex>
  )
}
