import { describe, it, expect, afterEach, vi } from 'vitest'
import { render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter, Routes, Route } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { Theme } from '@radix-ui/themes'
import { ToastProvider } from '../ui/toast'
import { LeagueDetail } from '../pages/LeagueDetail'
import { setToken } from '../api/client'

afterEach(() => { localStorage.clear(); vi.restoreAllMocks() })

function mockFetch() {
  return vi.fn((url: string, _init?: RequestInit) => {
    if (String(url).endsWith('/admin/leagues/lg1')) {
      return Promise.resolve(new Response(JSON.stringify({
        league: { id: 'lg1', name: 'My League', ownerUserId: 'u1', ownerDisplayName: 'Owner', memberCount: 2, joinCode: 'ABC123', hasPassword: false, createdAt: '2026-01-01T00:00:00Z' },
        members: [
          { userId: 'u1', displayName: 'Owner', email: 'o@x.com', role: 'owner', joinedAt: '2026-01-01T00:00:00Z' },
          { userId: 'u2', displayName: 'Bob', email: 'b@x.com', role: 'member', joinedAt: '2026-01-02T00:00:00Z' }
        ]
      }), { status: 200 }))
    }
    return Promise.resolve(new Response('{"ok":true}', { status: 200 }))
  })
}

function wrap() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } })
  return (
    <QueryClientProvider client={qc}>
      <ToastProvider>
        <Theme>
          <MemoryRouter initialEntries={['/leagues/lg1']}>
            <Routes><Route path="/leagues/:id" element={<LeagueDetail />} /></Routes>
          </MemoryRouter>
        </Theme>
      </ToastProvider>
    </QueryClientProvider>
  )
}

describe('LeagueDetail', () => {
  it('renders members and kicks a member (owner has no kick)', async () => {
    setToken('tok')
    const fetchMock = mockFetch()
    vi.stubGlobal('fetch', fetchMock)
    render(wrap())

    expect(await screen.findByText('Bob')).toBeInTheDocument()
    // Only the non-owner member has a Kick trigger.
    const kicks = screen.getAllByRole('button', { name: 'Kick' })
    expect(kicks).toHaveLength(1)

    await userEvent.click(kicks[0])
    const dialog = await screen.findByRole('alertdialog')
    await userEvent.click(within(dialog).getByRole('button', { name: 'Kick' }))

    const del = fetchMock.mock.calls.find((c) => (c[1]?.method ?? 'GET') === 'DELETE')
    expect(del).toBeTruthy()
    expect(String(del![0])).toMatch(/\/admin\/leagues\/lg1\/members\/u2$/)
  })
})
