import {
  pgTable, integer, text, boolean, timestamp, pgEnum, primaryKey, uniqueIndex, index, uuid, customType, jsonb, doublePrecision
} from 'drizzle-orm/pg-core'
import { sql } from 'drizzle-orm'

const bytea = customType<{ data: Buffer; driverData: Buffer }>({
  dataType: () => 'bytea'
})

export const sessionType = pgEnum('session_type', [
  'fp1', 'fp2', 'fp3', 'qualifying', 'sprint_quali', 'sprint', 'race'
])

export const sessionStatus = pgEnum('session_status', ['scheduled', 'finished'])

export const season = pgTable('season', {
  year: integer('year').primaryKey(),
  isCurrent: boolean('is_current').notNull().default(false)
})

export const event = pgTable('event', {
  id: integer('id').primaryKey().generatedAlwaysAsIdentity(),
  seasonYear: integer('season_year').notNull().references(() => season.year, { onDelete: 'cascade' }),
  round: integer('round').notNull(),
  name: text('name').notNull(),
  circuitName: text('circuit_name').notNull(),
  country: text('country').notNull(),
  hasSprint: boolean('has_sprint').notNull().default(false)
}, (t) => ({
  uqSeasonRound: uniqueIndex('event_season_round_uq').on(t.seasonYear, t.round)
}))

export const session = pgTable('session', {
  id: integer('id').primaryKey().generatedAlwaysAsIdentity(),
  eventId: integer('event_id').notNull().references(() => event.id, { onDelete: 'cascade' }),
  type: sessionType('type').notNull(),
  scheduledStart: timestamp('scheduled_start', { withTimezone: true }).notNull(),
  scheduledEnd: timestamp('scheduled_end', { withTimezone: true }).notNull(),
  status: sessionStatus('status').notNull().default('scheduled'),
  openf1SessionKey: integer('openf1_session_key'),
  // Stamped by the reconciliation pass after it has either replaced the
  // OpenF1-sourced result rows with Jolpica's official classification or
  // confirmed they agree. Null = never reconciled (still provisional if
  // session_result.source = 'openf1').
  lastReconciledAt: timestamp('last_reconciled_at', { withTimezone: true })
}, (t) => ({
  uqEventType: uniqueIndex('session_event_type_uq').on(t.eventId, t.type),
  idxStatusStart: index('session_status_start_idx').on(t.status, t.scheduledStart),
  idxStatusEnd: index('session_status_end_idx').on(t.status, t.scheduledEnd)
}))

export const driver = pgTable('driver', {
  code: text('code').primaryKey(),
  givenName: text('given_name').notNull(),
  familyName: text('family_name').notNull(),
  nationality: text('nationality'),
  permanentNumber: integer('permanent_number'),
  wikipediaUrl: text('wikipedia_url'),
  imageUrl: text('image_url'),
  imageUrlOverride: text('image_url_override'),
  headshotUrl: text('headshot_url')
})

export const constructor = pgTable('constructor', {
  id: text('id').primaryKey(),
  name: text('name').notNull(),
  nationality: text('nationality'),
  wikipediaUrl: text('wikipedia_url'),
  imageUrl: text('image_url'),
  imageUrlOverride: text('image_url_override'),
  teamColour: text('team_colour')
})

export const sessionResult = pgTable('session_result', {
  sessionId: integer('session_id').notNull().references(() => session.id, { onDelete: 'cascade' }),
  position: integer('position').notNull(),
  driverCode: text('driver_code').notNull().references(() => driver.code),
  driverName: text('driver_name').notNull(),
  constructorId: text('constructor_id').notNull().references(() => constructor.id),
  constructorName: text('constructor_name').notNull(),
  raceTime: text('race_time'),
  status: text('status'),
  points: integer('points'),
  fastestLap: text('fastest_lap'),
  fastestLapTime: text('fastest_lap_time'),
  fastestLapSpeed: text('fastest_lap_speed'),
  q1: text('q1'),
  q2: text('q2'),
  q3: text('q3'),
  // 'openf1' = sourced from OpenF1 (fast, may not reflect post-stewards
  // penalties yet). 'jolpica' = official Ergast/Jolpica classification.
  // The reconciliation pass replaces 'openf1' rows with 'jolpica' once the
  // official classification is published. Existing rows from before this
  // column was introduced default to 'jolpica' (matches old behaviour).
  source: text('source').notNull().default('jolpica')
}, (t) => ({
  pk: primaryKey({ columns: [t.sessionId, t.position] })
}))

