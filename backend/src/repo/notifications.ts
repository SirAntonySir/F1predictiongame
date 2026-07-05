import { and, desc, eq, inArray, isNull, sql } from 'drizzle-orm'
import { getDb } from '../db/client.js'
import { deviceToken, notificationLog, notificationPref } from '../db/schema.js'

export type DevicePlatform = 'ios' | 'android'

export type StoredDeviceToken = {
  id: string
  userId: string
  token: string
  platform: DevicePlatform
  timezone: string | null
  createdAt: Date
  lastSeenAt: Date
  disabledAt: Date | null
}

export type NotificationPref = {
  userId: string
  enabled: boolean
  quietEnabled: boolean
  quietStartMin: number
  quietEndMin: number
  timezone: string | null
}

const PREF_DEFAULTS = {
  enabled: true,
  quietEnabled: false,
  quietStartMin: 1320,
  quietEndMin: 480,
  timezone: null as string | null
}

// ---- device tokens ---------------------------------------------------------

/// Register (or refresh) an FCM token for a user. Keyed on the token itself:
/// the same physical token re-registering — even under a different user after
/// a re-login on the device — moves to the current user and is re-enabled.
export async function upsertToken(input: {
  userId: string
  token: string
  platform: DevicePlatform
  timezone?: string | null
}): Promise<StoredDeviceToken> {
  const db = getDb()
  const [row] = await db
    .insert(deviceToken)
    .values({
      userId: input.userId,
      token: input.token,
      platform: input.platform,
      timezone: input.timezone ?? null
    })
    .onConflictDoUpdate({
      target: deviceToken.token,
      set: {
        userId: input.userId,
        platform: input.platform,
        timezone: input.timezone ?? null,
        lastSeenAt: new Date(),
        disabledAt: null
      }
    })
    .returning()
  return row as StoredDeviceToken
}

/// Active (non-disabled) tokens for a single user.
export async function tokensForUser(userId: string): Promise<StoredDeviceToken[]> {
  const db = getDb()
  const rows = await db
    .select()
    .from(deviceToken)
    .where(and(eq(deviceToken.userId, userId), isNull(deviceToken.disabledAt)))
  return rows as StoredDeviceToken[]
}

/// Active tokens for a set of users (broadcast fan-out). Empty set → no query.
export async function tokensForUsers(userIds: string[]): Promise<StoredDeviceToken[]> {
  if (userIds.length === 0) return []
  const db = getDb()
  const rows = await db
    .select()
    .from(deviceToken)
    .where(and(inArray(deviceToken.userId, userIds), isNull(deviceToken.disabledAt)))
  return rows as StoredDeviceToken[]
}

/// Mark a token dead (FCM reported it unregistered/invalid). Idempotent.
export async function disableToken(token: string): Promise<void> {
  const db = getDb()
  await db
    .update(deviceToken)
    .set({ disabledAt: new Date() })
    .where(eq(deviceToken.token, token))
}

/// Remove a token outright — used on explicit logout from a device.
export async function deleteToken(userId: string, token: string): Promise<void> {
  const db = getDb()
  await db
    .delete(deviceToken)
    .where(and(eq(deviceToken.userId, userId), eq(deviceToken.token, token)))
}

/// Distinct user ids that have at least one active (non-disabled) token — the
/// only users who can actually receive anything, so the dispatcher's audience.
export async function activeTokenUserIds(): Promise<string[]> {
  const db = getDb()
  const rows = await db
    .selectDistinct({ userId: deviceToken.userId })
    .from(deviceToken)
    .where(isNull(deviceToken.disabledAt))
  return rows.map((r) => r.userId)
}

/// Admin diagnostics: every registered device with its owner's opt-in state.
/// Tokens are masked to their last 6 chars — enough to tell rows apart without
/// leaking a sendable credential. `enabled` reflects the user's pref (default
/// true when they've never touched settings). Newest-seen first.
export type DeviceDiagnosticRow = {
  userId: string
  platform: DevicePlatform
  tokenSuffix: string
  enabled: boolean
  timezone: string | null
  createdAt: Date
  lastSeenAt: Date
  disabledAt: Date | null
}

