import type { FastifyReply } from 'fastify'

export type ApiErrorCode =
  | 'NOT_FOUND'
  | 'UPSTREAM_FAILURE'
  | 'BAD_REQUEST'
  | 'UNAUTHORIZED'
  | 'FORBIDDEN'
  | 'CONFLICT'
  | 'VALIDATION'
  | 'INTERNAL'

const STATUS: Record<ApiErrorCode, number> = {
  NOT_FOUND: 404,
  UPSTREAM_FAILURE: 502,
  BAD_REQUEST: 400,
  UNAUTHORIZED: 401,
  FORBIDDEN: 403,
  CONFLICT: 409,
  VALIDATION: 422,
  INTERNAL: 500
}

export class ApiError extends Error {
  constructor(public code: ApiErrorCode, message: string) {
    super(message)
  }
}

export function sendError(reply: FastifyReply, err: unknown): void {
  if (err instanceof ApiError) {
    reply.status(STATUS[err.code]).send({ error: { code: err.code, message: err.message } })
    return
  }
  reply.status(500).send({ error: { code: 'INTERNAL', message: 'Internal server error' } })
}
