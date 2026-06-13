import type { JolpicaClient } from '../jolpica/client.js'
import type { WikipediaClient } from '../wikipedia/client.js'
import {
  parseRaceResults, parseQualifyingResults, parseSprintResults,
  extractDriversFromResults, extractConstructorsFromResults
} from '../jolpica/parsers.js'
import { upsertNewDrivers, upsertNewConstructors } from './tick.js'
import * as resultsRepo from '../repo/results.js'
import * as sessionsRepo from '../repo/sessions.js'
import { compareClassifications } from './crossCheck.js'
import { rescoreSession } from '../scoring/rescorer.js'
import { getDb } from '../db/client.js'
import { sql } from 'drizzle-orm'
import type { SessionResultRow, SessionType } from '../domain/types.js'

export type ReconcileSummary = {
  /// Provisional OpenF1-sourced sessions we attempted to reconcile this pass.
  attempted: number
  /// Reconciled and confirmed identical — rows untouched, timestamp stamped.
  matched: number
  /// Reconciled and rows replaced with Jolpica's classification — rescored.
  replaced: number
  /// Jolpica didn't have data yet — left as 'openf1', will retry next pass.
  noJolpicaData: number
  /// Errors during reconcile — left in current state to retry.
  errors: number
}

type ReconcileCandidate = {
  sessionId: number
  type: SessionType
  seasonYear: number
  round: number
}

/// Pulls the set of sessions that still need reconciliation. A session is
/// reconcilable when:
/// - it's finished
/// - it has at least one session_result row sourced from OpenF1
///   (jolpica-sourced rows are already official)
/// - either never reconciled, or last reconciled > 24 h ago
/// - scheduled within the last 7 days — outside that window we give up on
///   reconciliation and accept the OpenF1 classification as final, since
///   Jolpica is highly unlikely to publish more than a week late and the
///   reconciliation has run dozens of times already.
async function listReconcilable(): Promise<ReconcileCandidate[]> {
  const db = getDb()
  const rows = await db.execute(sql`
    SELECT
      ses.id           AS "sessionId",
      ses.type         AS "type",
      ev.season_year   AS "seasonYear",
      ev.round         AS "round"
    FROM session ses
    JOIN event ev ON ev.id = ses.event_id
    WHERE ses.status = 'finished'
      AND ses.scheduled_start > now() - interval '7 days'
      AND (ses.last_reconciled_at IS NULL OR ses.last_reconciled_at < now() - interval '24 hours')
      AND EXISTS (
        SELECT 1 FROM session_result sr
        WHERE sr.session_id = ses.id AND sr.source = 'openf1'
      )
    ORDER BY ses.scheduled_start DESC
  `)
  return (rows as unknown as { rows: ReconcileCandidate[] }).rows
}

async function fetchJolpicaRowsForType(
  jolpica: JolpicaClient,
  type: SessionType,
  year: number,
  round: number
): Promise<{ rows: SessionResultRow[]; raw: unknown } | null> {
  switch (type) {
    case 'race': {
      const raw = await jolpica.getRaceResults(year, round)
      if (!raw) return null
      return { rows: parseRaceResults(raw), raw }
    }
    case 'qualifying': {
      const raw = await jolpica.getQualifyingResults(year, round)
      if (!raw) return null
      return { rows: parseQualifyingResults(raw), raw }
    }
    case 'sprint': {
      const raw = await jolpica.getSprintResults(year, round)
      if (!raw) return null
      return { rows: parseSprintResults(raw), raw }
    }
    // Jolpica doesn't publish FP/sprint_quali — these sessions are OpenF1-only
    // and have no Jolpica side to reconcile against, so they're treated as
    // final at the moment they're written. They never appear in listReconcilable
    // (no Jolpica side means nothing to swap to), but guard anyway.
    case 'sprint_quali':
    case 'fp1':
    case 'fp2':
    case 'fp3':
      return null
  }
}

export async function reconcileOnce(
  jolpica: JolpicaClient,
  wiki: WikipediaClient
): Promise<ReconcileSummary> {
  const summary: ReconcileSummary = {
    attempted: 0, matched: 0, replaced: 0, noJolpicaData: 0, errors: 0
  }
  const candidates = await listReconcilable()
  for (const c of candidates) {
    summary.attempted++
    try {
      const fetched = await fetchJolpicaRowsForType(jolpica, c.type, c.seasonYear, c.round)
      if (!fetched || fetched.rows.length === 0) {
        summary.noJolpicaData++
        continue
      }
      const current = await resultsRepo.listForSession(c.sessionId)
      const cmp = compareClassifications(fetched.rows, current)
      if (cmp.kind === 'match') {
        await sessionsRepo.setLastReconciledAt(c.sessionId, new Date())
        summary.matched++
        continue
      }
      // Divergence — Jolpica's classification wins. Upsert any new
      // drivers/constructors Jolpica introduced (the OpenF1 path may have
      // used aliased ids), then swap the rows in and rescore.
      await upsertNewDrivers(extractDriversFromResults(fetched.raw), wiki)
      await upsertNewConstructors(extractConstructorsFromResults(fetched.raw), wiki)
      await resultsRepo.replaceForSession(
        c.sessionId,
        fetched.rows.map((r) => ({ ...r, sessionId: c.sessionId })),
        'jolpica'
      )
      await sessionsRepo.setLastReconciledAt(c.sessionId, new Date())
      try {
        const rescore = await rescoreSession(c.sessionId)
        console.log('Reconciled + rescored session', { sessionId: c.sessionId, ...rescore })
      } catch (err) {
        console.error('Reconcile rescore failed (rows replaced)', { sessionId: c.sessionId, err })
      }
      summary.replaced++
    } catch (err) {
      summary.errors++
      console.error('Reconcile error for session', c.sessionId, err)
    }
  }
  return summary
}
