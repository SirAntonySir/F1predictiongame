import {
  pgTable, integer, text, boolean, timestamp, pgEnum, primaryKey, uniqueIndex, index, uuid, customType
} from 'drizzle-orm/pg-core'

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
  status: sessionStatus('status').notNull().default('scheduled')
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
  imageUrlOverride: text('image_url_override')
})

export const constructor = pgTable('constructor', {
  id: text('id').primaryKey(),
  name: text('name').notNull(),
  nationality: text('nationality'),
  wikipediaUrl: text('wikipedia_url'),
  imageUrl: text('image_url'),
  imageUrlOverride: text('image_url_override')
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
  q3: text('q3')
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
