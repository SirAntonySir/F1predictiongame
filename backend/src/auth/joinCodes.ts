import { randomInt } from 'node:crypto'

const ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
// 8 chars × 36-char alphabet → ~2.8 trillion combinations, effectively
// collision-free at any plausible league count. DB unique index is still
// the source of truth, this just keeps retries from ever firing.
const LEN = 8
const MAX_ATTEMPTS = 10

export function generateJoinCode(): string {
  let out = ''
  for (let i = 0; i < LEN; i++) {
    out += ALPHABET[randomInt(0, ALPHABET.length)]
  }
  return out
}

export async function generateUniqueJoinCode(
  isTaken: (code: string) => Promise<boolean>
): Promise<string> {
  for (let i = 0; i < MAX_ATTEMPTS; i++) {
    const c = generateJoinCode()
    if (!(await isTaken(c))) return c
  }
  throw new Error('Could not generate a unique join code after ' + MAX_ATTEMPTS + ' attempts')
}
