import { describe, it, expect } from 'vitest'
import { buildApp } from '../../src/index.js'

async function app() {
  return buildApp({ scheduler: null })
}

async function signup(a: Awaited<ReturnType<typeof app>>, email: string, password = 'hunter22', displayName = 'U') {
  return a.inject({ method: 'POST', url: '/api/auth/signup', payload: { email, password, displayName } })
}

describe('POST /api/auth/signup', () => {
  it('creates a user and returns a token', async () => {
    const a = await app()
    const res = await signup(a, 'a@x.com')
    expect(res.statusCode).toBe(200)
    const body = res.json()
    expect(body.user.email).toBe('a@x.com')
    expect(body.user.id).toMatch(/^[0-9a-f-]{36}$/)
    expect(body.user.passwordHash).toBeUndefined()
    expect(typeof body.token).toBe('string')
    expect(body.token.length).toBeGreaterThan(20)
  })

  it('normalizes email to lowercase', async () => {
    const a = await app()
    const res = await signup(a, 'Mixed@X.COM')
    expect(res.json().user.email).toBe('mixed@x.com')
  })

  it('rejects duplicate email with 409 CONFLICT', async () => {
    const a = await app()
    await signup(a, 'dup@x.com')
    const res = await signup(a, 'DUP@x.com')
    expect(res.statusCode).toBe(409)
    expect(res.json().error.code).toBe('CONFLICT')
  })

  it('rejects short password with 422 VALIDATION', async () => {
    const a = await app()
    const res = await signup(a, 'short@x.com', '1234')
    expect(res.statusCode).toBe(422)
    expect(res.json().error.code).toBe('VALIDATION')
  })

  it('rejects bad email with 422 VALIDATION', async () => {
    const a = await app()
    const res = await signup(a, 'not-an-email')
    expect(res.statusCode).toBe(422)
  })
})

describe('POST /api/auth/login', () => {
  it('logs in with correct password', async () => {
    const a = await app()
    await signup(a, 'log@x.com', 'rightpass')
    const res = await a.inject({ method: 'POST', url: '/api/auth/login', payload: { email: 'log@x.com', password: 'rightpass' } })
    expect(res.statusCode).toBe(200)
    expect(typeof res.json().token).toBe('string')
  })

  it('returns the same UNAUTHORIZED for wrong password or unknown user', async () => {
    const a = await app()
    await signup(a, 'log2@x.com', 'rightpass')
    const wrong = await a.inject({ method: 'POST', url: '/api/auth/login', payload: { email: 'log2@x.com', password: 'wrong' } })
    const unknown = await a.inject({ method: 'POST', url: '/api/auth/login', payload: { email: 'nope@x.com', password: 'rightpass' } })
    expect(wrong.statusCode).toBe(401)
    expect(unknown.statusCode).toBe(401)
    expect(wrong.json().error.message).toBe(unknown.json().error.message)
  })

  it('login is case-insensitive on email', async () => {
    const a = await app()
    await signup(a, 'caseme@x.com', 'rightpass')
    const res = await a.inject({ method: 'POST', url: '/api/auth/login', payload: { email: 'CASEME@x.com', password: 'rightpass' } })
    expect(res.statusCode).toBe(200)
  })
})

describe('GET /api/auth/me', () => {
  it('returns the current user when token is valid', async () => {
    const a = await app()
    const s = await signup(a, 'me@x.com')
    const token = s.json().token
    const res = await a.inject({ method: 'GET', url: '/api/auth/me', headers: { authorization: `Bearer ${token}` } })
    expect(res.statusCode).toBe(200)
    expect(res.json().user.email).toBe('me@x.com')
    // New users have no avatar until they save one.
    expect(res.json().user.avatar).toBeNull()
    expect(Array.isArray(res.json().leagues)).toBe(true)
  })

  it('401s without a token', async () => {
    const a = await app()
    const res = await a.inject({ method: 'GET', url: '/api/auth/me' })
    expect(res.statusCode).toBe(401)
  })

  it('401s with a malformed token', async () => {
    const a = await app()
    const res = await a.inject({ method: 'GET', url: '/api/auth/me', headers: { authorization: 'Bearer not-real' } })
    expect(res.statusCode).toBe(401)
  })
})

