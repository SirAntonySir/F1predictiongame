import {
  pgTable, integer, text, boolean, timestamp, pgEnum, primaryKey, uniqueIndex
} from 'drizzle-orm/pg-core'

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
  uqEventType: uniqueIndex('session_event_type_uq').on(t.eventId, t.type)
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
