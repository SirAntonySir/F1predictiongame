/// Public circuit endpoints — list + SVG fetch.
///
///   GET /api/circuits                              -- metadata for all known
///   GET /api/circuits/:id                          -- one circuit's metadata
///   GET /api/circuits/:id/svg?layout=&detail=&variant=
///       returns raw SVG (content-type image/svg+xml). Defaults to the
///       circuit's currentLayoutId, detail=detailed, variant=white.
import type { FastifyInstance } from 'fastify'
import { ApiError } from '../errors.js'
import * as circuitsRepo from '../../repo/circuits.js'

const DEFAULT_DETAIL = 'detailed'
const DEFAULT_VARIANT = 'white'

export async function registerCircuitRoutes(app: FastifyInstance): Promise<void> {
  app.get('/api/circuits', async () => circuitsRepo.listAll())

  app.get<{ Params: { id: string } }>('/api/circuits/:id', async (req) => {
    const c = await circuitsRepo.getById(req.params.id)
    if (!c) throw new ApiError('NOT_FOUND', `Circuit ${req.params.id} not found`)
    return c
  })

  app.get<{
    Params: { id: string }
    Querystring: { layout?: string; detail?: string; variant?: string }
  }>('/api/circuits/:id/svg', async (req, reply) => {
    const c = await circuitsRepo.getById(req.params.id)
    if (!c) throw new ApiError('NOT_FOUND', `Circuit ${req.params.id} not found`)
    const layoutId = req.query.layout ?? c.currentLayoutId
    if (!layoutId) throw new ApiError('BAD_REQUEST', 'no layout specified and circuit has no currentLayoutId')
    const detail = req.query.detail ?? DEFAULT_DETAIL
    const variant = req.query.variant ?? DEFAULT_VARIANT
    const svg = await circuitsRepo.getSvg(c.id, layoutId, detail, variant)
    if (svg == null) {
      throw new ApiError('NOT_FOUND',
        `SVG not stored for ${c.id} · ${layoutId} · ${detail}/${variant}`)
    }
    reply.type('image/svg+xml')
    // SVGs are static — cache for an hour on intermediate proxies, a day
    // on the client, and let Render/CDN serve from cache.
    reply.header('Cache-Control', 'public, max-age=86400, s-maxage=3600')
    return svg
  })
}