describe('PATCH /api/auth/me', () => {
  it('updates display name', async () => {
    const a = await app()
    const s = await signup(a, 'p@x.com', 'hunter22', 'Old')
    const token = s.json().token
    const res = await a.inject({
      method: 'PATCH', url: '/api/auth/me',
      headers: { authorization: `Bearer ${token}` },
      payload: { displayName: 'New' }
    })
    expect(res.statusCode).toBe(200)
    expect(res.json().user.displayName).toBe('New')
  })

  it('sets the avatar config and returns it, and /me echoes it', async () => {
    const a = await app()
    const s = await signup(a, 'av@x.com')
    const token = s.json().token
    const avatar = JSON.stringify({ preset: 'bolt', pose: 'pose2' })
    const res = await a.inject({
      method: 'PATCH', url: '/api/auth/me',
      headers: { authorization: `Bearer ${token}` },
      payload: { avatar }
    })
    expect(res.statusCode).toBe(200)
    expect(res.json().user.avatar).toBe(avatar)
    const me = await a.inject({ method: 'GET', url: '/api/auth/me', headers: { authorization: `Bearer ${token}` } })
    expect(me.json().user.avatar).toBe(avatar)
  })

  it('rejects a non-JSON avatar with 422 VALIDATION', async () => {
    const a = await app()
    const s = await signup(a, 'av2@x.com')
    const token = s.json().token
    const res = await a.inject({
      method: 'PATCH', url: '/api/auth/me',
      headers: { authorization: `Bearer ${token}` },
      payload: { avatar: 'not json' }
    })
    expect(res.statusCode).toBe(422)
    expect(res.json().error.code).toBe('VALIDATION')
  })

  it('rejects an oversize avatar with 422 VALIDATION', async () => {
    const a = await app()
    const s = await signup(a, 'av3@x.com')
    const token = s.json().token
    const big = JSON.stringify({ x: 'y'.repeat(2100) })
    const res = await a.inject({
      method: 'PATCH', url: '/api/auth/me',
      headers: { authorization: `Bearer ${token}` },
      payload: { avatar: big }
    })
    expect(res.statusCode).toBe(422)
    expect(res.json().error.code).toBe('VALIDATION')
  })
})

describe('POST /api/auth/change-password', () => {
  async function change(a: Awaited<ReturnType<typeof app>>, payload: unknown) {
    return a.inject({ method: 'POST', url: '/api/auth/change-password', payload })
  }

  it('updates the password — old fails, new succeeds', async () => {
    const a = await app()
    await signup(a, 'cp@x.com', 'oldpass1')
    const res = await change(a, { email: 'cp@x.com', currentPassword: 'oldpass1', newPassword: 'newpass2' })
    expect(res.statusCode).toBe(200)
    expect(res.json().ok).toBe(true)

    const oldLogin = await a.inject({ method: 'POST', url: '/api/auth/login', payload: { email: 'cp@x.com', password: 'oldpass1' } })
    expect(oldLogin.statusCode).toBe(401)
    const newLogin = await a.inject({ method: 'POST', url: '/api/auth/login', payload: { email: 'cp@x.com', password: 'newpass2' } })
    expect(newLogin.statusCode).toBe(200)
  })

  it('rejects a wrong current password with 401', async () => {
    const a = await app()
    await signup(a, 'cp2@x.com', 'rightnow')
    const res = await change(a, { email: 'cp2@x.com', currentPassword: 'guessguess', newPassword: 'anotherone' })
    expect(res.statusCode).toBe(401)
    expect(res.json().error.code).toBe('UNAUTHORIZED')
  })

  it('rejects an unknown email with 401 (no enumeration leak)', async () => {
    const a = await app()
    const res = await change(a, { email: 'nobody@x.com', currentPassword: 'whatever', newPassword: 'anewlongone' })
    expect(res.statusCode).toBe(401)
  })

  it('rejects a too-short new password with 422', async () => {
    const a = await app()
    await signup(a, 'cp3@x.com', 'longenough')
    const res = await change(a, { email: 'cp3@x.com', currentPassword: 'longenough', newPassword: 'short' })
    expect(res.statusCode).toBe(422)
  })

  it('rejects reusing the current password with 422', async () => {
    const a = await app()
    await signup(a, 'cp4@x.com', 'samepass1')
    const res = await change(a, { email: 'cp4@x.com', currentPassword: 'samepass1', newPassword: 'samepass1' })
    expect(res.statusCode).toBe(422)
  })

  it('normalizes the email to lowercase', async () => {
    const a = await app()
    await signup(a, 'mixed@x.com', 'oldpass1')
    const res = await change(a, { email: 'Mixed@X.com', currentPassword: 'oldpass1', newPassword: 'newpass2' })
    expect(res.statusCode).toBe(200)
  })
})

describe('POST /api/auth/logout', () => {
  it('deletes the session, subsequent /me 401s', async () => {
    const a = await app()
    const s = await signup(a, 'out@x.com')
    const token = s.json().token
    const out = await a.inject({ method: 'POST', url: '/api/auth/logout', headers: { authorization: `Bearer ${token}` } })
    expect(out.statusCode).toBe(200)
    const me = await a.inject({ method: 'GET', url: '/api/auth/me', headers: { authorization: `Bearer ${token}` } })
    expect(me.statusCode).toBe(401)
  })
})
