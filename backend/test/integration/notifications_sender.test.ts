import { describe, it, expect } from 'vitest'
import { createSender, type FcmMessaging } from '../../src/notifications/sender.js'
import * as notif from '../../src/repo/notifications.js'
import { makeUser } from '../helpers/factories.js'

const MSG = { title: 'T', body: 'B', data: { route: '/x', kind: 'session_live' } }

function fakeMessaging(responses: { success: boolean; error?: { code: string } }[]): {
  m: FcmMessaging
  calls: { tokens: string[] }[]
} {
  const calls: { tokens: string[] }[] = []
  const m: FcmMessaging = {
    async sendEachForMulticast(message) {
      calls.push({ tokens: message.tokens })
      return { responses }
    }
  }
  return { m, calls }
}

describe('createSender', () => {
  it('multicasts to all of a user\'s active tokens', async () => {
    const u = await makeUser()
    await notif.upsertToken({ userId: u.id, token: 'a', platform: 'ios' })
    await notif.upsertToken({ userId: u.id, token: 'b', platform: 'android' })

    const { m, calls } = fakeMessaging([{ success: true }, { success: true }])
    await createSender(m).sendToUser(u.id, MSG)

    expect(calls).toHaveLength(1)
    expect(calls[0].tokens.sort()).toEqual(['a', 'b'])
  })

  it('disables a token FCM reports as unregistered, keeps the good one', async () => {
    const u = await makeUser()
    await notif.upsertToken({ userId: u.id, token: 'good', platform: 'ios' })
    await notif.upsertToken({ userId: u.id, token: 'dead', platform: 'ios' })

    // tokensForUser orders are not guaranteed, so map response by token.
    const tokens = (await notif.tokensForUser(u.id)).map((t) => t.token)
    const responses = tokens.map((t) =>
      t === 'dead'
        ? { success: false, error: { code: 'messaging/registration-token-not-registered' } }
        : { success: true }
    )
    const { m } = fakeMessaging(responses)
    await createSender(m).sendToUser(u.id, MSG)

    const remaining = (await notif.tokensForUser(u.id)).map((t) => t.token)
    expect(remaining).toEqual(['good'])
  })

  it('does nothing when the user has no tokens', async () => {
    const u = await makeUser()
    const { m, calls } = fakeMessaging([])
    await createSender(m).sendToUser(u.id, MSG)
    expect(calls).toHaveLength(0)
  })
})
