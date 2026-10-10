import { JolpicaClient } from '../jolpica/client.js'
import { OpenF1Client } from '../openf1/client.js'
import { parseSchedule } from '../jolpica/parsers.js'
import * as seasonsRepo from '../repo/seasons.js'
import * as eventsRepo from '../repo/events.js'
import * as sessionsRepo from '../repo/sessions.js'
import { mapSessionsToOpenF1 } from './openf1Mapping.js'

export async function runBootstrap(
  client: JolpicaClient,
  year: number,
  openf1?: OpenF1Client,
  opts: { isCurrent?: boolean } = {}
): Promise<void> {
  const raw = await client.getSeasonSchedule(year)
  if (!raw) throw new Error(`Jolpica returned null for season ${year}`)
  const schedule = parseSchedule(raw)
  // Events missing from the schedule get deleted, so a cut-short response
  // must never be synced.
  if (schedule.events.length === 0 || schedule.events.length < schedule.total) {
    throw new Error(`Jolpica schedule for ${year} looks truncated (${schedule.events.length} of ${schedule.total} races)`)
  }

  // Default true (the live current-season refresh). Pass false to pre-load a
  // future season's calendar without stealing "current" from the active one.
  await seasonsRepo.upsertSeason({ year: schedule.year, isCurrent: opts.isCurrent ?? true })

  const synced = await eventsRepo.syncSeasonEvents(schedule.year, schedule.events.map((ev) => ({
    seasonYear: ev.seasonYear,
    round: ev.round,
    name: ev.name,
    circuitName: ev.circuitName,
    country: ev.country,
    hasSprint: ev.hasSprint
  })))
  for (const e of synced.removed) {
    console.warn('Removed event no longer on schedule', { year, round: e.round, name: e.name })
  }
  for (const e of synced.parked) {
    console.warn('Event left the schedule after it ran — parked', { year, round: e.round, name: e.name })
  }

  for (const ev of schedule.events) {
    const stored = synced.byRound.get(ev.round)!
    for (const s of ev.sessions) {
      await sessionsRepo.upsertSession({
        eventId: stored.id,
        type: s.type,
        scheduledStart: s.scheduledStart,
        scheduledEnd: s.scheduledEnd,
        status: 'scheduled',
        openf1SessionKey: null
      })
    }
    // Upserts never remove a session that dropped off the calendar (e.g. a
    // sprint weekend reworked into a regular one), which would leave a
    // pickable ghost sprint behind. Only prune against a plausible weekend so
    // a truncated schedule response can't wipe one.
    if (ev.sessions.some((s) => s.type === 'race')) {
      const pruned = await sessionsRepo.pruneStaleForEvent(stored.id, ev.sessions.map((s) => s.type))
      for (const p of pruned) {
        console.warn('Pruned session no longer on schedule', { year, round: ev.round, sessionId: p.id, type: p.type })
      }
    }
  }

  if (openf1) {
    try {
      await mapSessionsToOpenF1(year, openf1)
    } catch (err) {
      console.error('OpenF1 mapping failed (bootstrap continues)', err)
    }
  }
}