export async function listDevices(): Promise<DeviceDiagnosticRow[]> {
  const db = getDb()
  const rows = await db
    .select({
      userId: deviceToken.userId,
      platform: deviceToken.platform,
      token: deviceToken.token,
      timezone: deviceToken.timezone,
      createdAt: deviceToken.createdAt,
      lastSeenAt: deviceToken.lastSeenAt,
      disabledAt: deviceToken.disabledAt,
      enabled: notificationPref.enabled
    })
    .from(deviceToken)
    .leftJoin(notificationPref, eq(notificationPref.userId, deviceToken.userId))
    .orderBy(desc(deviceToken.lastSeenAt))
  return rows.map((r) => ({
    userId: r.userId,
    platform: r.platform as DevicePlatform,
    tokenSuffix: r.token.slice(-6),
    enabled: r.enabled ?? true,
    timezone: r.timezone,
    createdAt: r.createdAt,
    lastSeenAt: r.lastSeenAt,
    disabledAt: r.disabledAt
  }))
}

// ---- preferences -----------------------------------------------------------

/// A user's preferences, or the shared defaults when they've never been set.
export async function getPrefOrDefault(userId: string): Promise<NotificationPref> {
  const db = getDb()
  const rows = await db
    .select()
    .from(notificationPref)
    .where(eq(notificationPref.userId, userId))
    .limit(1)
  const row = rows[0]
  if (!row) return { userId, ...PREF_DEFAULTS }
  return {
    userId,
    enabled: row.enabled,
    quietEnabled: row.quietEnabled,
    quietStartMin: row.quietStartMin,
    quietEndMin: row.quietEndMin,
    timezone: row.timezone
  }
}

/// Create or patch a user's preferences. Only the provided fields change.
export async function upsertPref(
  userId: string,
  patch: Partial<Omit<NotificationPref, 'userId'>>
): Promise<NotificationPref> {
  const db = getDb()
  const set: Record<string, unknown> = { updatedAt: new Date() }
  if (patch.enabled !== undefined) set.enabled = patch.enabled
  if (patch.quietEnabled !== undefined) set.quietEnabled = patch.quietEnabled
  if (patch.quietStartMin !== undefined) set.quietStartMin = patch.quietStartMin
  if (patch.quietEndMin !== undefined) set.quietEndMin = patch.quietEndMin
  if (patch.timezone !== undefined) set.timezone = patch.timezone

  await db
    .insert(notificationPref)
    .values({
      userId,
      enabled: patch.enabled ?? PREF_DEFAULTS.enabled,
      quietEnabled: patch.quietEnabled ?? PREF_DEFAULTS.quietEnabled,
      quietStartMin: patch.quietStartMin ?? PREF_DEFAULTS.quietStartMin,
      quietEndMin: patch.quietEndMin ?? PREF_DEFAULTS.quietEndMin,
      timezone: patch.timezone ?? PREF_DEFAULTS.timezone
    })
    .onConflictDoUpdate({ target: notificationPref.userId, set })
  return getPrefOrDefault(userId)
}

// ---- idempotency log -------------------------------------------------------

/// Atomically claim a dedupe key. Returns true the first time (the caller
/// should then send) and false on every subsequent call for the same key, so
/// the every-minute dispatcher never double-fires.
export async function claim(
  dedupeKey: string,
  meta: { userId: string; kind: string; sessionId?: number | null }
): Promise<boolean> {
  const db = getDb()
  const rows = await db
    .insert(notificationLog)
    .values({
      dedupeKey,
      userId: meta.userId,
      kind: meta.kind,
      sessionId: meta.sessionId ?? null
    })
    .onConflictDoNothing({ target: notificationLog.dedupeKey })
    .returning({ id: notificationLog.id })
  return rows.length > 0
}

/// Test/maintenance helper — has a key already been claimed?
export async function wasClaimed(dedupeKey: string): Promise<boolean> {
  const db = getDb()
  const rows = await db
    .select({ one: sql<number>`1` })
    .from(notificationLog)
    .where(eq(notificationLog.dedupeKey, dedupeKey))
    .limit(1)
  return rows.length > 0
}
