import { describe, it, expect, afterEach, vi } from 'vitest'
import { render, screen, within, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { Theme } from '@radix-ui/themes'
import { ToastProvider } from '../ui/toast'
import { Users } from '../pages/Users'
import { setToken } from '../api/client'

afterEach(() => { localStorage.clear(); vi.restoreAllMocks() })

function wrap(ui: React.ReactNode) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } })
  return <QueryClientProvider client={qc}><ToastProvider><Theme>{ui}</Theme></ToastProvider></QueryClientProvider>
}

// Fresh Response per call (bodies are single-read) + route by method.
function mockFetch() {
  return vi.fn((url: string, init?: RequestInit) => {
    const method = init?.method ?? 'GET'
    if (String(url).includes('/admin/users') && method === 'GET') {
      return Promise.resolve(new Response(JSON.stringify({
        users: [{ id: 'u1', email: 'a@x.com', displayName: 'Alice', createdAt: '2026-01-01T00:00:00Z', leagueCount: 2 }],
        total: 1
      }), { status: 200 }))
    }
    return Promise.resolve(new Response('{"ok":true}', { status: 200 }))
  })
}

describe('Users', () => {
  it('lists users and re-queries on search input', async () => {
    setToken('tok')
    const fetchMock = mockFetch()
    vi.stubGlobal('fetch', fetchMock)
    render(wrap(<Users />))
    expect(await screen.findByText('Alice')).toBeInTheDocument()

    await userEvent.type(screen.getByLabelText(/search users/i), 'bob')
    await waitFor(() => {
      expect(fetchMock.mock.calls.some((c) => String(c[0]).includes('/admin/users?query=bob'))).toBe(true)
    })
  })

  it('edits a user via the dialog (PATCH)', async () => {
    setToken('tok')
    const fetchMock = mockFetch()
    vi.stubGlobal('fetch', fetchMock)
    render(wrap(<Users />))
    await screen.findByText('Alice')

    await userEvent.click(screen.getByRole('button', { name: 'Edit' }))
    const nameField = await screen.findByLabelText('Display name')
    await userEvent.clear(nameField)
    await userEvent.type(nameField, 'Anton')
    await userEvent.click(screen.getByRole('button', { name: 'Save' }))

    await waitFor(() => {
      const patch = fetchMock.mock.calls.find((c) => (c[1]?.method ?? 'GET') === 'PATCH')
      expect(patch).toBeTruthy()
      expect(String(patch![0])).toMatch(/\/admin\/users\/u1$/)
      expect(JSON.parse(patch![1]!.body as string).displayName).toBe('Anton')
    })
  })

  it('deletes a user after confirm (DELETE)', async () => {
    setToken('tok')
    const fetchMock = mockFetch()
    vi.stubGlobal('fetch', fetchMock)
    render(wrap(<Users />))
    await screen.findByText('Alice')

    await userEvent.click(screen.getByRole('button', { name: 'Delete' }))
    const dialog = await screen.findByRole('alertdialog')
    await userEvent.click(within(dialog).getByRole('button', { name: 'Delete' }))

    await waitFor(() => {
      const del = fetchMock.mock.calls.find((c) => (c[1]?.method ?? 'GET') === 'DELETE')
      expect(del).toBeTruthy()
      expect(String(del![0])).toMatch(/\/admin\/users\/u1$/)
    })
  })
})
