import { describe, it, expect, afterEach, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { Theme } from '@radix-ui/themes'
import { Sessions } from '../pages/Sessions'
import { setToken } from '../api/client'

afterEach(() => { localStorage.clear(); vi.restoreAllMocks() })

function wrap(ui: React.ReactNode) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  // Radix Select.Content reads the Theme context, so mirror the app's <Theme> root.
  return (
    <QueryClientProvider client={qc}>
      <Theme><MemoryRouter>{ui}</MemoryRouter></Theme>
    </QueryClientProvider>
  )
}

function mockFetch() {
  return vi.fn((url: string, _init?: RequestInit) => {
    if (String(url).endsWith('/api/seasons')) {
      return Promise.resolve(new Response(JSON.stringify([
        { year: 2026, isCurrent: true },
        { year: 2025, isCurrent: false }
      ]), { status: 200 }))
    }
    if (String(url).includes('/admin/sessions?season=2026')) {
      return Promise.resolve(new Response(JSON.stringify({
        sessions: [
          { id: 5, seasonYear: 2026, round: 1, eventName: 'Bahrain GP', type: 'qualifying', status: 'finished', scheduledStart: '2026-03-01T14:00:00Z', lastReconciledAt: null, resultCount: 20, provisional: false },
          { id: 6, seasonYear: 2026, round: 1, eventName: 'Bahrain GP', type: 'race', status: 'scheduled', scheduledStart: '2026-03-01T15:00:00Z', lastReconciledAt: null, resultCount: 0, provisional: false }
        ]
      }), { status: 200 }))
    }
    return Promise.resolve(new Response('{}', { status: 200 }))
  })
}

describe('Sessions', () => {
  it('defaults to the current season and groups sessions under their event', async () => {
    setToken('tok')
    vi.stubGlobal('fetch', mockFetch())
    render(wrap(<Sessions />))

    // The event groups both sessions under one "Bahrain GP" header.
    expect(await screen.findByText(/Bahrain GP/)).toBeInTheDocument()

    // Each session links to its detail page; the race session is scheduled.
    const raceLink = screen.getByRole('link', { name: 'race' })
    expect(raceLink).toHaveAttribute('href', '/sessions/6')
    expect(screen.getByRole('link', { name: 'qualifying' })).toHaveAttribute('href', '/sessions/5')
  })

  it('requests the current season explicitly (no unfiltered all-seasons fetch)', async () => {
    setToken('tok')
    const fetchMock = mockFetch()
    vi.stubGlobal('fetch', fetchMock)
    render(wrap(<Sessions />))
    await screen.findByText(/Bahrain GP/)

    const sessionCalls = fetchMock.mock.calls
      .map((c) => String(c[0]))
      .filter((u) => u.includes('/admin/sessions'))
    expect(sessionCalls.length).toBeGreaterThan(0)
    // Every /admin/sessions call carries the season filter.
    expect(sessionCalls.every((u) => u.includes('?season=2026'))).toBe(true)
  })
})
