import { describe, it, expect, afterEach, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { Theme } from '@radix-ui/themes'
import { Predictions } from '../pages/Predictions'
import { setToken } from '../api/client'

afterEach(() => { localStorage.clear(); vi.restoreAllMocks() })

function wrap(ui: React.ReactNode) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  // Radix Select reads the Theme context.
  return <QueryClientProvider client={qc}><Theme>{ui}</Theme></QueryClientProvider>
}

function mockFetch() {
  return vi.fn((url: string, _init?: RequestInit) => {
    if (String(url).endsWith('/api/seasons')) {
      return Promise.resolve(new Response(JSON.stringify([{ year: 2026, isCurrent: true }]), { status: 200 }))
    }
    if (String(url).includes('/admin/sessions?season=2026')) {
      return Promise.resolve(new Response(JSON.stringify({
        sessions: [
          { id: 6, seasonYear: 2026, round: 1, eventName: 'Bahrain GP', type: 'race', status: 'finished', scheduledStart: '2026-03-01T15:00:00Z', lastReconciledAt: null, resultCount: 20, provisional: false }
        ]
      }), { status: 200 }))
    }
    if (String(url).includes('/admin/predictions?sessionId=6')) {
      return Promise.resolve(new Response(JSON.stringify({
        predictions: [
          { predictionId: 'p1', userId: 'u1', displayName: 'Alice', sessionId: 6, source: 'app', updatedAt: '2026-01-01T00:00:00Z', picks: [{ position: 1, driverCode: 'VER' }, { position: 2, driverCode: 'LEC' }] }
        ]
      }), { status: 200 }))
    }
    return Promise.resolve(new Response('{}', { status: 200 }))
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
})
