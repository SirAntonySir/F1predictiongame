import { beforeEach, afterEach, describe, it, expect, vi } from 'vitest'
import { apiFetch, ApiError, getToken, setToken, clearToken } from '../api/client'

describe('token storage', () => {
  beforeEach(() => localStorage.clear())
  it('round-trips the token', () => {
    expect(getToken()).toBeNull()
    setToken('abc')
    expect(getToken()).toBe('abc')
    clearToken()
    expect(getToken()).toBeNull()
  })
})

describe('apiFetch', () => {
  beforeEach(() => { localStorage.clear(); setToken('tok123') })
  afterEach(() => vi.restoreAllMocks())

  it('prefixes base URL and sends the admin token header', async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      new Response(JSON.stringify({ ok: true }), { status: 200, headers: { 'content-type': 'application/json' } })
    )
    vi.stubGlobal('fetch', fetchMock)
    const out = await apiFetch<{ ok: boolean }>('/admin/crawl/status')
    expect(out).toEqual({ ok: true })
    const [url, init] = fetchMock.mock.calls[0]
    expect(String(url)).toMatch(/\/admin\/crawl\/status$/)
    expect((init.headers as Record<string, string>)['X-Admin-Token']).toBe('tok123')
  })

  it('throws ApiError with status and code on non-2xx', async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      new Response(JSON.stringify({ error: { code: 'UNAUTHORIZED', message: 'Invalid admin token' } }),
        { status: 401, headers: { 'content-type': 'application/json' } })
    )
    vi.stubGlobal('fetch', fetchMock)
    const err = await apiFetch('/admin/crawl/status').catch(e => e)
    expect(err).toBeInstanceOf(ApiError)
    expect(err).toMatchObject({ name: 'ApiError', status: 401, code: 'UNAUTHORIZED' })
  })
})
