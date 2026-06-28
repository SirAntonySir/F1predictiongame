import { describe, it, expect, afterEach, vi } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { Users } from '../pages/Users'
import { setToken } from '../api/client'

afterEach(() => { localStorage.clear(); vi.restoreAllMocks() })

function wrap(ui: React.ReactNode) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return <QueryClientProvider client={qc}>{ui}</QueryClientProvider>
}

describe('Users', () => {
  it('lists users and re-queries on search input', async () => {
    setToken('tok')
    const fetchMock = vi.fn().mockResolvedValue(new Response(JSON.stringify({
      users: [{ id: 'u1', email: 'a@x.com', displayName: 'Alice', createdAt: '2026-01-01T00:00:00Z', leagueCount: 2 }],
      total: 1
    }), { status: 200 }))
    vi.stubGlobal('fetch', fetchMock)

    render(wrap(<Users />))
    expect(await screen.findByText('Alice')).toBeInTheDocument()

    await userEvent.type(screen.getByLabelText(/search users/i), 'bob')
    await waitFor(() => {
      expect(fetchMock.mock.calls.some((c) => String(c[0]).includes('/admin/users?query=bob'))).toBe(true)
    })
  })
})
