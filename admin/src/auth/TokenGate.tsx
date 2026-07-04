import { useState } from 'react'
import { Box, Button, Card, Flex, Heading, IconButton, Text, TextField } from '@radix-ui/themes'
import { apiFetch, ApiError } from '../api/client'
import { useAuth } from './AuthContext'
import { EyeIcon, EyeOffIcon } from '../ui/icons'

export function TokenGate({ children }: { children: React.ReactNode }) {
  const { token, signIn } = useAuth()
  const [value, setValue] = useState('')
  const [reveal, setReveal] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  if (token !== null) return <>{children}</>

  async function submit(e: React.FormEvent) {
    e.preventDefault()
    setBusy(true)
    setError(null)
    try {
      // Validate by hitting a token-gated endpoint with the candidate token.
      await apiFetch('/admin/crawl/status', { token: value })
      signIn(value)
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
            <Heading size="5" className="display">Undercut Admin</Heading>
            <Box>
              <Text as="label" htmlFor="admin-token" size="2" className="label">Admin token</Text>
              <TextField.Root
                id="admin-token"
                type={reveal ? 'text' : 'password'}
                value={value}
                onChange={(e) => setValue(e.target.value)}
                placeholder="X-Admin-Token"
                mt="1"
              >
                <TextField.Slot side="right">
                  <IconButton
                    type="button"
                    variant="ghost"
                    color="gray"
                    size="1"
                    aria-label={reveal ? 'Hide token' : 'Show token'}
                    onClick={() => setReveal((r) => !r)}
                  >
                    {reveal ? <EyeOffIcon /> : <EyeIcon />}
                  </IconButton>
                </TextField.Slot>
              </TextField.Root>
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
