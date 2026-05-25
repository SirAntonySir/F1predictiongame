import { describe, it, expect } from 'vitest'
import { buildApp } from '../../src/index.js'

describe('admin auth', () => {
  it('rejects requests without the admin token', async () => {
    const app = await buildApp({ scheduler: null })
    const res = await app.inject({ method: 'POST', url: '/admin/bootstrap' })
    expect(res.statusCode).toBe(401)
    await app.close()
  })

  it('rejects requests with a wrong token', async () => {
    const app = await buildApp({ scheduler: null })
    const res = await app.inject({
      method: 'POST',
      url: '/admin/bootstrap',
      headers: { 'x-admin-token': 'wrong' }
    })
    expect(res.statusCode).toBe(401)
    await app.close()
  })

  it('rejects refresh-images without token', async () => {
    const app = await buildApp({ scheduler: null })
    const res = await app.inject({ method: 'POST', url: '/admin/refresh-images' })
    expect(res.statusCode).toBe(401)
    await app.close()
  })

  it('rejects crawl without token', async () => {
    const app = await buildApp({ scheduler: null })
    const res = await app.inject({ method: 'POST', url: '/admin/crawl' })
    expect(res.statusCode).toBe(401)
    await app.close()
  })
})
