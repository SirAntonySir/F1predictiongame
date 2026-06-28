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
