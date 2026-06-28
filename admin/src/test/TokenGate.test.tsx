import { afterEach, describe, it, expect, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { TokenGate } from '../auth/TokenGate'

afterEach(() => { localStorage.clear(); vi.restoreAllMocks() })

describe('TokenGate', () => {
  it('shows the token form when no token is stored', () => {
    render(<TokenGate><div>secret</div></TokenGate>)
    expect(screen.getByLabelText(/admin token/i)).toBeInTheDocument()
    expect(screen.queryByText('secret')).not.toBeInTheDocument()
  })

  it('stores the token and reveals children on a valid token', async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      new Response(JSON.stringify({ lastTickAt: null, lastTickStatus: null, pendingCandidates: [], provisionalSessions: [] }),
        { status: 200, headers: { 'content-type': 'application/json' } })
    )
    vi.stubGlobal('fetch', fetchMock)
    render(<TokenGate><div>secret</div></TokenGate>)
    await userEvent.type(screen.getByLabelText(/admin token/i), 'local-dev-token')
    await userEvent.click(screen.getByRole('button', { name: /unlock|sign in|enter/i }))
    expect(await screen.findByText('secret')).toBeInTheDocument()
    expect(localStorage.getItem('f1pg_admin_token')).toBe('local-dev-token')
  })

  it('shows an error and keeps the form on an invalid token', async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      new Response(JSON.stringify({ error: { code: 'UNAUTHORIZED', message: 'Invalid admin token' } }),
        { status: 401, headers: { 'content-type': 'application/json' } })
    )
    vi.stubGlobal('fetch', fetchMock)
    render(<TokenGate><div>secret</div></TokenGate>)
    await userEvent.type(screen.getByLabelText(/admin token/i), 'wrong')
    await userEvent.click(screen.getByRole('button', { name: /unlock|sign in|enter/i }))
    expect(await screen.findByText(/invalid admin token/i)).toBeInTheDocument()
    expect(screen.queryByText('secret')).not.toBeInTheDocument()
    expect(localStorage.getItem('f1pg_admin_token')).toBeNull()
  })
})
