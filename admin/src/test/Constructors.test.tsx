import { describe, it, expect, afterEach, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { Theme } from '@radix-ui/themes'
import { ToastProvider } from '../ui/toast'
import { Constructors } from '../pages/Constructors'
import { setToken } from '../api/client'

afterEach(() => { localStorage.clear(); vi.restoreAllMocks() })

function wrap(ui: React.ReactNode) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return <QueryClientProvider client={qc}><ToastProvider><Theme>{ui}</Theme></ToastProvider></QueryClientProvider>
}

function mockFetch() {
  return vi.fn((url: string) => {
    if (String(url).endsWith('/admin/constructors')) {
      return Promise.resolve(new Response(JSON.stringify({
        constructors: [
          { id: 'ferrari', name: 'Ferrari', nationality: 'IT', wikipediaUrl: null, imageUrl: 'fe.png', imageUrlOverride: null, teamColour: 'E80020', image: 'fe.png' },
          { id: 'red_bull', name: 'Red Bull', nationality: 'AT', wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, teamColour: null, image: null }
        ]
      }), { status: 200 }))
    }
    return Promise.resolve(new Response('{}', { status: 200 }))
  })
}

describe('Constructors', () => {
  it('lists constructors by name (never raw ids) with colour swatch', async () => {
    setToken('tok')
    vi.stubGlobal('fetch', mockFetch())
    render(wrap(<Constructors />))
    expect(await screen.findByText('Ferrari')).toBeInTheDocument()
    expect(screen.getByText('Red Bull')).toBeInTheDocument()
    // raw id must not be shown
    expect(screen.queryByText('red_bull')).not.toBeInTheDocument()
    expect(screen.getByText('#E80020')).toBeInTheDocument()
    expect(screen.getByText('2 constructors')).toBeInTheDocument()
  })
})
