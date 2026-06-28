import { describe, it, expect, afterEach, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { Leagues } from '../pages/Leagues'
import { setToken } from '../api/client'

afterEach(() => { localStorage.clear(); vi.restoreAllMocks() })

function wrap(ui: React.ReactNode) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return <QueryClientProvider client={qc}><MemoryRouter>{ui}</MemoryRouter></QueryClientProvider>
}

describe('Leagues', () => {
  it('lists leagues with owner + member count and links to detail', async () => {
    setToken('tok')
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(new Response(JSON.stringify({
      leagues: [{ id: 'lg1', name: 'My League', ownerUserId: 'u1', ownerDisplayName: 'Alice', memberCount: 4, joinCode: 'ABC123', hasPassword: true, createdAt: '2026-01-01T00:00:00Z' }]
    }), { status: 200 })))

    render(wrap(<Leagues />))
    expect(await screen.findByText('My League')).toBeInTheDocument()
    expect(screen.getByText('Alice')).toBeInTheDocument()
    expect(screen.getByRole('link', { name: /my league/i })).toHaveAttribute('href', '/leagues/lg1')
  })
})
