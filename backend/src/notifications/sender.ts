import * as notifRepo from '../repo/notifications.js'
import { config } from '../config.js'
import type { NotificationMessage, SendFn } from './dispatcher.js'

/// Minimal slice of firebase-admin's Messaging we depend on — lets tests inject
/// a fake without pulling in the SDK or a real Firebase project.
export interface FcmMessaging {
  sendEachForMulticast(message: {
    tokens: string[]
    notification: { title: string; body: string }
    data?: Record<string, string>
  }): Promise<{ responses: { success: boolean; error?: { code: string } }[] }>
}

/// FCM error codes that mean "this token is dead, stop using it".
const DEAD_TOKEN_CODES = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
  'messaging/invalid-argument'
])

/// Build a [SendFn] over a messaging client: looks up the user's active tokens,
/// multicasts, and prunes any token FCM reports as dead.
export function createSender(messaging: FcmMessaging): { sendToUser: SendFn } {
  async function sendToUser(userId: string, msg: NotificationMessage): Promise<void> {
    const tokens = await notifRepo.tokensForUser(userId)
    if (tokens.length === 0) return
    const res = await messaging.sendEachForMulticast({
      tokens: tokens.map((t) => t.token),
      notification: { title: msg.title, body: msg.body },
      data: msg.data
    })
    await Promise.all(
      res.responses.map(async (r, i) => {
        const token = tokens[i]
        if (token && !r.success && r.error && DEAD_TOKEN_CODES.has(r.error.code)) {
          await notifRepo.disableToken(token.token)
        }
      })
    )
  }
  return { sendToUser }
}

let _messaging: FcmMessaging | null | undefined

/// Lazily initialise firebase-admin from [config.firebaseServiceAccount].
/// Returns null when no service account is configured (local dev / not yet
/// wired) so the dispatcher simply doesn't send.
export async function resolveMessaging(): Promise<FcmMessaging | null> {
  if (_messaging !== undefined) return _messaging
  const raw = config.firebaseServiceAccount
  if (!raw) {
    _messaging = null
    return null
  }
  try {
    const { initializeApp, cert, getApps } = await import('firebase-admin/app')
    const { getMessaging } = await import('firebase-admin/messaging')
    if (getApps().length === 0) {
      initializeApp({ credential: cert(JSON.parse(raw)) })
    }
    _messaging = getMessaging() as unknown as FcmMessaging
  } catch (e) {
    console.error('[notifications] firebase-admin init failed:', e)
    _messaging = null
  }
  return _messaging
}

/// Test seam — drop the memoised client.
export function _resetMessagingForTests(): void {
  _messaging = undefined
}
