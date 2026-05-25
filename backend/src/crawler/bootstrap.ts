import { JolpicaClient } from '../jolpica/client.js'
import { parseSchedule } from '../jolpica/parsers.js'
import * as seasonsRepo from '../repo/seasons.js'
import * as eventsRepo from '../repo/events.js'
import * as sessionsRepo from '../repo/sessions.js'

export async function runBootstrap(client: JolpicaClient, year: number): Promise<void> {
  const raw = await client.getSeasonSchedule(year)
  if (!raw) throw new Error(`Jolpica returned null for season ${year}`)
  const schedule = parseSchedule(raw)

  await seasonsRepo.upsertSeason({ year: schedule.year, isCurrent: true })

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
        status: 'scheduled'
      })
    }
  }
}
