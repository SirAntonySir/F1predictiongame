const TOKEN_KEY = 'f1pg_admin_token'
const BASE_URL = import.meta.env.VITE_API_URL ?? 'http://localhost:3000'

let onUnauthorized: (() => void) | null = null
export function setUnauthorizedHandler(fn: (() => void) | null): void {
  onUnauthorized = fn
}

export function getToken(): string | null {
  return localStorage.getItem(TOKEN_KEY)
}
export function setToken(token: string): void {
  localStorage.setItem(TOKEN_KEY, token)
}
export function clearToken(): void {
  localStorage.removeItem(TOKEN_KEY)
}

export class ApiError extends Error {
  status: number
  code: string
  constructor(status: number, code: string, message: string) {
    super(message)
    this.name = 'ApiError'
    this.status = status
    this.code = code
  }
}

type FetchOpts = { method?: string; body?: unknown; token?: string }

export async function apiFetch<T>(path: string, opts: FetchOpts = {}): Promise<T> {
  const token = opts.token ?? getToken()
  const headers: Record<string, string> = {}
  if (token) headers['X-Admin-Token'] = token
  if (opts.body !== undefined) headers['Content-Type'] = 'application/json'

  const res = await fetch(`${BASE_URL}${path}`, {
    method: opts.method ?? 'GET',
    headers,
    body: opts.body !== undefined ? JSON.stringify(opts.body) : undefined
  })

  if (!res.ok) {
    if (res.status === 401 && opts.token === undefined) onUnauthorized?.()
    let code = 'ERROR'
    let message = `Request failed (${res.status})`
    try {
      const data = await res.json()
      if (data?.error) { code = data.error.code ?? code; message = data.error.message ?? message }
    } catch {
      // non-JSON error body; keep defaults
    }
    throw new ApiError(res.status, code, message)
  }

  if (res.status === 204) return undefined as T
  return (await res.json()) as T
}
