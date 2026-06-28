import { describe, it, expect, afterEach, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { ToastProvider } from '../ui/toast'
import { Seasons } from '../pages/Seasons'
import { setToken } from '../api/client'

afterEach(() => { localStorage.clear(); vi.restoreAllMocks() })

function wrap(ui: React.ReactNode) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return <QueryClientProvider client={qc}><ToastProvider>{ui}</ToastProvider></QueryClientProvider>
}

describe('Seasons', () => {
  it('lists seasons with per-season action buttons', async () => {
    setToken('tok')
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(new Response(JSON.stringify([
      { year: 2026, isCurrent: true },
      { year: 2025, isCurrent: false }
    ]), { status: 200 })))
    render(wrap(<Seasons />))
    expect(await screen.findByText('2026')).toBeInTheDocument()
    expect(screen.getByText('2025')).toBeInTheDocument()
    // one Activate button per season
    expect(screen.getAllByRole('button', { name: 'Activate' })).toHaveLength(2)
  })
})
