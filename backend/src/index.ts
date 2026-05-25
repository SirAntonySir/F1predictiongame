import Fastify, { type FastifyInstance } from 'fastify'
import cors from '@fastify/cors'
import { config } from './config.js'
import { pingDb, _resetPoolForTests } from './db/client.js'
import { sendError, ApiError } from './api/errors.js'
import { registerPublicRoutes } from './api/routes/public.js'
import { Scheduler } from './crawler/scheduler.js'

export type BuildAppOpts = { scheduler: Scheduler | null }

export async function buildApp(opts: BuildAppOpts): Promise<FastifyInstance> {
  const app = Fastify({
    logger: { level: config.nodeEnv === 'test' ? 'silent' : 'info' }
  })

  await app.register(cors, { origin: true })

  await registerPublicRoutes(app)

  app.get('/api/health', async (_req, reply) => {
    const db = (await pingDb()) ? 'up' : 'down'
    const sched = opts.scheduler?.status() ?? { lastTickAt: null, lastTickStatus: null }
    reply.send({ ok: true, db, ...sched })
  })

  app.setErrorHandler((err, _req, reply) => {
    sendError(reply, err)
  })

  app.setNotFoundHandler((_req, reply) => {
    sendError(reply, new ApiError('NOT_FOUND', 'Not found'))
  })

  return app
}

async function main() {
  const scheduler = new Scheduler()
  scheduler.start()
  const app = await buildApp({ scheduler })
  await app.listen({ port: config.port, host: '0.0.0.0' })

  const shutdown = async (sig: string) => {
    app.log.info({ sig }, 'shutting down')
    scheduler.stop()
    await app.close()
    await _resetPoolForTests()
    process.exit(0)
  }
  process.on('SIGTERM', () => void shutdown('SIGTERM'))
  process.on('SIGINT', () => void shutdown('SIGINT'))
}

const isEntry = process.argv[1]?.endsWith('index.js') || process.argv[1]?.endsWith('index.ts')
if (isEntry) {
  main().catch((err) => {
    console.error(err)
    process.exit(1)
  })
}
