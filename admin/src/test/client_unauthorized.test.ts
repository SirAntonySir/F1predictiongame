import { afterEach, describe, it, expect, vi } from 'vitest'
import { apiFetch, setUnauthorizedHandler, setToken } from '../api/client'

afterEach(() => { localStorage.clear(); setUnauthorizedHandler(null); vi.restoreAllMocks() })

describe('apiFetch 401 handling', () => {
  it('invokes the unauthorized handler on a 401 with a stored token', async () => {
    setToken('stale')
    const handler = vi.fn()
    setUnauthorizedHandler(handler)
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(
      new Response(JSON.stringify({ error: { code: 'UNAUTHORIZED', message: 'x' } }), { status: 401 })
    ))
    await expect(apiFetch('/admin/crawl/status')).rejects.toThrow()
    expect(handler).toHaveBeenCalledOnce()
  })

  it('does NOT invoke the handler when a candidate token was supplied (gate validation)', async () => {
    const handler = vi.fn()
    setUnauthorizedHandler(handler)
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(
      new Response(JSON.stringify({ error: { code: 'UNAUTHORIZED', message: 'x' } }), { status: 401 })
    ))
    await expect(apiFetch('/admin/crawl/status', { token: 'candidate' })).rejects.toThrow()
    expect(handler).not.toHaveBeenCalled()
  })
})
