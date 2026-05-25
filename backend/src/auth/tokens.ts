import { randomBytes, createHash } from 'node:crypto'

export function generateToken(): string {
  return randomBytes(32).toString('base64url')
}

export function hashToken(token: string): Buffer {
  return createHash('sha256').update(token).digest()
}
