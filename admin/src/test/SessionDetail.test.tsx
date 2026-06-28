import { describe, it, expect, afterEach, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import { MemoryRouter, Routes, Route } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { ToastProvider } from '../ui/toast'
import { SessionDetail } from '../pages/SessionDetail'
import { setToken } from '../api/client'

afterEach(() => { localStorage.clear(); vi.restoreAllMocks() })

function mockFetch() {
  return vi.fn((url: string) => {
    if (String(url).endsWith('/api/sessions/5')) {
      return Promise.resolve(new Response(JSON.stringify({ id: 5, eventId: 1, type: 'race', scheduledStart: '2026-03-01T14:00:00Z', scheduledEnd: '2026-03-01T16:00:00Z', status: 'finished' }), { status: 200 }))
    }
    if (String(url).endsWith('/api/sessions/5/results')) {
      return Promise.resolve(new Response(JSON.stringify([
        { position: 1, driverCode: 'VER', driverName: 'Max Verstappen', constructorId: 'red_bull', constructorName: 'Red Bull', points: 25, status: 'Finished', raceTime: null, q1: null, q2: null, q3: null }
      ]), { status: 200 }))
    }
    return Promise.resolve(new Response('{}', { status: 200 }))
  })
}

function wrap() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return (
    <QueryClientProvider client={qc}>
      <ToastProvider>
        <MemoryRouter initialEntries={['/sessions/5']}>
          <Routes><Route path="/sessions/:id" element={<SessionDetail />} /></Routes>
        </MemoryRouter>
      </ToastProvider>
    </QueryClientProvider>
  )
}

describe('SessionDetail', () => {
  it('shows the results grid and refetch/rescore buttons', async () => {
    setToken('tok')
    vi.stubGlobal('fetch', mockFetch())
    render(wrap())
    expect(await screen.findByText('Max Verstappen')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /re-fetch/i })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /re-score/i })).toBeInTheDocument()
  })
})
