import { describe, it, expect, afterEach, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { Theme } from '@radix-ui/themes'
import { ToastProvider } from '../ui/toast'
import { Drivers } from '../pages/Drivers'
import { setToken } from '../api/client'

afterEach(() => { localStorage.clear(); vi.restoreAllMocks() })

function wrap(ui: React.ReactNode) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return <QueryClientProvider client={qc}><ToastProvider><Theme>{ui}</Theme></ToastProvider></QueryClientProvider>
}

function mockFetch() {
  return vi.fn((url: string) => {
    if (String(url).endsWith('/admin/drivers')) {
      return Promise.resolve(new Response(JSON.stringify({
        drivers: [
          { code: 'HAM', givenName: 'Lewis', familyName: 'Hamilton', nationality: 'GB', permanentNumber: 44, wikipediaUrl: null, imageUrl: 'w.png', imageUrlOverride: 'o.png', headshotUrl: null, image: 'o.png' },
          { code: 'VER', givenName: 'Max', familyName: 'Verstappen', nationality: 'NL', permanentNumber: 1, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, headshotUrl: null, image: null }
        ]
      }), { status: 200 }))
    }
    return Promise.resolve(new Response('{}', { status: 200 }))
  })
}

describe('Drivers', () => {
  it('lists drivers with their data', async () => {
    setToken('tok')
    vi.stubGlobal('fetch', mockFetch())
    render(wrap(<Drivers />))
    expect(await screen.findByText('Lewis Hamilton')).toBeInTheDocument()
    expect(screen.getByText('Max Verstappen')).toBeInTheDocument()
    expect(screen.getByText('2 drivers')).toBeInTheDocument()
    // override flagged distinctly from missing image
    expect(screen.getByText('override')).toBeInTheDocument()
    expect(screen.getByText('none')).toBeInTheDocument()
  })

  it('filters by the search box', async () => {
    setToken('tok')
    vi.stubGlobal('fetch', mockFetch())
    render(wrap(<Drivers />))
    await screen.findByText('Lewis Hamilton')

    await userEvent.type(screen.getByLabelText('Search drivers'), 'versta')
    expect(screen.getByText('Max Verstappen')).toBeInTheDocument()
    expect(screen.queryByText('Lewis Hamilton')).not.toBeInTheDocument()
  })
})
