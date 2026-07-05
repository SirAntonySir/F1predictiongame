import { useState } from 'react'
import { useMutation, useQuery } from '@tanstack/react-query'
import { AlertDialog, Badge, Button, Card, Flex, Heading, Table, Text, TextArea, TextField } from '@radix-ui/themes'
import { apiFetch, ApiError } from '../api/client'
import { useToast } from '../ui/toast'

type BroadcastResult =
  | { ok: true; sent: number }
  | { ok: false; reason: string; sent: number }

type DeviceRow = {
  userId: string
  platform: string
  tokenSuffix: string
  enabled: boolean
  timezone: string | null
  lastSeenAt: string
  disabledAt: string | null
}

const TITLE_MAX = 120
const BODY_MAX = 240
const ROUTE_MAX = 256

export function Notifications() {
  const { show } = useToast()
  const [title, setTitle] = useState('')
  const [body, setBody] = useState('')
  const [route, setRoute] = useState('')
  const [confirmOpen, setConfirmOpen] = useState(false)

  const devices = useQuery({
    queryKey: ['notif-devices'],
    queryFn: () => apiFetch<{ devices: DeviceRow[]; count: number }>('/admin/notifications/devices')
  })

  const broadcast = useMutation({
    mutationFn: () =>
      apiFetch<BroadcastResult>('/admin/notifications/broadcast', {
        method: 'POST',
        body: {
          title: title.trim(),
          body: body.trim(),
          ...(route.trim() ? { route: route.trim() } : {})
        }
      }),
    onSuccess: (res) => {
      if (res.ok) {
        show(`Broadcast sent to ${res.sent} user${res.sent === 1 ? '' : 's'}`, 'ok')
        setTitle('')
        setBody('')
        setRoute('')
      } else {
        show(res.reason, 'info')
      }
    },
    onError: (err) => {
      show(err instanceof ApiError ? err.message : 'Broadcast failed', 'error')
    }
  })

  const canSend =
    title.trim().length > 0 &&
    title.trim().length <= TITLE_MAX &&
    body.trim().length > 0 &&
    body.trim().length <= BODY_MAX &&
    route.trim().length <= ROUTE_MAX

  return (
    <Flex direction="column" gap="4">
      <Heading size="6" className="display">Notifications</Heading>
      <Text size="2" color="gray" style={{ maxWidth: 560 }}>
        Fire a one-off push to every opted-in device. Users with notifications disabled
        are skipped. If FCM isn't configured on the server the call is a safe no-op.
      </Text>

      <Card size="3" style={{ maxWidth: 560 }}>
        <Flex direction="column" gap="4">
          <Flex direction="column" gap="1">
            <Text as="label" size="2" weight="medium" htmlFor="notif-title">Title</Text>
            <TextField.Root
              id="notif-title"
              placeholder="Quali starts in 1 hour"
              value={title}
              maxLength={TITLE_MAX}
              onChange={(e) => setTitle(e.target.value)}
            />
            <Text size="1" color="gray" align="right">{title.length}/{TITLE_MAX}</Text>
          </Flex>

          <Flex direction="column" gap="1">
            <Text as="label" size="2" weight="medium" htmlFor="notif-body">Body</Text>
            <TextArea
              id="notif-body"
              placeholder="Get your picks in before lights out."
              value={body}
              maxLength={BODY_MAX}
              rows={3}
              onChange={(e) => setBody(e.target.value)}
            />
            <Text size="1" color="gray" align="right">{body.length}/{BODY_MAX}</Text>
          </Flex>

          <Flex direction="column" gap="1">
            <Text as="label" size="2" weight="medium" htmlFor="notif-route">
              Deep-link route <Text size="1" color="gray">(optional)</Text>
            </Text>
            <TextField.Root
              id="notif-route"
              placeholder="/predict"
              value={route}
              maxLength={ROUTE_MAX}
              onChange={(e) => setRoute(e.target.value)}
            />
            <Text size="1" color="gray">Where the app navigates when the notification is tapped.</Text>
          </Flex>

          <Flex justify="end">
            <AlertDialog.Root open={confirmOpen} onOpenChange={setConfirmOpen}>
              <AlertDialog.Trigger>
                <Button disabled={!canSend || broadcast.isPending}>
                  {broadcast.isPending ? 'Sending…' : 'Send broadcast'}
                </Button>
              </AlertDialog.Trigger>
              <AlertDialog.Content maxWidth="440px">
                <AlertDialog.Title>Send to every opted-in user?</AlertDialog.Title>
                <AlertDialog.Description size="2">
                  This delivers a real push notification to all devices with notifications
                  enabled. It can't be recalled.
                </AlertDialog.Description>
                <Card size="1" my="3" style={{ background: 'var(--surface-muted)' }}>
                  <Text size="2" weight="bold" as="div">{title.trim()}</Text>
                  <Text size="2" as="div" color="gray">{body.trim()}</Text>
                </Card>
                <Flex gap="2" justify="end">
                  <AlertDialog.Cancel>
                    <Button variant="soft" color="gray">Cancel</Button>
                  </AlertDialog.Cancel>
                  <AlertDialog.Action>
                    <Button onClick={() => broadcast.mutate()}>Send</Button>
                  </AlertDialog.Action>
                </Flex>
              </AlertDialog.Content>
            </AlertDialog.Root>
          </Flex>
        </Flex>
      </Card>

      <Card size="3" style={{ maxWidth: 640 }}>
        <Flex direction="column" gap="3">
          <Flex align="center" justify="between" gap="3">
            <Heading size="4">
              Registered devices{devices.data ? ` (${devices.data.count})` : ''}
            </Heading>
            <Button variant="surface" size="1" onClick={() => devices.refetch()} disabled={devices.isFetching}>
              {devices.isFetching ? '…' : 'Refresh'}
            </Button>
          </Flex>
          <Text size="1" color="gray">
            A phone appears here once it has launched the app, granted notification
            permission and registered its token. No rows → no token reached the backend yet.
          </Text>

          {devices.isLoading && <Text size="2">Loading…</Text>}
          {devices.error && <Text size="2" color="red">Failed to load devices.</Text>}
          {devices.data && devices.data.count === 0 && (
            <Text size="2" color="gray">No devices registered yet.</Text>
          )}
          {devices.data && devices.data.count > 0 && (
            <Table.Root variant="surface" size="1">
              <Table.Header>
                <Table.Row>
                  <Table.ColumnHeaderCell>User</Table.ColumnHeaderCell>
                  <Table.ColumnHeaderCell>Platform</Table.ColumnHeaderCell>
                  <Table.ColumnHeaderCell>Token</Table.ColumnHeaderCell>
                  <Table.ColumnHeaderCell>Opted in</Table.ColumnHeaderCell>
                  <Table.ColumnHeaderCell>Last seen</Table.ColumnHeaderCell>
                </Table.Row>
              </Table.Header>
              <Table.Body>
                {devices.data.devices.map((d) => (
                  <Table.Row key={d.tokenSuffix}>
                    <Table.Cell>{d.userId.slice(0, 8)}…</Table.Cell>
                    <Table.Cell>{d.platform}</Table.Cell>
                    <Table.Cell>…{d.tokenSuffix}</Table.Cell>
                    <Table.Cell>
                      {d.disabledAt
                        ? <Badge color="gray">dead token</Badge>
                        : d.enabled
                          ? <Badge color="green">yes</Badge>
                          : <Badge color="orange">disabled</Badge>}
                    </Table.Cell>
                    <Table.Cell>{new Date(d.lastSeenAt).toLocaleString()}</Table.Cell>
                  </Table.Row>
                ))}
              </Table.Body>
            </Table.Root>
          )}
        </Flex>
      </Card>
    </Flex>
  )
}
