import { describe, it, expect, afterEach, vi } from 'vitest'
import { render, screen, within, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { Theme } from '@radix-ui/themes'
import { ToastProvider } from '../ui/toast'
import { Predictions } from '../pages/Predictions'
import { setToken } from '../api/client'

afterEach(() => { localStorage.clear(); vi.restoreAllMocks() })

function wrap(ui: React.ReactNode) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } })
  return <QueryClientProvider client={qc}><ToastProvider><Theme>{ui}</Theme></ToastProvider></QueryClientProvider>
}

function mockFetch() {
  return vi.fn((url: string, _init?: RequestInit) => {
    if (String(url).endsWith('/api/seasons')) {
      return Promise.resolve(new Response(JSON.stringify([{ year: 2026, isCurrent: true }]), { status: 200 }))
    }
    if (String(url).includes('/admin/sessions?season=2026')) {
      return Promise.resolve(new Response(JSON.stringify({
        sessions: [{ id: 6, seasonYear: 2026, round: 1, eventName: 'Bahrain GP', type: 'race', status: 'finished', scheduledStart: '2026-03-01T15:00:00Z', lastReconciledAt: null, resultCount: 20, provisional: false }]
      }), { status: 200 }))
    }
    if (String(url).includes('/admin/predictions?sessionId=6')) {
      return Promise.resolve(new Response(JSON.stringify({
        predictions: [{ predictionId: 'p1', userId: 'u1', displayName: 'Alice', sessionId: 6, source: 'app', updatedAt: '2026-01-01T00:00:00Z', picks: [{ position: 1, driverCode: 'VER' }, { position: 2, driverCode: 'LEC' }] }]
      }), { status: 200 }))
    }
    if (String(url).endsWith('/admin/leagues')) {
      return Promise.resolve(new Response(JSON.stringify({
        leagues: [{ id: 'l1', name: 'Friends', ownerUserId: 'u1', ownerDisplayName: 'Alice', memberCount: 2, joinCode: 'ABC', hasPassword: false, createdAt: '2026-01-01T00:00:00Z' }]
      }), { status: 200 }))
    }
    if (String(url).endsWith('/admin/leagues/l1')) {
      return Promise.resolve(new Response(JSON.stringify({
        league: { id: 'l1', name: 'Friends', ownerUserId: 'u1', ownerDisplayName: 'Alice', memberCount: 2, joinCode: 'ABC', hasPassword: false, createdAt: '2026-01-01T00:00:00Z' },
        members: [
          { userId: 'u1', displayName: 'Alice', email: 'a@x.io', role: 'owner', joinedAt: '2026-01-01T00:00:00Z' },
          { userId: 'u2', displayName: 'Bob', email: 'b@x.io', role: 'member', joinedAt: '2026-01-01T00:00:00Z' }
        ]
      }), { status: 200 }))
    }
    return Promise.resolve(new Response('{"ok":true}', { status: 200 }))
  })
}

describe('Predictions', () => {
  it('auto-selects the latest finished session and lists its predictions', async () => {
    setToken('tok')
    vi.stubGlobal('fetch', mockFetch())
    render(wrap(<Predictions />))
    expect(await screen.findByText('Alice')).toBeInTheDocument()
    expect(screen.getByText(/P1 VER · P2 LEC/)).toBeInTheDocument()
  })

  it('edits picks via the dialog (PUT)', async () => {
    setToken('tok')
    const fetchMock = mockFetch()
    vi.stubGlobal('fetch', fetchMock)
    render(wrap(<Predictions />))
    await screen.findByText('Alice')

    await userEvent.click(screen.getByRole('button', { name: 'Edit' }))
    const p1 = await screen.findByLabelText('P1 driver')
    await userEvent.clear(p1)
    await userEvent.type(p1, 'HAM')
    await userEvent.click(screen.getByRole('button', { name: 'Save' }))

    await waitFor(() => {
      const put = fetchMock.mock.calls.find((c) => (c[1]?.method ?? 'GET') === 'PUT')
      expect(put).toBeTruthy()
      expect(String(put![0])).toMatch(/\/admin\/predictions\/u1\/6\/picks$/)
      const body = JSON.parse(put![1]!.body as string)
      expect(body.picks[0]).toEqual({ position: 1, driverCode: 'HAM' })
    })
  })

  it('adds a prediction for a league member without one (PUT)', async () => {
    setToken('tok')
    const fetchMock = mockFetch()
    vi.stubGlobal('fetch', fetchMock)
    render(wrap(<Predictions />))
    await screen.findByText('Alice')

    await userEvent.click(screen.getByRole('button', { name: 'Add prediction' }))
    const dialog = await screen.findByRole('dialog')

    // Pick the league, then the player. Alice already has a prediction, so the
    // player list should offer Bob (u2), not Alice.
    await userEvent.click(within(dialog).getByLabelText('League'))
    await userEvent.click(await screen.findByRole('option', { name: 'Friends' }))
    await userEvent.click(within(dialog).getByLabelText('Player'))
    expect(screen.queryByRole('option', { name: 'Alice' })).not.toBeInTheDocument()
    await userEvent.click(await screen.findByRole('option', { name: 'Bob' }))

    // Race needs 5 picks; Add stays disabled until all are filled.
    const codes = ['VER', 'LEC', 'HAM', 'NOR', 'RUS']
    for (let i = 0; i < codes.length; i++) {
      await userEvent.type(within(dialog).getByLabelText(`P${i + 1} driver`), codes[i])
    }
    await userEvent.click(within(dialog).getByRole('button', { name: 'Add' }))

    await waitFor(() => {
      const put = fetchMock.mock.calls.find((c) => (c[1]?.method ?? 'GET') === 'PUT')
      expect(put).toBeTruthy()
      expect(String(put![0])).toMatch(/\/admin\/predictions\/u2\/6\/picks$/)
      const body = JSON.parse(put![1]!.body as string)
      expect(body.picks).toHaveLength(5)
      expect(body.picks[0]).toEqual({ position: 1, driverCode: 'VER' })
      expect(body.picks[4]).toEqual({ position: 5, driverCode: 'RUS' })
    })
  })

  it('deletes a prediction after confirm (DELETE)', async () => {
    setToken('tok')
    const fetchMock = mockFetch()
    vi.stubGlobal('fetch', fetchMock)
    render(wrap(<Predictions />))
    await screen.findByText('Alice')

    await userEvent.click(screen.getByRole('button', { name: 'Delete' }))
    const dialog = await screen.findByRole('alertdialog')
    await userEvent.click(within(dialog).getByRole('button', { name: 'Delete' }))

    await waitFor(() => {
      const del = fetchMock.mock.calls.find((c) => (c[1]?.method ?? 'GET') === 'DELETE')
      expect(del).toBeTruthy()
      expect(String(del![0])).toMatch(/\/admin\/predictions\/u1\/6$/)
    })
  })
})
