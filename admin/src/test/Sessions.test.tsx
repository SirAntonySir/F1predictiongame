import { describe, it, expect, afterEach, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { Sessions } from '../pages/Sessions'
import { setToken } from '../api/client'

afterEach(() => { localStorage.clear(); vi.restoreAllMocks() })

function wrap(ui: React.ReactNode) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return <QueryClientProvider client={qc}><MemoryRouter>{ui}</MemoryRouter></QueryClientProvider>
}

describe('Sessions', () => {
  it('lists sessions from /admin/sessions', async () => {
    setToken('tok')
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(new Response(JSON.stringify({
      sessions: [{ id: 5, seasonYear: 2026, round: 1, eventName: 'Bahrain GP', type: 'race', status: 'finished', scheduledStart: '2026-03-01T14:00:00Z', lastReconciledAt: null, resultCount: 20, provisional: true }]
    }), { status: 200 })))

    render(wrap(<Sessions />))
    expect(await screen.findByText('Bahrain GP')).toBeInTheDocument()
    const link = screen.getByRole('link', { name: /bahrain gp/i })
    expect(link).toHaveAttribute('href', '/sessions/5')
  })
})