export const driverStanding = pgTable('driver_standing', {
  seasonYear: integer('season_year').notNull().references(() => season.year, { onDelete: 'cascade' }),
  driverCode: text('driver_code').notNull().references(() => driver.code),
  position: integer('position').notNull(),
  points: integer('points').notNull(),
  wins: integer('wins').notNull(),
  constructorId: text('constructor_id').notNull().references(() => constructor.id),
  updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow()
}, (t) => ({
  pk: primaryKey({ columns: [t.seasonYear, t.driverCode] })
}))

export const constructorStanding = pgTable('constructor_standing', {
  seasonYear: integer('season_year').notNull().references(() => season.year, { onDelete: 'cascade' }),
  constructorId: text('constructor_id').notNull().references(() => constructor.id),
  position: integer('position').notNull(),
  points: integer('points').notNull(),
  wins: integer('wins').notNull(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow()
}, (t) => ({
  pk: primaryKey({ columns: [t.seasonYear, t.constructorId] })
}))

export const user = pgTable('user', {
  id: uuid('id').primaryKey().defaultRandom(),
  email: text('email').notNull(),
  passwordHash: text('password_hash').notNull(),
  displayName: text('display_name').notNull(),
  // Opaque AvatarConfig JSON (the client's AvatarConfig.toJson()); rendered
  // client-side. Null = user hasn't customized → clients show the default
  // livery. Never introspected by the backend beyond parse+size validation.
  avatarConfig: text('avatar_config'),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow()
}, (t) => ({
  emailUq: uniqueIndex('user_email_uq').on(t.email)
}))

export const appSession = pgTable('app_session', {
  id: uuid('id').primaryKey().defaultRandom(),
  userId: uuid('user_id').notNull().references(() => user.id, { onDelete: 'cascade' }),
  tokenHash: bytea('token_hash').notNull(),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  lastUsedAt: timestamp('last_used_at', { withTimezone: true }).notNull().defaultNow(),
  expiresAt: timestamp('expires_at', { withTimezone: true }).notNull(),
  userAgent: text('user_agent')
}, (t) => ({
  tokenHashUq: uniqueIndex('app_session_token_hash_uq').on(t.tokenHash),
  userIdx: index('app_session_user_idx').on(t.userId),
  expiresIdx: index('app_session_expires_idx').on(t.expiresAt)
}))

export const league = pgTable('league', {
  id: uuid('id').primaryKey().defaultRandom(),
  ownerUserId: uuid('owner_user_id').notNull().references(() => user.id, { onDelete: 'cascade' }),
  name: text('name').notNull(),
  joinCode: text('join_code').notNull(),
  // Optional join-gate password (bcrypt hash). Null = open league, joiners
  // only need the join code. When set, joiners must provide the matching
  // password alongside the join code or the call 401s.
  passwordHash: text('password_hash'),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow()
}, (t) => ({
  ownerUq: uniqueIndex('league_owner_uq').on(t.ownerUserId),
  joinCodeUq: uniqueIndex('league_join_code_uq').on(t.joinCode)
}))

export const leagueMember = pgTable('league_member', {
  leagueId: uuid('league_id').notNull().references(() => league.id, { onDelete: 'cascade' }),
  userId: uuid('user_id').notNull().references(() => user.id, { onDelete: 'cascade' }),
  joinedAt: timestamp('joined_at', { withTimezone: true }).notNull().defaultNow()
}, (t) => ({
  pk: primaryKey({ columns: [t.leagueId, t.userId] }),
  userIdx: index('league_member_user_idx').on(t.userId)
}))

export const prediction = pgTable('prediction', {
  id: uuid('id').primaryKey().defaultRandom(),
  userId: uuid('user_id').notNull().references(() => user.id, { onDelete: 'cascade' }),
  sessionId: integer('session_id').notNull().references(() => session.id, { onDelete: 'cascade' }),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow(),
  // 'app' = entered via the in-app predict screen (default).
  // 'import' = bulk-imported by a league owner via /imports endpoint.
  // Surfaced in the UI so members can tell apart in-app picks from
  // backfilled ones.
  source: text('source').notNull().default('app'),
  importedBy: uuid('imported_by').references(() => user.id),
  importedAt: timestamp('imported_at', { withTimezone: true })
}, (t) => ({
  userSessionUq: uniqueIndex('prediction_user_session_uq').on(t.userId, t.sessionId),
  sessionIdx: index('prediction_session_idx').on(t.sessionId)
}))

/// Audit row per `/imports` upload. Lets the league surface "imported by
/// Anton on 2026-06-13: 47 applied, 2 skipped" without scanning every
/// prediction row.
export const predictionImport = pgTable('prediction_import', {
  id: uuid('id').primaryKey().defaultRandom(),
  leagueId: uuid('league_id').notNull().references(() => league.id, { onDelete: 'cascade' }),
  seasonYear: integer('season_year').notNull().references(() => season.year),
  uploadedBy: uuid('uploaded_by').notNull().references(() => user.id),
  uploadedAt: timestamp('uploaded_at', { withTimezone: true }).notNull().defaultNow(),
  schemaVersion: integer('schema_version').notNull(),
  appliedCount: integer('applied_count').notNull(),
  skippedCount: integer('skipped_count').notNull(),
  rawFilename: text('raw_filename')
}, (t) => ({
  leagueIdx: index('prediction_import_league_idx').on(t.leagueId, t.uploadedAt)
}))

export const predictionPick = pgTable('prediction_pick', {
  predictionId: uuid('prediction_id').notNull().references(() => prediction.id, { onDelete: 'cascade' }),
  position: integer('position').notNull(),
  driverCode: text('driver_code').notNull().references(() => driver.code)
}, (t) => ({
  pk: primaryKey({ columns: [t.predictionId, t.position] }),
  driverIdx: index('prediction_pick_driver_idx').on(t.driverCode)
}))

export const score = pgTable('score', {
  userId: uuid('user_id').notNull().references(() => user.id, { onDelete: 'cascade' }),
  sessionId: integer('session_id').references(() => session.id, { onDelete: 'cascade' }),
  pointsTotal: integer('points_total').notNull(),
  breakdown: jsonb('breakdown').notNull(),
  computedAt: timestamp('computed_at', { withTimezone: true }).notNull().defaultNow(),
  kind: text('kind').notNull().default('session'),
  seasonYear: integer('season_year').references(() => season.year, { onDelete: 'cascade' }),
  preseasonCategory: text('preseason_category')
}, (t) => ({
  sessionUq: uniqueIndex('score_session_uq').on(t.userId, t.sessionId).where(sql`${t.kind} = 'session'`),
  preseasonUq: uniqueIndex('score_preseason_uq').on(t.userId, t.seasonYear, t.preseasonCategory).where(sql`${t.kind} = 'preseason'`),
  sessionIdx: index('score_session_idx').on(t.sessionId),
  userIdx: index('score_user_idx').on(t.userId)
}))

export const preseasonCategory = pgEnum('preseason_category', [
  'surprise', 'disappointment', 'dnf', 'poles', 'fastest_lap', 'wdc_wcc'
])

export const preseasonPick = pgTable('preseason_pick', {
  userId: uuid('user_id').notNull().references(() => user.id, { onDelete: 'cascade' }),
  seasonYear: integer('season_year').notNull().references(() => season.year, { onDelete: 'cascade' }),
  category: preseasonCategory('category').notNull(),
  driverCode: text('driver_code').references(() => driver.code),
  constructorId: text('constructor_id').references(() => constructor.id),
  updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow()
}, (t) => ({
  pk: primaryKey({ columns: [t.userId, t.seasonYear, t.category] }),
  seasonCategoryIdx: index('preseason_pick_season_category_idx').on(t.seasonYear, t.category)
}))

export const preseasonPickStandingsDriver = pgTable('preseason_pick_standings_driver', {
  userId: uuid('user_id').notNull().references(() => user.id, { onDelete: 'cascade' }),
  seasonYear: integer('season_year').notNull().references(() => season.year, { onDelete: 'cascade' }),
  position: integer('position').notNull(),
  driverCode: text('driver_code').notNull().references(() => driver.code)
}, (t) => ({
  pk: primaryKey({ columns: [t.userId, t.seasonYear, t.position] }),
  driverUq: uniqueIndex('preseason_psd_driver_uq').on(t.userId, t.seasonYear, t.driverCode),
  seasonIdx: index('preseason_psd_season_idx').on(t.seasonYear)
}))

export const preseasonPickStandingsConstructor = pgTable('preseason_pick_standings_constructor', {
  userId: uuid('user_id').notNull().references(() => user.id, { onDelete: 'cascade' }),
  seasonYear: integer('season_year').notNull().references(() => season.year, { onDelete: 'cascade' }),
  position: integer('position').notNull(),
  constructorId: text('constructor_id').notNull().references(() => constructor.id)
}, (t) => ({
  pk: primaryKey({ columns: [t.userId, t.seasonYear, t.position] }),
  constructorUq: uniqueIndex('preseason_psc_constructor_uq').on(t.userId, t.seasonYear, t.constructorId),
  seasonIdx: index('preseason_psc_season_idx').on(t.seasonYear)
}))

/// Snapshot of each user's projected preseason points after a given race.
/// Populated by rescorePreseasonForSeason once at the end of every preseason
/// rescore, keyed by the most recent finished race session id. Used to
/// compute "projection delta since last weekend" without recomputing
/// historical standings on the fly.
export const preseasonProjectionSnapshot = pgTable('preseason_projection_snapshot', {
  userId: uuid('user_id').notNull().references(() => user.id, { onDelete: 'cascade' }),
  seasonYear: integer('season_year').notNull().references(() => season.year, { onDelete: 'cascade' }),
  afterSessionId: integer('after_session_id').notNull().references(() => session.id, { onDelete: 'cascade' }),
  projectedPoints: integer('projected_points').notNull(),
  computedAt: timestamp('computed_at', { withTimezone: true }).notNull().defaultNow()
}, (t) => ({
  pk: primaryKey({ columns: [t.userId, t.seasonYear, t.afterSessionId] }),
  userSeasonIdx: index('preseason_proj_snapshot_user_season_idx').on(t.userId, t.seasonYear)
}))

/// Best lap (with sector durations) per driver per session. Sourced from
/// OpenF1 /laps once a session is marked finished. Backs the predict-screen
/// sector-color reference view.
///
/// Durations are stored in milliseconds (integer) so:
///   - we can compare/aggregate without floating-point quirks,
///   - we can compute session-best and personal-best sectors without
///     re-parsing formatted strings.
///
/// `pitOutLap` is excluded at parse time, so any row that lands here is a
/// real flying lap.
export const sessionBestLap = pgTable('session_best_lap', {
  sessionId: integer('session_id').notNull().references(() => session.id, { onDelete: 'cascade' }),
  driverCode: text('driver_code').notNull().references(() => driver.code),
  /// 1/2/3 for qualifying knockout segments (Q1/Q2/Q3 or SQ1/SQ2/SQ3).
  /// 0 for non-knockout sessions (FP/race/sprint). Always non-null so it can
  /// participate in the primary key — using 0 instead of nullable avoids
  /// PostgreSQL's "nulls are distinct" PK semantics.
  knockout: integer('knockout').notNull().default(0),
  lapMs: integer('lap_ms').notNull(),
  s1Ms: integer('s1_ms'),
  s2Ms: integer('s2_ms'),
  s3Ms: integer('s3_ms'),
  lapNumber: integer('lap_number'),
  computedAt: timestamp('computed_at', { withTimezone: true }).notNull().defaultNow()
}, (t) => ({
  pk: primaryKey({ columns: [t.sessionId, t.driverCode, t.knockout] }),
  sessionIdx: index('session_best_lap_session_idx').on(t.sessionId)
}))

/// F1 circuit metadata + SVG layouts sourced from julesr0y/f1-circuits-svg.
/// We mirror upstream's `circuits.json` (id, name, country, lat/lng) and
/// store the SVG variants in `circuit_svg`.
///
/// `currentLayoutId` points to the layout used in the most recent season —
/// the value the public endpoint defaults to when the caller doesn't
/// specify one. Populated by the crawler from upstream's "seasons" field.
export const circuit = pgTable('circuit', {
  id: text('id').primaryKey(),
  name: text('name').notNull(),
  countryId: text('country_id'),
  latitude: doublePrecision('latitude'),
  longitude: doublePrecision('longitude'),
  currentLayoutId: text('current_layout_id'),
  fetchedAt: timestamp('fetched_at', { withTimezone: true }).notNull().defaultNow()
})

/// One row per (circuit_id, layout_id, detail, variant). 8 SVGs per layout
/// upstream — we crawl all of them so the client can pick the right style.
///   detail   ∈ 'detailed' | 'minimal'
///   variant  ∈ 'black' | 'white' | 'black-outline' | 'white-outline'
export const circuitSvg = pgTable('circuit_svg', {
  circuitId: text('circuit_id').notNull().references(() => circuit.id, { onDelete: 'cascade' }),
  layoutId: text('layout_id').notNull(),
  detail: text('detail').notNull(),
  variant: text('variant').notNull(),
  svg: text('svg').notNull(),
  fetchedAt: timestamp('fetched_at', { withTimezone: true }).notNull().defaultNow()
}, (t) => ({
  pk: primaryKey({ columns: [t.circuitId, t.layoutId, t.detail, t.variant] }),
  layoutIdx: index('circuit_svg_layout_idx').on(t.layoutId)
}))

export const subjectiveTruth = pgTable('subjective_truth', {
  seasonYear: integer('season_year').primaryKey().references(() => season.year, { onDelete: 'cascade' }),
  surpriseDriverCode: text('surprise_driver_code').references(() => driver.code),
  surpriseConstructorId: text('surprise_constructor_id').references(() => constructor.id),
  disappointmentDriverCode: text('disappointment_driver_code').references(() => driver.code),
  disappointmentConstructorId: text('disappointment_constructor_id').references(() => constructor.id),
  setAt: timestamp('set_at', { withTimezone: true }).notNull().defaultNow()
})

// ---- notifications ---------------------------------------------------------

export const notifyPlatform = pgEnum('notify_platform', ['ios', 'android'])

/// One FCM registration token per device, owned by a user. Tokens rotate, so
/// the dispatcher prunes dead ones by setting [disabledAt] when FCM reports a
/// token as unregistered. [timezone] is the device's IANA zone, used to gate
/// quiet hours when the server fires reminders.
export const deviceToken = pgTable('device_token', {
  id: uuid('id').primaryKey().defaultRandom(),
  userId: uuid('user_id').notNull().references(() => user.id, { onDelete: 'cascade' }),
  token: text('token').notNull(),
  platform: notifyPlatform('platform').notNull(),
  timezone: text('timezone'),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  lastSeenAt: timestamp('last_seen_at', { withTimezone: true }).notNull().defaultNow(),
  disabledAt: timestamp('disabled_at', { withTimezone: true })
}, (t) => ({
  tokenUq: uniqueIndex('device_token_token_uq').on(t.token),
  userIdx: index('device_token_user_idx').on(t.userId)
}))

/// Per-user notification preferences. The server home of what used to live in
/// the app's SharedPreferences. Defaults match the app's prior local defaults:
/// reminders on, quiet hours off, 22:00–08:00 window (minutes since midnight).
export const notificationPref = pgTable('notification_pref', {
  userId: uuid('user_id').primaryKey().references(() => user.id, { onDelete: 'cascade' }),
  enabled: boolean('enabled').notNull().default(true),
  quietEnabled: boolean('quiet_enabled').notNull().default(false),
  quietStartMin: integer('quiet_start_min').notNull().default(1320),
  quietEndMin: integer('quiet_end_min').notNull().default(480),
  timezone: text('timezone'),
  updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow()
})

/// Idempotency ledger. The every-minute dispatcher claims a [dedupeKey] (insert
/// on-conflict-do-nothing) before sending, so a notification fires exactly once
/// even across cron re-ticks and crashes. Shape: `${kind}:${sessionId}:${userId}`.
export const notificationLog = pgTable('notification_log', {
  id: uuid('id').primaryKey().defaultRandom(),
  dedupeKey: text('dedupe_key').notNull(),
  userId: uuid('user_id').notNull().references(() => user.id, { onDelete: 'cascade' }),
  kind: text('kind').notNull(),
  sessionId: integer('session_id').references(() => session.id, { onDelete: 'cascade' }),
  sentAt: timestamp('sent_at', { withTimezone: true }).notNull().defaultNow()
}, (t) => ({
  dedupeUq: uniqueIndex('notification_log_dedupe_uq').on(t.dedupeKey),
  userIdx: index('notification_log_user_idx').on(t.userId)
}))
