import * as sessionsRepo from '../repo/sessions.js'
import * as eventsRepo from '../repo/events.js'
import * as predictionsRepo from '../repo/predictions.js'
import * as notifRepo from '../repo/notifications.js'
import { picksRequiredFor } from '../scoring/index.js'
import type { StoredSession } from '../repo/sessions.js'
import type { StoredEvent } from '../repo/events.js'
import type { NotificationPref } from '../repo/notifications.js'

export type NotificationMessage = {
  title: string
  body: string
  data: Record<string, string>
}

export type SendFn = (userId: string, msg: NotificationMessage) => Promise<void>

/// Pick-reminder lead times. Each fires once (claim-guarded) when its threshold
/// is freshly crossed — see [GRACE_MS].
const REMINDER_OFFSETS = [
  { kind: 'pick_reminder_5h', ms: 5 * 60 * 60 * 1000 },
  { kind: 'pick_reminder_1h', ms: 1 * 60 * 60 * 1000 },
  { kind: 'pick_reminder_10m', ms: 10 * 60 * 1000 }
] as const

/// A reminder bucket only fires if its threshold was crossed within this window,
/// so a late-registering device doesn't get a stale "5h to go" the moment it
/// appears. Wide enough to absorb a few missed minute-ticks; the claim ledger
/// makes overlap harmless.
const GRACE_MS = 6 * 60 * 1000
/// "Session live" broadcast fires for this long after the scheduled start.
const LIVE_GRACE_MS = 12 * 60 * 1000
/// How far back to scan finished sessions for the "results are in" alert.
const FINISHED_LOOKBACK_MS = 24 * 60 * 60 * 1000

/// Evaluate all notification triggers for [now] and dispatch via [send].
/// Idempotent: every send is guarded by a claim on the notification log, so the
/// per-minute cron and crash-restarts never double-fire. [send] is injected so
/// tests can assert dispatch decisions without Firebase.
export async function runNotificationsTick(now: Date, send: SendFn): Promise<{ sent: number }> {
  const userIds = await notifRepo.activeTokenUserIds()
  if (userIds.length === 0) return { sent: 0 }

  const prefs = new Map<string, NotificationPref>()
  for (const id of userIds) prefs.set(id, await notifRepo.getPrefOrDefault(id))
  const eventCache = new Map<number, StoredEvent | null>()
  const eventFor = async (eventId: number) => {
    if (!eventCache.has(eventId)) eventCache.set(eventId, await eventsRepo.getById(eventId))
    return eventCache.get(eventId) ?? null
  }

  let sent = 0
  const t = now.getTime()

  // Window covers just-started sessions (for "live") through the furthest
  // reminder lead (5h ahead).
  const sessions = await sessionsRepo.listScheduledStartingBetween(
    new Date(t - LIVE_GRACE_MS),
    new Date(t + REMINDER_OFFSETS[0].ms)
  )

  for (const s of sessions) {
    const start = s.scheduledStart.getTime()

    // --- pick reminders: pickable sessions, before they start ---
    if (picksRequiredFor(s.type) !== null && start > t) {
      const dueBuckets = REMINDER_OFFSETS.filter((o) => {
        const thr = start - o.ms
        return t >= thr && t - thr <= GRACE_MS
      })
      if (dueBuckets.length > 0) {
        const picked = new Set(
          (await predictionsRepo.listForSessionWithPicks(s.id)).map((p) => p.userId)
        )
        const ev = await eventFor(s.eventId)
        for (const bucket of dueBuckets) {
          for (const uid of userIds) {
            const pref = prefs.get(uid)!
            if (!pref.enabled || picked.has(uid) || inQuietHours(now, pref)) continue
            if (await notifRepo.claim(`${bucket.kind}:${s.id}:${uid}`, {
              userId: uid, kind: bucket.kind, sessionId: s.id
            })) {
              await send(uid, reminderMessage(ev, s)); sent++
            }
          }
        }
      }
    }

    // --- session live: just started ---
    if (start <= t && t - start <= LIVE_GRACE_MS) {
      const ev = await eventFor(s.eventId)
      for (const uid of userIds) {
        const pref = prefs.get(uid)!
        if (!pref.enabled || inQuietHours(now, pref)) continue
        if (await notifRepo.claim(`session_live:${s.id}:${uid}`, {
          userId: uid, kind: 'session_live', sessionId: s.id
        })) {
          await send(uid, liveMessage(ev, s)); sent++
        }
      }
    }
  }

  // --- results final: finished sessions → the users who picked them ---
  const finished = await sessionsRepo.listFinishedEndedSince(new Date(t - FINISHED_LOOKBACK_MS))
  for (const s of finished) {
    const pickers = await predictionsRepo.listForSessionWithPicks(s.id)
    if (pickers.length === 0) continue
    const ev = await eventFor(s.eventId)
    for (const p of pickers) {
      const pref = prefs.get(p.userId)
      if (!pref) continue // no active device
      if (!pref.enabled || inQuietHours(now, pref)) continue
      if (await notifRepo.claim(`results_final:${s.id}:${p.userId}`, {
        userId: p.userId, kind: 'results_final', sessionId: s.id
      })) {
        await send(p.userId, resultsMessage(ev, s)); sent++
      }
    }
  }

  return { sent }
}

