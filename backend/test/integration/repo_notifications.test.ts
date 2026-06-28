import { describe, it, expect } from 'vitest'
import * as repo from '../../src/repo/notifications.js'
import { makeUser } from '../helpers/factories.js'

describe('device token repo', () => {
  it('upsertToken is keyed on the token (no duplicate, updates platform/tz)', async () => {
    const u = await makeUser()
    await repo.upsertToken({ userId: u.id, token: 't1', platform: 'ios', timezone: 'Europe/Vienna' })
    await repo.upsertToken({ userId: u.id, token: 't1', platform: 'android', timezone: 'America/New_York' })
    const tokens = await repo.tokensForUser(u.id)
    expect(tokens).toHaveLength(1)
    expect(tokens[0].platform).toBe('android')
    expect(tokens[0].timezone).toBe('America/New_York')
  })

  it('disableToken prunes a token from the active list', async () => {
    const u = await makeUser()
    await repo.upsertToken({ userId: u.id, token: 'dead', platform: 'ios' })
    await repo.disableToken('dead')
    expect(await repo.tokensForUser(u.id)).toHaveLength(0)
  })

  it('re-registering a disabled token re-enables it', async () => {
    const u = await makeUser()
    await repo.upsertToken({ userId: u.id, token: 'rev', platform: 'ios' })
    await repo.disableToken('rev')
    await repo.upsertToken({ userId: u.id, token: 'rev', platform: 'ios' })
    expect(await repo.tokensForUser(u.id)).toHaveLength(1)
  })

  it('tokensForUsers fans out across a set and ignores an empty set', async () => {
    const a = await makeUser()
    const b = await makeUser()
    await repo.upsertToken({ userId: a.id, token: 'a1', platform: 'ios' })
    await repo.upsertToken({ userId: b.id, token: 'b1', platform: 'android' })
    const tokens = await repo.tokensForUsers([a.id, b.id])
    expect(tokens.map((t) => t.token).sort()).toEqual(['a1', 'b1'])
    expect(await repo.tokensForUsers([])).toEqual([])
  })
})

describe('preferences repo', () => {
  it('getPrefOrDefault returns defaults for an unseen user', async () => {
    const u = await makeUser()
    const pref = await repo.getPrefOrDefault(u.id)
    expect(pref).toMatchObject({ enabled: true, quietEnabled: false, quietStartMin: 1320, quietEndMin: 480, timezone: null })
  })

  it('upsertPref patches only provided fields', async () => {
    const u = await makeUser()
    await repo.upsertPref(u.id, { enabled: false })
    await repo.upsertPref(u.id, { quietEnabled: true })
    const pref = await repo.getPrefOrDefault(u.id)
    expect(pref).toMatchObject({ enabled: false, quietEnabled: true, quietStartMin: 1320 })
  })
})

describe('notification_log claim (idempotency)', () => {
  it('claims a key once; subsequent claims return false', async () => {
    const u = await makeUser()
    const first = await repo.claim('pick_reminder_1h:5:x', { userId: u.id, kind: 'pick_reminder_1h' })
    const second = await repo.claim('pick_reminder_1h:5:x', { userId: u.id, kind: 'pick_reminder_1h' })
    expect(first).toBe(true)
    expect(second).toBe(false)
    expect(await repo.wasClaimed('pick_reminder_1h:5:x')).toBe(true)
  })

  it('distinct keys each claim independently', async () => {
    const u = await makeUser()
    expect(await repo.claim('k:1', { userId: u.id, kind: 'session_live' })).toBe(true)
    expect(await repo.claim('k:2', { userId: u.id, kind: 'session_live' })).toBe(true)
  })
})
