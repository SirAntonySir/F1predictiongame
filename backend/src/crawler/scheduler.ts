import cron, { type ScheduledTask } from 'node-cron'
import { JolpicaClient } from '../jolpica/client.js'
import { WikipediaClient } from '../wikipedia/client.js'
import { OpenF1Client } from '../openf1/client.js'
import { runTick, type TickSummary } from './tick.js'
import { reconcileOnce, type ReconcileSummary } from './reconcile.js'
import { runBootstrap } from './bootstrap.js'
import * as seasonsRepo from '../repo/seasons.js'
import { sweepExpiredSessions } from '../auth/sweeper.js'
import { runNotificationsTick } from '../notifications/dispatcher.js'
import { createSender, resolveMessaging } from '../notifications/sender.js'

export class Scheduler {
  private isRunningTick = false
  private isRunningWeekly = false
  private isRunningReconcile = false
  private isRunningNotify = false
  private lastTickAt: Date | null = null
  private lastTickStatus: 'ok' | 'error' | null = null
  private tickJob: ScheduledTask | null = null
  private weeklyJob: ScheduledTask | null = null
  private sweepJob: ScheduledTask | null = null
  private reconcileJob: ScheduledTask | null = null
  private notifyJob: ScheduledTask | null = null

  constructor(
    private jolpica = new JolpicaClient(),
    private wiki = new WikipediaClient(),
    private openf1 = new OpenF1Client()
  ) {}

  start(): void {
    // Every minute — OpenF1 publishes session results within minutes of the
    // chequered flag, and the tick early-returns when nothing is eligible,
    // so the polling rate is cheap. Jolpica is only hit for sessions that
    // OpenF1 doesn't cover (older seasons) or hasn't published yet — a
    // narrow window in practice, since OpenF1 leads Jolpica by a lot.
    this.tickJob = cron.schedule('* * * * *', () => { void this.tickOnce() })
    // Mondays 03:00 UTC
    this.weeklyJob = cron.schedule('0 3 * * 1', () => { void this.weeklyOnce() }, { timezone: 'UTC' })
    // Daily 04:00 UTC — delete expired sessions
    this.sweepJob = cron.schedule('0 4 * * *', () => { void this.sweepOnce() }, { timezone: 'UTC' })
    // Hourly at :15 — fetch Jolpica's official classification for any session
    // whose results are still OpenF1-sourced, and replace + rescore if they
    // diverge (penalties, DSQ, post-stewards reclassification).
    this.reconcileJob = cron.schedule('15 * * * *', () => { void this.reconcileOnce() })
    // Every minute — evaluate notification triggers (pick reminders, session
    // live, results in). Cheap: early-returns when no devices are registered,
    // and the claim ledger makes re-ticks idempotent.
    this.notifyJob = cron.schedule('* * * * *', () => { void this.notifyOnce() })
  }

  stop(): void {
    this.tickJob?.stop()
    this.weeklyJob?.stop()
    this.tickJob = null
    this.weeklyJob = null
    this.sweepJob?.stop()
    this.sweepJob = null
    this.reconcileJob?.stop()
    this.reconcileJob = null
    this.notifyJob?.stop()
    this.notifyJob = null
  }

  /// Evaluate notification triggers and dispatch. Guarded against overlap.
  /// When no Firebase service account is configured, [resolveMessaging] returns
  /// null and we skip sending (without claiming anything), so enabling FCM
  /// later doesn't start by replaying a backlog.
  async notifyOnce(): Promise<{ sent: number } | null> {
    if (this.isRunningNotify) return null
    this.isRunningNotify = true
    try {
      const messaging = await resolveMessaging()
      if (!messaging) return { sent: 0 }
      const sender = createSender(messaging)
      const summary = await runNotificationsTick(new Date(), sender.sendToUser)
      if (summary.sent > 0) console.log('Notifications dispatched', summary)
      return summary
    } catch (err) {
      console.error('Notifications tick failed', err)
      return null
    } finally {
      this.isRunningNotify = false
    }
  }

  async tickOnce(): Promise<TickSummary | null> {
    if (this.isRunningTick) {
      console.log('Tick already running, skipping')
      return null
    }
    this.isRunningTick = true
    try {
      const summary = await runTick(this.jolpica, this.wiki, this.openf1)
      this.lastTickAt = new Date()
      this.lastTickStatus = 'ok'
      console.log('Tick complete', summary)
      return summary
    } catch (err) {
      this.lastTickStatus = 'error'
      console.error('Tick failed', err)
      return null
    } finally {
      this.isRunningTick = false
    }
  }

  /// One-shot tick targeting a single session. Intended for external triggers
  /// — e.g. an admin endpoint or a future frontend FINALISED webhook — that
  /// know a specific session just produced its classification and want it
  /// crawled and scored without waiting for the next cron tick. Bypasses the
  /// eligibility window (scheduledEnd cutoff) so the caller can force a
  /// refresh as soon as upstream data is available.
  async tickForSession(sessionId: number): Promise<TickSummary | null> {
    try {
      const summary = await runTick(this.jolpica, this.wiki, this.openf1, { sessionId })
      console.log('TickForSession complete', { sessionId, ...summary })
      return summary
    } catch (err) {
      console.error('TickForSession failed', { sessionId, err })
      return null
    }
  }

  async reconcileOnce(): Promise<ReconcileSummary | null> {
    if (this.isRunningReconcile) {
      console.log('Reconcile already running, skipping')
      return null
    }
    this.isRunningReconcile = true
    try {
      const summary = await reconcileOnce(this.jolpica, this.wiki)
      console.log('Reconcile complete', summary)
      return summary
    } catch (err) {
      console.error('Reconcile failed', err)
      return null
    } finally {
      this.isRunningReconcile = false
    }
  }

  async weeklyOnce(): Promise<void> {
    if (this.isRunningWeekly) return
    this.isRunningWeekly = true
    try {
      const cur = await seasonsRepo.getCurrent()
      if (!cur) return
      await runBootstrap(this.jolpica, cur.year, this.openf1)
      console.log('Weekly schedule refresh complete')
      // Pre-load next season's calendar (non-current) the moment F1 publishes
      // it, so a new year is ready for an admin to activate. Probe first so an
      // unpublished year is a clean no-op rather than an error.
      const next = cur.year + 1
      try {
        if (await this.jolpica.getSeasonSchedule(next)) {
          await runBootstrap(this.jolpica, next, this.openf1, { isCurrent: false })
          console.log(`Pre-loaded next season ${next} (non-current)`)
        }
      } catch (err) {
        console.error(`Next-season pre-load failed (${next})`, err)
      }
    } catch (err) {
      console.error('Weekly refresh failed', err)
    } finally {
      this.isRunningWeekly = false
    }
  }

  async sweepOnce(): Promise<void> {
    try {
      const removed = await sweepExpiredSessions()
      console.log('Session sweep complete', { removed })
    } catch (err) {
      console.error('Session sweep failed', err)
    }
  }

  status(): { lastTickAt: string | null; lastTickStatus: 'ok' | 'error' | null } {
    return {
      lastTickAt: this.lastTickAt?.toISOString() ?? null,
      lastTickStatus: this.lastTickStatus
    }
  }
}
