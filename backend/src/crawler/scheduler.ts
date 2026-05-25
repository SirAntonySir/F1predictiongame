import cron, { type ScheduledTask } from 'node-cron'
import { JolpicaClient } from '../jolpica/client.js'
import { WikipediaClient } from '../wikipedia/client.js'
import { runTick, type TickSummary } from './tick.js'
import { runBootstrap } from './bootstrap.js'
import * as seasonsRepo from '../repo/seasons.js'

export class Scheduler {
  private isRunningTick = false
  private isRunningWeekly = false
  private lastTickAt: Date | null = null
  private lastTickStatus: 'ok' | 'error' | null = null
  private tickJob: ScheduledTask | null = null
  private weeklyJob: ScheduledTask | null = null

  constructor(
    private jolpica = new JolpicaClient(),
    private wiki = new WikipediaClient()
  ) {}

  start(): void {
    // Every 15 minutes
    this.tickJob = cron.schedule('*/15 * * * *', () => { void this.tickOnce() })
    // Mondays 03:00 UTC
    this.weeklyJob = cron.schedule('0 3 * * 1', () => { void this.weeklyOnce() }, { timezone: 'UTC' })
  }

  stop(): void {
    this.tickJob?.stop()
    this.weeklyJob?.stop()
    this.tickJob = null
    this.weeklyJob = null
  }

  async tickOnce(): Promise<TickSummary | null> {
    if (this.isRunningTick) {
      console.log('Tick already running, skipping')
      return null
    }
    this.isRunningTick = true
    try {
      const summary = await runTick(this.jolpica, this.wiki)
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
      await runBootstrap(this.jolpica, cur.year)
      console.log('Weekly schedule refresh complete')
    } catch (err) {
      console.error('Weekly refresh failed', err)
    } finally {
      this.isRunningWeekly = false
    }
  }

  status(): { lastTickAt: string | null; lastTickStatus: 'ok' | 'error' | null } {
    return {
      lastTickAt: this.lastTickAt?.toISOString() ?? null,
      lastTickStatus: this.lastTickStatus
    }
  }
}