/// Fan a one-off message out to every opted-in device-holder. Used by the admin
/// broadcast endpoint. No claim ledger (an admin triggers it deliberately, once)
/// and no quiet-hours gate (the admin chooses when to send); [enabled] is still
/// honoured so opted-out users are skipped.
export async function broadcastToAll(send: SendFn, msg: NotificationMessage): Promise<{ sent: number }> {
  const userIds = await notifRepo.activeTokenUserIds()
  let sent = 0
  for (const uid of userIds) {
    const pref = await notifRepo.getPrefOrDefault(uid)
    if (!pref.enabled) continue
    await send(uid, msg)
    sent++
  }
  return { sent }
}

/// True if [now], in the user's timezone, lies inside their quiet window.
/// Without a timezone we can't evaluate it, so we don't suppress.
export function inQuietHours(now: Date, pref: NotificationPref): boolean {
  if (!pref.quietEnabled || !pref.timezone) return false
  let mins: number
  try {
    const parts = new Intl.DateTimeFormat('en-US', {
      timeZone: pref.timezone, hour: '2-digit', minute: '2-digit', hour12: false
    }).formatToParts(now)
    const h = Number(parts.find((p) => p.type === 'hour')!.value) % 24
    const m = Number(parts.find((p) => p.type === 'minute')!.value)
    mins = h * 60 + m
  } catch {
    return false
  }
  const { quietStartMin: s, quietEndMin: e } = pref
  return s <= e ? mins >= s && mins < e : mins >= s || mins < e
}

const eventName = (ev: StoredEvent | null) => ev?.name ?? 'the next session'
const typeLabel = (s: StoredSession) => s.type.toUpperCase().replace('_', ' ')
const route = (s: StoredSession, ev: StoredEvent | null) =>
  ev ? `/race/${ev.round}/${s.id}` : `/predict?session=${s.id}`

function reminderMessage(ev: StoredEvent | null, s: StoredSession): NotificationMessage {
  return {
    title: `${eventName(ev)} — make your pick`,
    body: `${typeLabel(s)} locks soon and you haven't picked yet.`,
    data: { route: `/predict?session=${s.id}`, kind: 'pick_reminder' }
  }
}

function liveMessage(ev: StoredEvent | null, s: StoredSession): NotificationMessage {
  return {
    title: `${eventName(ev)} is live`,
    body: `${typeLabel(s)} has started — follow it live.`,
    data: { route: route(s, ev), kind: 'session_live' }
  }
}

function resultsMessage(ev: StoredEvent | null, s: StoredSession): NotificationMessage {
  return {
    title: `${eventName(ev)} — results are in`,
    body: `See how your ${typeLabel(s)} picks scored.`,
    data: { route: route(s, ev), kind: 'results_final' }
  }
}
