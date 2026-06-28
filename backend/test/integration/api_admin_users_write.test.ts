import { describe, it, expect } from 'vitest'
import { buildApp } from '../../src/index.js'
import * as users from '../../src/repo/users.js'

const TOKEN = { 'x-admin-token': 'local-dev-token' }

describe('admin user writes', () => {
  it('requires the admin token', async () => {
    const u = await users.insertUser({ email: 'a@x.com', passwordHash: 'h', displayName: 'A' })
    const app = await buildApp({ scheduler: null })
    const r = await app.inject({ method: 'PATCH', url: `/admin/users/${u.id}`, payload: { displayName: 'B' } })
    expect(r.statusCode).toBe(401)
    await app.close()
  })

  it('edits name + email, rejects email conflict, sets password, deletes', async () => {
    const u = await users.insertUser({ email: 'a@x.com', passwordHash: 'h', displayName: 'A' })
    await users.insertUser({ email: 'taken@x.com', passwordHash: 'h', displayName: 'O' })
    const app = await buildApp({ scheduler: null })

    let r = await app.inject({ method: 'PATCH', url: `/admin/users/${u.id}`, headers: TOKEN, payload: { displayName: 'Anton', email: 'anton@x.com' } })
    expect(r.statusCode).toBe(200)
    expect(r.json().user.displayName).toBe('Anton')
    expect(r.json().user.email).toBe('anton@x.com')

    r = await app.inject({ method: 'PATCH', url: `/admin/users/${u.id}`, headers: TOKEN, payload: { email: 'taken@x.com' } })
    expect(r.statusCode).toBe(409)

    r = await app.inject({ method: 'POST', url: `/admin/users/${u.id}/set-password`, headers: TOKEN, payload: { password: 'newsecret8' } })
    expect(r.statusCode).toBe(200)

    r = await app.inject({ method: 'DELETE', url: `/admin/users/${u.id}`, headers: TOKEN })
    expect(r.statusCode).toBe(200)
    expect(await users.findById(u.id)).toBeNull()
    await app.close()
  })

  it('404s an unknown user', async () => {
    const app = await buildApp({ scheduler: null })
    const r = await app.inject({ method: 'PATCH', url: '/admin/users/00000000-0000-0000-0000-000000000000', headers: TOKEN, payload: { displayName: 'X' } })
    expect(r.statusCode).toBe(404)
    await app.close()
  })
})
