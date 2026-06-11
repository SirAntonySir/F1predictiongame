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

  // Default true (the live current-season refresh). Pass false to pre-load a
  // future season's calendar without stealing "current" from the active one.
  await seasonsRepo.upsertSeason({ year: schedule.year, isCurrent: opts.isCurrent ?? true })

  for (const ev of schedule.events) {
    const stored = await eventsRepo.upsertEvent({
      seasonYear: ev.seasonYear,
      round: ev.round,
      name: ev.name,
      circuitName: ev.circuitName,
      country: ev.country,
      hasSprint: ev.hasSprint
    })
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
  }

  if (openf1) {
    try {
      await mapSessionsToOpenF1(year, openf1)
    } catch (err) {
      console.error('OpenF1 mapping failed (bootstrap continues)', err)
    }
  }
}
