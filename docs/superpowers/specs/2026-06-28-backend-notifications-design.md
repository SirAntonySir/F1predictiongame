# Backend-driven notifications (FCM)

**Status:** approved · **Date:** 2026-06-28

## Problem

Notifications today are **device-local only**. The Flutter app uses
`flutter_local_notifications` via `ReminderService`, which schedules three
"you haven't picked yet" reminders (5h / 1h / 10min before a session's lock)
on-device and cancels them when the user picks. Preferences (enabled, quiet
hours) live in `SharedPreferences`. The server is never involved.

A local notification can only be scheduled by the app on that device — **a
server cannot fire one**. We want the backend to own notifications so it can
(a) deliver reminders even if the app never opens, and (b) fire *default*
broadcasts to all opted-in users (e.g. "Quali starts in 1h", "Results are in").

## Goal

Move notification scheduling + delivery to the backend, replacing the local
scheduler entirely. The app becomes a **token reporter + receiver**; the
backend owns *when* and *to whom*.

## Decisions

- **Transport: FCM via `firebase-admin`.** One send-path for iOS + Android
  from the existing Fastify/Node backend; covers Android (builds already
  scaffolded) with no second transport; `sendEachForMulticast` returns dead
  tokens for cheap pruning; hangs off the existing `node-cron` scheduler.
- **Scope: move pick reminders server-side AND add default broadcasts.** The
  local scheduler is retired.
- **Replace local notifications entirely** (no on-device scheduling fallback).
  `flutter_local_notifications` is kept only to *display* foreground pushes.
- **Preferences move server-side.** Required because the server now fires the
  reminders and must honor `enabled` + quiet hours. Quiet hours need each
  user's timezone, reported at device registration.
- **Quiet hours v1 = skip** (a notification due during the quiet window is
  dropped, not deferred).
- **Broadcast audiences:** `session_live` → all opted-in users; `results_final`
  → users who submitted a pick for that session.

## Architecture

```
App (Flutter)                         Backend (Fastify + node-cron)
─────────────                         ─────────────────────────────
firebase_messaging                    src/notifications/
  ├ request permission                  ├ sender.ts      → firebase-admin → FCM
  ├ get + refresh FCM token  ──POST──▶  ├ dispatcher.ts  (new notifyJob, 1/min)
  ├ report platform + tz                │   ├ pick reminders (5h/1h/10m)
  └ receive + tap → deep-link           │   └ defaults: session_live, results_final
                                         └ idempotency via notification_log.claim
NotificationSettings  ──PUT prefs──▶  device_token, notification_pref (Drizzle)
(server-backed)
```

## Backend module — `src/notifications/`

### DB schema (`src/db/schema.ts` + generated migration)

- **`device_token`**: `id uuid pk`, `userId → user.id (cascade)`,
  `token text` (FCM token, unique index), `platform` enum(`ios`,`android`),
  `timezone text` (IANA), `createdAt`, `lastSeenAt`, `disabledAt timestamptz?`
  (set when FCM reports the token dead).
- **`notification_pref`** (one row per user): `userId pk → user.id`,
  `enabled bool default true`, `quietEnabled bool default false`,
  `quietStartMin int default 1320`, `quietEndMin int default 480`,
  `timezone text?`.
- **`notification_log`** (idempotency ledger): `id uuid pk`,
  `dedupeKey text` (unique index), `userId`, `kind text`, `sessionId int?`,
  `sentAt timestamptz`. The every-minute cron *claims* a key
  (`insert … on conflict do nothing`) before sending → no double-fires,
  crash-safe.

`kind` values: `pick_reminder_5h`, `pick_reminder_1h`, `pick_reminder_10m`,
`session_live`, `results_final`.
`dedupeKey` shape: `${kind}:${sessionId}:${userId}`.

### Repo — `src/repo/notifications.ts`

- tokens: `upsertToken({userId, token, platform, timezone})`,
  `tokensForUser(userId)`, `tokensForUsers(userIds)`, `disableToken(token)`,
  `deleteToken(userId, token)`.
- prefs: `getPrefOrDefault(userId)`, `upsertPref(userId, patch)`.
- log: `claim(dedupeKey, {userId, kind, sessionId}) → boolean` (true iff the
  row was newly inserted).

### Sender — `src/notifications/sender.ts`

Wraps `firebase-admin`. `sendToUser(userId, msg)` and `sendToUsers(userIds, msg)`
where `msg = {title, body, data}` (`data.route` drives the in-app deep link).
Loads active tokens → `messaging.sendEachForMulticast({tokens, notification, data})`
→ on per-token failure `messaging/registration-token-not-registered` or
`messaging/invalid-argument`, calls `disableToken`. The messaging client is
**injectable** so tests pass a fake. Firebase inits lazily from
`config.firebaseServiceAccount` (env `FIREBASE_SERVICE_ACCOUNT`, JSON); **if
unset, the sender no-ops and logs** so local dev still boots.

### Dispatcher — `src/notifications/dispatcher.ts`

`runNotificationsTick(now)`, wired as a new guarded `notifyJob =
cron.schedule('* * * * *', …)` in `src/crawler/scheduler.ts` (mirrors the
existing `isRunningTick` guard).

- **Pick reminders:** for each pickable session whose lock (`scheduledStart`)
  `now` just crossed at `−5h / −1h / −10m`, target users who (a) have no
  `prediction` for that session, (b) `enabled`, (c) not in quiet hours (per
  their `timezone`), (d) not already in `notification_log`. Send + claim.
- **`session_live`:** when `now` crosses `scheduledStart` → all opted-in users
  (claim once per user per session).
- **`results_final`:** when a session's `status` flips to `finished`/scored
  (detected via a once-per-session claim) → users who picked.

"Just crossed window X" is expressed as `lockTime − offset` falling in
`(now − tickInterval, now]`; the `notification_log` claim is the real guard, so
exact window width is not safety-critical.

### API routes — `src/api/routes/devices.ts`

Auth-gated via the existing `getCurrentUser(req)` hook. Registered alongside the
other routes in the server bootstrap.

- `POST /api/devices` `{token, platform, timezone}` → `upsertToken` for the
  current user; updates `notification_pref.timezone`.
- `DELETE /api/devices` `{token}` → on logout.
- `GET /api/notification-prefs` → pref row (or defaults).
- `PUT /api/notification-prefs` `{enabled, quietEnabled, quietStartMin,
  quietEndMin}` → upsert.

### Config / deps

`package.json`: add `firebase-admin`. `config.ts`: `firebaseServiceAccount?`
(parsed JSON), `notificationsEnabled` flag.

## App changes (Flutter)

- **Deps/config:** add `firebase_core`, `firebase_messaging`, `firebase_options.dart`
  (flutterfire). iOS: Push Notifications + Background Modes (remote
  notifications) capabilities; APNs auth key uploaded to Firebase once.
  `flutter_local_notifications` kept **only** to display foreground pushes.
- **New `lib/services/push_service.dart`** (replaces `ReminderService`):
  `Firebase.initializeApp` → request permission → get token →
  `POST /api/devices` (token, platform, `flutter_timezone`); `onTokenRefresh`
  → re-register; `onMessage` → display heads-up; `getInitialMessage` /
  `onMessageOpenedApp` → deep-link via go_router from `data.route`; top-level
  `@pragma('vm:entry-point')` background handler.
- **Retire `ReminderService`**: remove `syncFromUpcoming`/`_offsets`/scheduling
  and its call sites (e.g. in `home_cache_controller`).
- **`NotificationSettingsController` → server-backed**: swap `SharedPreferences`
  for `GET/PUT /api/notification-prefs` (cached for instant UI). `isInQuietHours`
  moves server-side; the client only stores values. Drop the
  `attachSettings → ReminderService` wiring.
- **Lifecycle:** init PushService after login (needs auth token to register);
  unregister on logout. Settings/notifications screens unchanged except the new
  data source + a "Enable notifications in iOS Settings" nudge when permission
  is denied.

## Error handling / edge cases

- Permission denied → no token registered → user gets nothing (accepted); show
  a settings nudge.
- Token rotation → `onTokenRefresh` re-registers; stale tokens pruned on send
  failure.
- Idempotency → `notification_log.claim` makes the every-minute cron safe and
  crash-safe (claim-before-send; single Render instance → no concurrency race).
- Quiet hours → send skipped if the target local time is in-window.
- Multiple devices → tokens per user; a user-scoped event rings all their
  devices once each.
- Firebase unconfigured (local dev) → sender no-ops; dispatcher still runs/logs.

## Testing

- **Backend (`make backend-test`, vitest):** `sender` (fake messaging → asserts
  multicast + dead-token pruning); `dispatcher` (sessions+picks+prefs+now →
  expected sends; second tick = no resend; quiet-hours/`enabled=false` skip);
  repo (`upsertToken` dedupe, `claim` idempotency, prefs default); routes
  (auth-gated CRUD).
- **App:** PushService registration posts token (mock api client); prefs
  controller GET/PUT; `data.route` → navigation mapping. Firebase is behind an
  interface so tests need no real Firebase.

## Implementation phases

1. **Backend schema + repo + device/prefs routes** (deployable; no sends yet).
2. **App:** Firebase + PushService registration + retire local scheduler +
   server-backed prefs (tokens now flow; manual test send possible).
3. **Backend:** sender + dispatcher (reminders → then defaults) + cron + dedupe.
4. **Polish:** deep-links, permission nudge, optional admin broadcast endpoint.

This spec covers all phases; each phase gets its own implementation plan.
