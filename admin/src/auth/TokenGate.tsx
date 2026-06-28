import { useState, type ReactNode } from 'react'
import { Box, Button, Card, Flex, Heading, Text, TextField } from '@radix-ui/themes'
import { apiFetch, getToken, setToken, ApiError } from '../api/client'

export function TokenGate({ children }: { children: ReactNode }) {
  const [unlocked, setUnlocked] = useState(() => getToken() !== null)
  const [value, setValue] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  if (unlocked) return <>{children}</>

  async function submit(e: React.FormEvent) {
    e.preventDefault()
    setBusy(true)
    setError(null)
    try {
      // Validate by hitting a token-gated endpoint with the candidate token.
      await apiFetch('/admin/crawl/status', { token: value })
      setToken(value)
      setUnlocked(true)
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Could not reach the backend')
    } finally {
      setBusy(false)
    }
  }

  return (
    <Flex align="center" justify="center" style={{ minHeight: '100vh' }}>
      <Card size="3" style={{ width: 360 }}>
        <form onSubmit={submit}>
          <Flex direction="column" gap="3">
            <Heading size="5">F1PG Admin</Heading>
            <Box>
              <Text as="label" htmlFor="admin-token" size="2">Admin token</Text>
              <TextField.Root
                id="admin-token"
                type="password"
                value={value}
                onChange={(e) => setValue(e.target.value)}
                placeholder="X-Admin-Token"
                mt="1"
              />
            </Box>
            {error && <Text size="2" color="red">{error}</Text>}
            <Button type="submit" disabled={busy || value.length === 0}>
              {busy ? 'Checking…' : 'Unlock'}
            </Button>
          </Flex>
        </form>
      </Card>
    </Flex>
  )
}
