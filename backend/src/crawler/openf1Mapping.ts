import type { OpenF1Client } from '../openf1/client.js'
import { sessionNameFor } from '../openf1/parsers.js'
import * as sessionsRepo from '../repo/sessions.js'
import * as eventsRepo from '../repo/events.js'

type OpenF1Session = { session_key: number; session_name: string; date_start: string }

function utcDate(iso: string): string {
  return new Date(iso).toISOString().slice(0, 10) // YYYY-MM-DD
}

export async function mapSessionsToOpenF1(year: number, client: OpenF1Client): Promise<void> {
  const raw = await client.getSessions(year)
  if (!raw) return
  const openf1: OpenF1Session[] = raw as OpenF1Session[]

  const byKey = new Map<string, number>()
  for (const s of openf1) {
    byKey.set(`${utcDate(s.date_start)}|${s.session_name}`, s.session_key)
  }

  const events = await eventsRepo.listForSeason(year)
  for (const ev of events) {
    const local = await sessionsRepo.listForEvent(ev.id)
    for (const s of local) {
      const name = sessionNameFor(s.type)
      const k = `${utcDate(s.scheduledStart.toISOString())}|${name}`
      const key = byKey.get(k) ?? null
      if (key !== null) {
        await sessionsRepo.setOpenF1SessionKey(s.id!, key)
      } else {
        console.log('OpenF1 no-match for session', { eventId: ev.id, round: ev.round, type: s.type, date: k })
      }
    }
  }
}
