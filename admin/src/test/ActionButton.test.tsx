import { afterEach, describe, it, expect, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { ToastProvider } from '../ui/toast'
import { ActionButton } from '../components/ActionButton'
import { setToken } from '../api/client'

afterEach(() => { localStorage.clear(); vi.restoreAllMocks() })

function wrap(ui: React.ReactNode) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return <QueryClientProvider client={qc}><ToastProvider>{ui}</ToastProvider></QueryClientProvider>
}

describe('ActionButton', () => {
  it('POSTs the path and toasts the success message', async () => {
    setToken('tok')
    const fetchMock = vi.fn().mockResolvedValue(new Response(JSON.stringify({ ok: true }), { status: 200 }))
    vi.stubGlobal('fetch', fetchMock)

    render(wrap(<ActionButton label="Crawl" path="/admin/crawl" successMessage="Crawl triggered" />))
    await userEvent.click(screen.getByRole('button', { name: 'Crawl' }))

    expect(await screen.findByText('Crawl triggered')).toBeInTheDocument()
    const [url, init] = fetchMock.mock.calls[0]
    expect(String(url)).toMatch(/\/admin\/crawl$/)
    expect(init.method).toBe('POST')
  })

  it('toasts the error message on failure', async () => {
    setToken('tok')
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(
      new Response(JSON.stringify({ error: { code: 'INTERNAL', message: 'boom' } }), { status: 500 })
    ))
    render(wrap(<ActionButton label="Crawl" path="/admin/crawl" successMessage="ok" />))
    await userEvent.click(screen.getByRole('button', { name: 'Crawl' }))
    expect(await screen.findByText('boom')).toBeInTheDocument()
  })
})
