import { describe, it, expect, afterEach, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { ToastProvider } from '../ui/toast'
import { ResultEditDialog } from '../components/ResultEditDialog'
import { setToken } from '../api/client'

afterEach(() => { localStorage.clear(); vi.restoreAllMocks() })

function wrap(ui: React.ReactNode) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } })
  return <QueryClientProvider client={qc}><ToastProvider>{ui}</ToastProvider></QueryClientProvider>
}

describe('ResultEditDialog', () => {
  it('PATCHes the edited fields for an existing row', async () => {
    setToken('tok')
    const fetchMock = vi.fn().mockResolvedValue(new Response(JSON.stringify({ ok: true, result: {}, rescored: { users: 0, totalPoints: 0 } }), { status: 200 }))
    vi.stubGlobal('fetch', fetchMock)

    render(wrap(
      <ResultEditDialog
        sessionId={5}
        mode="edit"
        initial={{ position: 1, driverCode: 'VER', driverName: 'Max Verstappen', constructorId: 'red_bull', constructorName: 'Red Bull', points: 25, status: 'Finished', raceTime: null, q1: null, q2: null, q3: null }}
        onClose={() => {}}
      />
    ))

    const points = screen.getByLabelText(/points/i)
    await userEvent.clear(points)
    await userEvent.type(points, '18')
    await userEvent.click(screen.getByRole('button', { name: /save/i }))

    expect(await screen.findByText(/saved/i)).toBeInTheDocument()
    const patchCall = fetchMock.mock.calls.find((c) => (c[1]?.method ?? 'GET') === 'PATCH')
    expect(patchCall).toBeTruthy()
    expect(String(patchCall![0])).toMatch(/\/admin\/sessions\/5\/results\/1$/)
    expect(JSON.parse(patchCall![1].body).points).toBe(18)
  })
})
