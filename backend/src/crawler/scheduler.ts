import cron, { type ScheduledTask } from 'node-cron'
import { JolpicaClient } from '../jolpica/client.js'
import { WikipediaClient } from '../wikipedia/client.js'
import { OpenF1Client } from '../openf1/client.js'
import { runTick, type TickSummary } from './tick.js'
import { runBootstrap } from './bootstrap.js'
import * as seasonsRepo from '../repo/seasons.js'
import { sweepExpiredSessions } from '../auth/sweeper.js'

export class Scheduler {
  private isRunningTick = false
  private isRunningWeekly = false
  private lastTickAt: Date | null = null
  private lastTickStatus: 'ok' | 'error' | null = null
  private tickJob: ScheduledTask | null = null
  private weeklyJob: ScheduledTask | null = null
  private sweepJob: ScheduledTask | null = null

  constructor(
    private jolpica = new JolpicaClient(),
    private wiki = new WikipediaClient(),
    private openf1 = new OpenF1Client()
  ) {}

  start(): void {
    // Every 5 minutes — keeps post-race result ingestion/scoring snappy
    // (results land within ~5 min of a session becoming eligible).
    this.tickJob = cron.schedule('*/5 * * * *', () => { void this.tickOnce() })
    // Mondays 03:00 UTC
    this.weeklyJob = cron.schedule('0 3 * * 1', () => { void this.weeklyOnce() }, { timezone: 'UTC' })
    // Daily 04:00 UTC — delete expired sessions
    this.sweepJob = cron.schedule('0 4 * * *', () => { void this.sweepOnce() }, { timezone: 'UTC' })
  }

  stop(): void {
    this.tickJob?.stop()
    this.weeklyJob?.stop()
    this.tickJob = null
    this.weeklyJob = null
    this.sweepJob?.stop()
    this.sweepJob = null
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
