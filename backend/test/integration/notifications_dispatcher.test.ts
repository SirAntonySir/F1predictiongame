import { describe, it, expect } from 'vitest'
import * as seasons from '../../src/repo/seasons.js'
import * as events from '../../src/repo/events.js'
import * as sessions from '../../src/repo/sessions.js'
import * as predictions from '../../src/repo/predictions.js'
import * as notif from '../../src/repo/notifications.js'
import { runNotificationsTick, broadcastToAll, type NotificationMessage } from '../../src/notifications/dispatcher.js'
import { makeUser } from '../helpers/factories.js'

const NOW = new Date('2026-06-10T12:00:00.000Z')

async function scene() {
  await seasons.upsertSeason({ year: 2026, isCurrent: true })
  const ev = await events.upsertEvent({
    seasonYear: 2026, round: 1, name: 'Bahrain Grand Prix', circuitName: 'BIC', country: 'BH', hasSprint: false
  })
  return ev
}

async function sessionAt(eventId: number, start: Date, opts: { type?: 'race'; finished?: boolean } = {}) {
  const s = await sessions.upsertSession({
    eventId, type: opts.type ?? 'race',
    scheduledStart: start,
    scheduledEnd: new Date(start.getTime() + 2 * 60 * 60 * 1000),
    status: 'scheduled', openf1SessionKey: null
  })
  if (opts.finished) await sessions.markFinished(s.id)
  return s
}

function collector() {
  const calls: { userId: string; msg: NotificationMessage }[] = []
  const send = async (userId: string, msg: NotificationMessage) => { calls.push({ userId, msg }) }
  return { calls, send }
}

async function userWithToken(token: string) {
  const u = await makeUser()
  await notif.upsertToken({ userId: u.id, token, platform: 'ios' })
  return u
}

describe('runNotificationsTick', () => {
  it('sends a pick reminder to a token-holder who has not picked, once', async () => {
    const ev = await scene()
    await sessionAt(ev.id, new Date(NOW.getTime() + 59 * 60 * 1000)) // 1h bucket due
    const u = await userWithToken('tok-1')

    const c = collector()
    const r1 = await runNotificationsTick(NOW, c.send)
    expect(r1.sent).toBe(1)
    expect(c.calls).toHaveLength(1)
    expect(c.calls[0].userId).toBe(u.id)
    expect(c.calls[0].msg.data.kind).toBe('pick_reminder')

    // Second tick: claim already taken → no resend.
    const r2 = await runNotificationsTick(NOW, c.send)
    expect(r2.sent).toBe(0)
  })

  it('does not remind a user who already picked', async () => {
    const ev = await scene()
    const s = await sessionAt(ev.id, new Date(NOW.getTime() + 59 * 60 * 1000))
    const u = await userWithToken('tok-2')
    await predictions.upsertPredictionWithPicks(u.id, s.id, []) // entered, no slots

    const c = collector()
    const r = await runNotificationsTick(NOW, c.send)
    expect(r.sent).toBe(0)
  })

  it('respects the enabled=false preference', async () => {
    const ev = await scene()
    await sessionAt(ev.id, new Date(NOW.getTime() + 59 * 60 * 1000))
    const u = await userWithToken('tok-3')
    await notif.upsertPref(u.id, { enabled: false })

    const c = collector()
    expect((await runNotificationsTick(NOW, c.send)).sent).toBe(0)
  })

  it('suppresses during quiet hours', async () => {
    const ev = await scene()
    await sessionAt(ev.id, new Date(NOW.getTime() + 59 * 60 * 1000))
    const u = await userWithToken('tok-4')
    // 10:00–14:00 UTC window covers 12:00 NOW.
    await notif.upsertPref(u.id, { quietEnabled: true, quietStartMin: 600, quietEndMin: 840, timezone: 'UTC' })

    const c = collector()
    expect((await runNotificationsTick(NOW, c.send)).sent).toBe(0)
  })

  it('broadcasts session_live to token-holders when a session has just started', async () => {
    const ev = await scene()
    await sessionAt(ev.id, new Date(NOW.getTime() - 5 * 60 * 1000)) // started 5m ago
    await userWithToken('tok-5a')
    await userWithToken('tok-5b')

    const c = collector()
    const r = await runNotificationsTick(NOW, c.send)
    expect(r.sent).toBe(2)
    expect(c.calls.every((x) => x.msg.data.kind === 'session_live')).toBe(true)
  })

  it('sends results_final to users who picked a finished session', async () => {
    const ev = await scene()
    const s = await sessionAt(ev.id, new Date(NOW.getTime() - 3 * 60 * 60 * 1000), { finished: true })
    const picker = await userWithToken('tok-6')
    await predictions.upsertPredictionWithPicks(picker.id, s.id, [])
    // A non-picker token-holder should NOT get the results notification.
    await userWithToken('tok-7')

    const c = collector()
    const r = await runNotificationsTick(NOW, c.send)
    expect(r.sent).toBe(1)
    expect(c.calls[0].userId).toBe(picker.id)
    expect(c.calls[0].msg.data.kind).toBe('results_final')
  })

  it('broadcastToAll sends to every opted-in device-holder, skipping disabled', async () => {
    await scene()
    const a = await userWithToken('b-1')
    const b = await userWithToken('b-2')
    await notif.upsertPref(b.id, { enabled: false }) // opted out

    const c = collector()
    const r = await broadcastToAll(c.send, { title: 'Hi', body: 'all', data: { kind: 'broadcast' } })
    expect(r.sent).toBe(1)
    expect(c.calls.map((x) => x.userId)).toEqual([a.id])
  })

  it('no-ops when there are no registered devices', async () => {
    const ev = await scene()
    await sessionAt(ev.id, new Date(NOW.getTime() + 59 * 60 * 1000))
    const c = collector()
    expect((await runNotificationsTick(NOW, c.send)).sent).toBe(0)
  })
})
