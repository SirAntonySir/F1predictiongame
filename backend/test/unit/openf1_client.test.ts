import { describe, it, expect } from 'vitest'
import { OpenF1Client } from '../../src/openf1/client.js'

function fakeFetch(handlers: Record<string, { status: number; body: unknown }>) {
  const calls: string[] = []
  const fetchFn = async (url: string | URL): Promise<Response> => {
    const u = url.toString()
    calls.push(u)
    const h = handlers[u]
    if (!h) throw new Error(`Unexpected fetch: ${u}`)
    return new Response(JSON.stringify(h.body), { status: h.status })
  }
  return { fetchFn: fetchFn as unknown as typeof fetch, calls }
}

describe('OpenF1Client', () => {
  it('GET /sessions?year=Y', async () => {
    const { fetchFn, calls } = fakeFetch({
      'https://api.openf1.org/v1/sessions?year=2026': { status: 200, body: [{ session_key: 1 }] }
    })
    const c = new OpenF1Client('https://api.openf1.org/v1', fetchFn)
    const out = await c.getSessions(2026)
    expect(out).toEqual([{ session_key: 1 }])
    expect(calls).toEqual(['https://api.openf1.org/v1/sessions?year=2026'])
  })

  it('GET /drivers?session_key=K', async () => {
    const { fetchFn } = fakeFetch({
      'https://api.openf1.org/v1/drivers?session_key=11282': { status: 200, body: [{ driver_number: 63 }] }
    })
    const c = new OpenF1Client('https://api.openf1.org/v1', fetchFn)
    const out = await c.getDrivers(11282)
    expect(out).toEqual([{ driver_number: 63 }])
  })

  it('GET /session_result?session_key=K', async () => {
    const { fetchFn } = fakeFetch({
      'https://api.openf1.org/v1/session_result?session_key=11282': { status: 200, body: [{ position: 1 }] }
    })
    const c = new OpenF1Client('https://api.openf1.org/v1', fetchFn)
    const out = await c.getSessionResult(11282)
    expect(out).toEqual([{ position: 1 }])
  })

  it('returns null on 4xx (treats as "no data", matching JolpicaClient convention)', async () => {
    const { fetchFn } = fakeFetch({
      'https://api.openf1.org/v1/session_result?session_key=99999': { status: 404, body: { error: 'not found' } }
    })
    const c = new OpenF1Client('https://api.openf1.org/v1', fetchFn)
    expect(await c.getSessionResult(99999)).toBeNull()
  })

  it('throws on 5xx', async () => {
    const { fetchFn } = fakeFetch({
      'https://api.openf1.org/v1/sessions?year=2026': { status: 502, body: '' }
    })
    const c = new OpenF1Client('https://api.openf1.org/v1', fetchFn)
    await expect(c.getSessions(2026)).rejects.toThrow(/OpenF1 502/)
  })

  it('GET /position?session_key=K', async () => {
    const { fetchFn, calls } = fakeFetch({
      'https://api.openf1.org/v1/position?session_key=9876': {
        status: 200,
        body: [{ driver_number: 1, position: 1, date: '2026-06-07T13:00:00Z' }]
      }
    })
    const c = new OpenF1Client('https://api.openf1.org/v1', fetchFn)
    const out = await c.getPosition(9876)
    expect(out).toEqual([{ driver_number: 1, position: 1, date: '2026-06-07T13:00:00Z' }])
    expect(calls).toEqual(['https://api.openf1.org/v1/position?session_key=9876'])
  })
})
