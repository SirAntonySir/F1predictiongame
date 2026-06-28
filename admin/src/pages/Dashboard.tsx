import { useEffect, useState } from 'react'
import { Card, Flex, Heading, Text, Badge, Box } from '@radix-ui/themes'
import { useCrawlStatus } from '../api/hooks'
import { FetchControls } from '../components/FetchControls'
import { formatAbsolute, formatRelative } from '../utils/time'

export function Dashboard() {
  const { data, isLoading, error } = useCrawlStatus()
  const [now, setNow] = useState(() => Date.now())

  useEffect(() => {
    const id = setInterval(() => setNow(Date.now()), 1000)
    return () => clearInterval(id)
  }, [])

  return (
    <Flex direction="column" gap="4">
      <Heading size="6" className="display">Dashboard</Heading>
      {isLoading && <Text size="2">Loading crawl status…</Text>}
      {error && <Text size="2" color="red">Failed to load crawl status.</Text>}
      {data && (
        <Flex gap="4" wrap="wrap">
          <Card size="2" style={{ minWidth: 220 }}>
            <Text size="1" className="label">Last tick</Text>
            <Box mt="1">
              <Text size="3">{formatAbsolute(data.lastTickAt)}</Text>{' '}
              {data.lastTickStatus && (
                <Badge color={data.lastTickStatus === 'ok' ? 'green' : 'red'}>
                  {data.lastTickStatus}
                </Badge>
              )}
              {data.lastTickAt && (
                <Box mt="1">
                  <Text size="1" color="gray">{formatRelative(data.lastTickAt, now)}</Text>
                </Box>
              )}
            </Box>
          </Card>
          <Card size="2" style={{ minWidth: 220 }}>
            <Text size="1" className="label">Pending candidates</Text>
            <Box mt="1"><Text size="6" className="display">{data.pendingCandidates.length}</Text></Box>
          </Card>
          <Card size="2" style={{ minWidth: 220 }}>
            <Text size="1" className="label">Provisional sessions</Text>
            <Box mt="1"><Text size="6" className="display">{data.provisionalSessions.length}</Text></Box>
          </Card>
        </Flex>
      )}
      <FetchControls />
    </Flex>
  )
}
