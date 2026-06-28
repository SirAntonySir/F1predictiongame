import { describe, it, expect } from 'vitest'
import { buildApp } from '../../src/index.js'
import * as notificationsRepo from '../../src/repo/notifications.js'

async function buildAndUser() {
  const a = await buildApp({ scheduler: null })
  const r = await a.inject({
    method: 'POST',
    url: '/api/auth/signup',
    payload: { email: `dev-${Date.now()}-${Math.round(Math.random() * 1e6)}@x.com`, password: 'hunter22', displayName: 'U' }
  })
  return { app: a, token: r.json().token as string, userId: r.json().user.id as string }
}

const auth = (token: string) => ({ authorization: `Bearer ${token}` })

describe('POST /api/devices', () => {
  it('registers an FCM token for the current user', async () => {
    const { app, token, userId } = await buildAndUser()
    const res = await app.inject({
      method: 'POST',
      url: '/api/devices',
      headers: auth(token),
      payload: { token: 'fcm-abc', platform: 'ios', timezone: 'Europe/Vienna' }
    })
    expect(res.statusCode).toBe(200)
    const stored = await notificationsRepo.tokensForUser(userId)
    expect(stored.map((t) => t.token)).toEqual(['fcm-abc'])
    expect(stored[0].platform).toBe('ios')
  })

  it('syncs the reported timezone onto the user prefs', async () => {
    const { app, token, userId } = await buildAndUser()
    await app.inject({
      method: 'POST', url: '/api/devices', headers: auth(token),
      payload: { token: 'fcm-tz', platform: 'android', timezone: 'America/New_York' }
    })
    const pref = await notificationsRepo.getPrefOrDefault(userId)
    expect(pref.timezone).toBe('America/New_York')
  })

  it('re-registering the same token does not duplicate it', async () => {
    const { app, token, userId } = await buildAndUser()
    const body = { token: 'fcm-dup', platform: 'ios' as const }
    await app.inject({ method: 'POST', url: '/api/devices', headers: auth(token), payload: body })
    await app.inject({ method: 'POST', url: '/api/devices', headers: auth(token), payload: body })
    const stored = await notificationsRepo.tokensForUser(userId)
    expect(stored).toHaveLength(1)
  })

  it('requires authentication', async () => {
    const a = await buildApp({ scheduler: null })
    const res = await a.inject({
      method: 'POST', url: '/api/devices',
      payload: { token: 'x', platform: 'ios' }
    })
    expect(res.statusCode).toBe(401)
  })

  it('rejects an invalid platform with 422 VALIDATION', async () => {
    const { app, token } = await buildAndUser()
    const res = await app.inject({
      method: 'POST', url: '/api/devices', headers: auth(token),
      payload: { token: 'x', platform: 'windows' }
    })
    expect(res.statusCode).toBe(422)
    expect(res.json().error.code).toBe('VALIDATION')
  })
})

describe('DELETE /api/devices', () => {
  it('removes the token for the user', async () => {
    const { app, token, userId } = await buildAndUser()
    await app.inject({ method: 'POST', url: '/api/devices', headers: auth(token), payload: { token: 'fcm-del', platform: 'ios' } })
    const res = await app.inject({ method: 'DELETE', url: '/api/devices', headers: auth(token), payload: { token: 'fcm-del' } })
    expect(res.statusCode).toBe(200)
    expect(await notificationsRepo.tokensForUser(userId)).toHaveLength(0)
  })
})

describe('GET/PUT /api/notification-prefs', () => {
  it('returns defaults before anything is set', async () => {
    const { app, token } = await buildAndUser()
    const res = await app.inject({ method: 'GET', url: '/api/notification-prefs', headers: auth(token) })
    expect(res.statusCode).toBe(200)
    expect(res.json().prefs).toMatchObject({
      enabled: true, quietEnabled: false, quietStartMin: 1320, quietEndMin: 480
    })
  })

  it('persists an update and reflects it on the next GET', async () => {
    const { app, token } = await buildAndUser()
    const put = await app.inject({
      method: 'PUT', url: '/api/notification-prefs', headers: auth(token),
      payload: { enabled: false, quietEnabled: true, quietStartMin: 1380, quietEndMin: 420 }
    })
    expect(put.statusCode).toBe(200)
    expect(put.json().prefs).toMatchObject({ enabled: false, quietEnabled: true, quietStartMin: 1380, quietEndMin: 420 })
    const get = await app.inject({ method: 'GET', url: '/api/notification-prefs', headers: auth(token) })
    expect(get.json().prefs).toMatchObject({ enabled: false, quietEnabled: true, quietStartMin: 1380, quietEndMin: 420 })
  })

  it('only patches provided fields', async () => {
    const { app, token } = await buildAndUser()
    await app.inject({ method: 'PUT', url: '/api/notification-prefs', headers: auth(token), payload: { enabled: false } })
    const get = await app.inject({ method: 'GET', url: '/api/notification-prefs', headers: auth(token) })
    // quiet defaults untouched
    expect(get.json().prefs).toMatchObject({ enabled: false, quietStartMin: 1320, quietEndMin: 480 })
  })
})
