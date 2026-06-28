import { describe, it, expect, afterEach, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { Predictions } from '../pages/Predictions'
import { setToken } from '../api/client'

afterEach(() => { localStorage.clear(); vi.restoreAllMocks() })

function wrap(ui: React.ReactNode) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return <QueryClientProvider client={qc}>{ui}</QueryClientProvider>
}

describe('Predictions', () => {
  it('shows predictions for an entered session id', async () => {
    setToken('tok')
    vi.stubGlobal('fetch', vi.fn((url: string) => {
      if (String(url).includes('/admin/predictions?sessionId=5')) {
        return Promise.resolve(new Response(JSON.stringify({
          predictions: [
            { predictionId: 'p1', userId: 'u1', displayName: 'Alice', sessionId: 5, source: 'app', updatedAt: '2026-01-01T00:00:00Z', picks: [{ position: 1, driverCode: 'VER' }, { position: 2, driverCode: 'LEC' }] }
          ]
        }), { status: 200 }))
      }
      return Promise.resolve(new Response('{}', { status: 200 }))
    }))

    render(wrap(<Predictions />))
    await userEvent.type(screen.getByLabelText(/session id/i), '5')
    expect(await screen.findByText('Alice')).toBeInTheDocument()
    expect(screen.getByText(/P1 VER · P2 LEC/)).toBeInTheDocument()
  })
})
