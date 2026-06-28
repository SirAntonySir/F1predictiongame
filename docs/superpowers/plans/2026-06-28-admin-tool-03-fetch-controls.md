# Admin Tool — Plan 3: Fetch Control Center

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the admin Dashboard into a fetch control center — buttons that trigger the existing backend admin POST routes (bootstrap, crawl, refresh-images, refresh-openf1-metadata, circuits/sync), each with an async/pending state, a toast on success/failure, and automatic refresh of the crawl-status panel. Plus a stale-token recovery path: any `401` on a stored token clears it and drops back to the gate.

**Architecture:** Pure frontend, in `admin/` (all the trigger endpoints already exist on the backend — no backend changes). A dependency-free toast system (context + portal), an auth context that owns the gate's locked/unlocked state and a `signOut`, a one-line `401 → signOut` hook registered into the API client, a `useAdminAction` mutation hook, and an `ActionButton` that wires a route to a button. The Dashboard gains a "Fetch controls" panel of `ActionButton`s that invalidate `['crawl-status']` so the status cards refresh after a run.

**Tech Stack:** React 18, TypeScript, Radix Themes, TanStack Query v5, Vitest + React Testing Library + jsdom. No new dependencies.

## Global Constraints

- Files under `admin/` ONLY. Do not modify `backend/`, `lib/`, or anything outside `admin/`.
- **Concurrency:** another session may edit `backend/`/`lib/` and push `main`. NEVER `git add -A`/`git add .`/`git commit -a`. Stage only the exact `admin/...` paths each task names. Leave anything else unstaged.
- TypeScript strict; the build gate is `npm run build` (`tsc -b && vite build`). Tests: `npm test` (`vitest run`). Run from `admin/`.
- No new npm dependencies — the toast is custom (context + a fixed-position portal).
- Keep the app typography classes (`className="display"` / `className="label"`) on headings and labels — they apply Anton/Inter from `tokens.css`.
- Existing API surface (from Plan 2, do not change signatures): `apiFetch<T>(path, opts?: { method?; body?; token? })`, `ApiError { status, code }`, `getToken/setToken/clearToken`, `useCrawlStatus()`, `CrawlStatus`.
- Backend admin POST routes these buttons call (already deployed, token-gated): `POST /admin/bootstrap` → `{ ok, year }`; `POST /admin/crawl` → `{ ok, summary }`; `POST /admin/refresh-images` → `{ ok, driversAttempted, constructorsAttempted }`; `POST /admin/refresh-openf1-metadata` → `{ ok, driversUpdated, constructorsUpdated }`; `POST /admin/circuits/sync` → `{ ok, ... }`.

## File Structure

```
admin/src/
  ui/
    toast.tsx            # ToastProvider + useToast + viewport (custom, dependency-free)
  auth/
    AuthContext.tsx      # AuthProvider + useAuth (owns token state + signOut)
    TokenGate.tsx        # MODIFY: consume useAuth instead of local unlocked state
  api/
    client.ts            # MODIFY: setUnauthorizedHandler + call it on 401 (stored-token path)
    actions.ts           # useAdminAction mutation hook
  components/
    ActionButton.tsx     # async button: pending state + toast + query invalidation
    FetchControls.tsx    # the panel of trigger buttons
  pages/
    Dashboard.tsx        # MODIFY: render <FetchControls/>
  main.tsx               # MODIFY: nest ToastProvider + AuthProvider providers
  test/
    toast.test.tsx
    auth.test.tsx
    client_unauthorized.test.ts
    ActionButton.test.tsx
    FetchControls.test.tsx
```

---

### Task 1: Toast system (dependency-free)

**Files:**
- Create: `admin/src/ui/toast.tsx`, `admin/src/test/toast.test.tsx`

**Interfaces:**
- Produces:
  - `type ToastTone = 'ok' | 'error' | 'info'`
  - `<ToastProvider>{children}</ToastProvider>` — renders children plus a fixed bottom-right toast stack.
  - `useToast(): { show: (message: string, tone?: ToastTone) => void }` — adds a toast that auto-dismisses after 4000ms.

- [ ] **Step 1: Write the failing test**

`admin/src/test/toast.test.tsx`:
```tsx
import { describe, it, expect } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { ToastProvider, useToast } from '../ui/toast'

function Trigger() {
  const { show } = useToast()
  return <button onClick={() => show('Saved!', 'ok')}>fire</button>
}

describe('toast', () => {
  it('shows a toast message when triggered', async () => {
    render(
      <ToastProvider>
        <Trigger />
      </ToastProvider>
    )
    expect(screen.queryByText('Saved!')).not.toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'fire' }))
    expect(await screen.findByText('Saved!')).toBeInTheDocument()
  })

  it('throws if useToast is used outside the provider', () => {
    function Bad() { useToast(); return null }
    // React logs the error; assert the render throws.
    expect(() => render(<Bad />)).toThrow(/ToastProvider/)
  })
})
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd admin && npx vitest run src/test/toast.test.tsx`
Expected: FAIL — `../ui/toast` does not exist.

- [ ] **Step 3: Implement `admin/src/ui/toast.tsx`**

```tsx
import { createContext, useCallback, useContext, useRef, useState, type ReactNode } from 'react'
import { Box, Card, Flex, Text } from '@radix-ui/themes'

export type ToastTone = 'ok' | 'error' | 'info'
type Toast = { id: number; message: string; tone: ToastTone }

type ToastApi = { show: (message: string, tone?: ToastTone) => void }
const ToastContext = createContext<ToastApi | null>(null)

const TONE_COLOR: Record<ToastTone, string> = {
  ok: 'var(--ok)',
  error: 'var(--accent)',
  info: 'var(--on-surface-muted)'
}

export function ToastProvider({ children }: { children: ReactNode }) {
  const [toasts, setToasts] = useState<Toast[]>([])
  const nextId = useRef(1)

  const show = useCallback((message: string, tone: ToastTone = 'info') => {
    const id = nextId.current++
    setToasts((t) => [...t, { id, message, tone }])
    setTimeout(() => setToasts((t) => t.filter((x) => x.id !== id)), 4000)
  }, [])

  return (
    <ToastContext.Provider value={{ show }}>
      {children}
      <Box style={{ position: 'fixed', right: 16, bottom: 16, zIndex: 1000, maxWidth: 360 }}>
        <Flex direction="column" gap="2">
          {toasts.map((t) => (
            <Card key={t.id} size="2" style={{ borderLeft: `4px solid ${TONE_COLOR[t.tone]}` }}>
              <Text size="2">{t.message}</Text>
            </Card>
          ))}
        </Flex>
      </Box>
    </ToastContext.Provider>
  )
}

export function useToast(): ToastApi {
  const ctx = useContext(ToastContext)
  if (!ctx) throw new Error('useToast must be used within a ToastProvider')
  return ctx
}
```

> Note: the import line uses `useRef` (lowercase). The token `useRef` must match React's export — write `import { createContext, useCallback, useContext, useRef, useState, type ReactNode } from 'react'`.

- [ ] **Step 4: Run to verify it passes**

Run: `cd admin && npx vitest run src/test/toast.test.tsx`
Expected: PASS (2 tests). Then `cd admin && npm run build` → clean.

- [ ] **Step 5: Commit**

```bash
git add admin/src/ui/toast.tsx admin/src/test/toast.test.tsx
git commit -m "feat(admin-ui): dependency-free toast system"
```

---

### Task 2: Auth context + 401 recovery + TokenGate refactor

**Files:**
- Create: `admin/src/auth/AuthContext.tsx`, `admin/src/test/auth.test.tsx`, `admin/src/test/client_unauthorized.test.ts`
- Modify: `admin/src/api/client.ts`, `admin/src/auth/TokenGate.tsx`, `admin/src/main.tsx`

**Interfaces:**
- Consumes: `useToast` (Task 1), `getToken/setToken/clearToken`, `apiFetch`, `ApiError`.
- Produces:
  - `client.ts`: `setUnauthorizedHandler(fn: (() => void) | null): void`; `apiFetch` calls the handler on a `401` **only when `opts.token` was not supplied** (so the gate's candidate-token validation doesn't trigger a global sign-out).
  - `AuthContext.tsx`: `<AuthProvider>{children}</AuthProvider>`; `useAuth(): { token: string | null; signIn: (t: string) => void; signOut: () => void }`. On mount it registers `setUnauthorizedHandler(() => { signOut(); toast.show('Session expired — re-enter your token', 'error') })`; on unmount it clears the handler.
  - `TokenGate.tsx`: renders children when `useAuth().token !== null`; otherwise the token form, validating then calling `signIn(value)`.

- [ ] **Step 1: Write the failing tests**

`admin/src/test/client_unauthorized.test.ts`:
```ts
import { afterEach, describe, it, expect, vi } from 'vitest'
import { apiFetch, setUnauthorizedHandler, setToken } from '../api/client'

afterEach(() => { localStorage.clear(); setUnauthorizedHandler(null); vi.restoreAllMocks() })

describe('apiFetch 401 handling', () => {
  it('invokes the unauthorized handler on a 401 with a stored token', async () => {
    setToken('stale')
    const handler = vi.fn()
    setUnauthorizedHandler(handler)
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(
      new Response(JSON.stringify({ error: { code: 'UNAUTHORIZED', message: 'x' } }), { status: 401 })
    ))
    await expect(apiFetch('/admin/crawl/status')).rejects.toThrow()
    expect(handler).toHaveBeenCalledOnce()
  })

  it('does NOT invoke the handler when a candidate token was supplied (gate validation)', async () => {
    const handler = vi.fn()
    setUnauthorizedHandler(handler)
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(
      new Response(JSON.stringify({ error: { code: 'UNAUTHORIZED', message: 'x' } }), { status: 401 })
    ))
    await expect(apiFetch('/admin/crawl/status', { token: 'candidate' })).rejects.toThrow()
    expect(handler).not.toHaveBeenCalled()
  })
})
```

`admin/src/test/auth.test.tsx`:
```tsx
import { afterEach, describe, it, expect, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { ToastProvider } from '../ui/toast'
import { AuthProvider, useAuth } from '../auth/AuthContext'
import { setUnauthorizedHandler } from '../api/client'

afterEach(() => { localStorage.clear(); setUnauthorizedHandler(null); vi.restoreAllMocks() })

function Probe() {
  const { token, signIn, signOut } = useAuth()
  return (
    <div>
      <span data-testid="token">{token ?? 'none'}</span>
      <button onClick={() => signIn('abc')}>in</button>
      <button onClick={() => signOut()}>out</button>
    </div>
  )
}

function wrap(ui: React.ReactNode) {
  return <ToastProvider><AuthProvider>{ui}</AuthProvider></ToastProvider>
}

describe('AuthProvider', () => {
  it('signIn stores the token and signOut clears it', async () => {
    render(wrap(<Probe />))
    expect(screen.getByTestId('token')).toHaveTextContent('none')
    await userEvent.click(screen.getByRole('button', { name: 'in' }))
    expect(screen.getByTestId('token')).toHaveTextContent('abc')
    expect(localStorage.getItem('f1pg_admin_token')).toBe('abc')
    await userEvent.click(screen.getByRole('button', { name: 'out' }))
    expect(screen.getByTestId('token')).toHaveTextContent('none')
    expect(localStorage.getItem('f1pg_admin_token')).toBeNull()
  })
})
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd admin && npx vitest run src/test/client_unauthorized.test.ts src/test/auth.test.tsx`
Expected: FAIL — `setUnauthorizedHandler` and `../auth/AuthContext` do not exist.

- [ ] **Step 3: Modify `admin/src/api/client.ts`**

Add the handler registry near the top (after `BASE_URL`):
```ts
let onUnauthorized: (() => void) | null = null
export function setUnauthorizedHandler(fn: (() => void) | null): void {
  onUnauthorized = fn
}
```
Inside `apiFetch`, in the `if (!res.ok)` block, add as the FIRST line of that block:
```ts
    if (res.status === 401 && opts.token === undefined) onUnauthorized?.()
```
So the block becomes:
```ts
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
```

- [ ] **Step 4: Create `admin/src/auth/AuthContext.tsx`**

```tsx
import { createContext, useCallback, useContext, useEffect, useState, type ReactNode } from 'react'
import { getToken, setToken, clearToken, setUnauthorizedHandler } from '../api/client'
import { useToast } from '../ui/toast'

type AuthApi = {
  token: string | null
  signIn: (token: string) => void
  signOut: () => void
}
const AuthContext = createContext<AuthApi | null>(null)

export function AuthProvider({ children }: { children: ReactNode }) {
  const [token, setTokenState] = useState<string | null>(() => getToken())
  const { show } = useToast()

  const signIn = useCallback((t: string) => {
    setToken(t)
    setTokenState(t)
  }, [])

  const signOut = useCallback(() => {
    clearToken()
    setTokenState(null)
  }, [])

  useEffect(() => {
    setUnauthorizedHandler(() => {
      signOut()
      show('Session expired — re-enter your token', 'error')
    })
    return () => setUnauthorizedHandler(null)
  }, [signOut, show])

  return <AuthContext.Provider value={{ token, signIn, signOut }}>{children}</AuthContext.Provider>
}

export function useAuth(): AuthApi {
  const ctx = useContext(AuthContext)
  if (!ctx) throw new Error('useAuth must be used within an AuthProvider')
  return ctx
}
```

- [ ] **Step 5: Replace `admin/src/auth/TokenGate.tsx`** (full new contents)

```tsx
import { useState } from 'react'
import { Box, Button, Card, Flex, Heading, Text, TextField } from '@radix-ui/themes'
import { apiFetch, ApiError } from '../api/client'
import { useAuth } from './AuthContext'

export function TokenGate({ children }: { children: React.ReactNode }) {
  const { token, signIn } = useAuth()
  const [value, setValue] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  if (token !== null) return <>{children}</>

  async function submit(e: React.FormEvent) {
    e.preventDefault()
    setBusy(true)
    setError(null)
    try {
      // Validate by hitting a token-gated endpoint with the candidate token.
      await apiFetch('/admin/crawl/status', { token: value })
      signIn(value)
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Could not reach the backend')
    } finally {
      setBusy(false)
    }
  }

  return (
    <Flex align="center" justify="center" style={{ minHeight: '100vh' }}>
      <Card size="3" style={{ width: 360 }}>
        <form onSubmit={submit}>
          <Flex direction="column" gap="3">
            <Heading size="5" className="display">F1PG Admin</Heading>
            <Box>
              <Text as="label" htmlFor="admin-token" size="2" className="label">Admin token</Text>
              <TextField.Root
                id="admin-token"
                type="password"
                value={value}
                onChange={(e) => setValue(e.target.value)}
                placeholder="X-Admin-Token"
                mt="1"
              />
            </Box>
            {error && <Text size="2" color="red">{error}</Text>}
            <Button type="submit" disabled={busy || value.length === 0}>
              {busy ? 'Checking…' : 'Unlock'}
            </Button>
          </Flex>
        </form>
      </Card>
    </Flex>
  )
}
```

- [ ] **Step 6: Replace `admin/src/main.tsx`** (full new contents — adds ToastProvider + AuthProvider)

```tsx
import React from 'react'
import ReactDOM from 'react-dom/client'
import { Theme } from '@radix-ui/themes'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { RouterProvider } from 'react-router-dom'
import '@radix-ui/themes/styles.css'
import './theme/tokens.css'
import { ToastProvider } from './ui/toast'
import { AuthProvider } from './auth/AuthContext'
import { TokenGate } from './auth/TokenGate'
import { router } from './router'

const queryClient = new QueryClient()

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <Theme appearance="dark" accentColor="red" grayColor="gray" radius="medium">
      <ToastProvider>
        <AuthProvider>
          <QueryClientProvider client={queryClient}>
            <TokenGate>
              <RouterProvider router={router} />
            </TokenGate>
          </QueryClientProvider>
        </AuthProvider>
      </ToastProvider>
    </Theme>
  </React.StrictMode>
)
```

- [ ] **Step 7: Update the existing `TokenGate.test.tsx`** to wrap with the providers

The Plan-2 `admin/src/test/TokenGate.test.tsx` renders `<TokenGate>` directly; it now needs the Auth + Toast providers. Replace each `render(<TokenGate>…</TokenGate>)` with a wrapped render. At the top of the file add:
```tsx
import { ToastProvider } from '../ui/toast'
import { AuthProvider } from '../auth/AuthContext'

function renderGate(children: React.ReactNode) {
  return render(
    <ToastProvider>
      <AuthProvider>
        <TokenGate>{children}</TokenGate>
      </AuthProvider>
    </ToastProvider>
  )
}
```
Then change the three `render(<TokenGate><div>secret</div></TokenGate>)` calls to `renderGate(<div>secret</div>)`. Leave the assertions unchanged (they still hold: no token → form; valid token → children + localStorage set; invalid → error + no children + no localStorage). Also add `setUnauthorizedHandler(null)` to the existing `afterEach` cleanup (import it from `../api/client`) so a registered handler doesn't leak across tests.

- [ ] **Step 8: Run the tests + build**

Run: `cd admin && npx vitest run src/test/client_unauthorized.test.ts src/test/auth.test.tsx src/test/TokenGate.test.tsx`
Expected: PASS (2 + 1 + 3 = 6).

Run: `cd admin && npm test`
Expected: full suite passes (toast, auth, client, client_unauthorized, TokenGate, AppShell).

Run: `cd admin && npm run build`
Expected: `tsc -b` clean + `vite build` writes dist/.

- [ ] **Step 9: Commit**

```bash
git add admin/src/api/client.ts admin/src/auth/AuthContext.tsx admin/src/auth/TokenGate.tsx \
  admin/src/main.tsx admin/src/test/auth.test.tsx admin/src/test/client_unauthorized.test.ts \
  admin/src/test/TokenGate.test.tsx
git commit -m "feat(admin-ui): auth context + 401 stale-token recovery"
```

---

### Task 3: useAdminAction hook + ActionButton

**Files:**
- Create: `admin/src/api/actions.ts`, `admin/src/components/ActionButton.tsx`, `admin/src/test/ActionButton.test.tsx`

**Interfaces:**
- Consumes: `apiFetch`, `useToast`, TanStack Query `useMutation`/`useQueryClient`.
- Produces:
  - `actions.ts`: `useAdminAction(opts: { path: string; method?: string; invalidateKeys?: string[][]; successMessage: string }): { run: () => void; isPending: boolean }`. On success it toasts `successMessage` (tone `ok`) and invalidates each key array via the query client; on error it toasts `err.message` (tone `error`). It swallows the rejection so a failed action does not surface as an unhandled rejection (the toast is the user feedback).
  - `ActionButton.tsx`: `<ActionButton label="…" path="/admin/…" method? invalidateKeys? successMessage="…" />` — a Radix `Button` that calls `run` on click and is `disabled`/shows `…` while pending.

- [ ] **Step 1: Write the failing test**

`admin/src/test/ActionButton.test.tsx`:
```tsx
import { afterEach, describe, it, expect, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { ToastProvider } from '../ui/toast'
import { ActionButton } from '../components/ActionButton'
import { setToken } from '../api/client'

afterEach(() => { localStorage.clear(); vi.restoreAllMocks() })

function wrap(ui: React.ReactNode) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return <QueryClientProvider client={qc}><ToastProvider>{ui}</ToastProvider></QueryClientProvider>
}

describe('ActionButton', () => {
  it('POSTs the path and toasts the success message', async () => {
    setToken('tok')
    const fetchMock = vi.fn().mockResolvedValue(new Response(JSON.stringify({ ok: true }), { status: 200 }))
    vi.stubGlobal('fetch', fetchMock)

    render(wrap(<ActionButton label="Crawl" path="/admin/crawl" successMessage="Crawl triggered" />))
    await userEvent.click(screen.getByRole('button', { name: 'Crawl' }))

    expect(await screen.findByText('Crawl triggered')).toBeInTheDocument()
    const [url, init] = fetchMock.mock.calls[0]
    expect(String(url)).toMatch(/\/admin\/crawl$/)
    expect(init.method).toBe('POST')
  })

  it('toasts the error message on failure', async () => {
    setToken('tok')
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(
      new Response(JSON.stringify({ error: { code: 'INTERNAL', message: 'boom' } }), { status: 500 })
    ))
    render(wrap(<ActionButton label="Crawl" path="/admin/crawl" successMessage="ok" />))
    await userEvent.click(screen.getByRole('button', { name: 'Crawl' }))
    expect(await screen.findByText('boom')).toBeInTheDocument()
  })
})
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd admin && npx vitest run src/test/ActionButton.test.tsx`
Expected: FAIL — `../components/ActionButton` does not exist.

- [ ] **Step 3: Implement `admin/src/api/actions.ts`**

```ts
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { apiFetch, ApiError } from './client'
import { useToast } from '../ui/toast'

export function useAdminAction(opts: {
  path: string
  method?: string
  invalidateKeys?: string[][]
  successMessage: string
}): { run: () => void; isPending: boolean } {
  const qc = useQueryClient()
  const { show } = useToast()

  const mutation = useMutation({
    mutationFn: () => apiFetch(opts.path, { method: opts.method ?? 'POST' }),
    onSuccess: () => {
      show(opts.successMessage, 'ok')
      for (const key of opts.invalidateKeys ?? []) {
        void qc.invalidateQueries({ queryKey: key })
      }
    },
    onError: (err) => {
      show(err instanceof ApiError ? err.message : 'Request failed', 'error')
    }
  })

  return { run: () => mutation.mutate(), isPending: mutation.isPending }
}
```

- [ ] **Step 4: Implement `admin/src/components/ActionButton.tsx`**

```tsx
import { Button } from '@radix-ui/themes'
import { useAdminAction } from '../api/actions'

export function ActionButton(props: {
  label: string
  path: string
  method?: string
  invalidateKeys?: string[][]
  successMessage: string
}) {
  const { run, isPending } = useAdminAction({
    path: props.path,
    method: props.method,
    invalidateKeys: props.invalidateKeys,
    successMessage: props.successMessage
  })
  return (
    <Button onClick={run} disabled={isPending} variant="surface">
      {isPending ? '…' : props.label}
    </Button>
  )
}
```

- [ ] **Step 5: Run to verify it passes**

Run: `cd admin && npx vitest run src/test/ActionButton.test.tsx`
Expected: PASS (2 tests). Then `cd admin && npm run build` → clean.

- [ ] **Step 6: Commit**

```bash
git add admin/src/api/actions.ts admin/src/components/ActionButton.tsx admin/src/test/ActionButton.test.tsx
git commit -m "feat(admin-ui): useAdminAction + ActionButton (toast + invalidate)"
```

---

### Task 4: FetchControls panel on the Dashboard

**Files:**
- Create: `admin/src/components/FetchControls.tsx`, `admin/src/test/FetchControls.test.tsx`
- Modify: `admin/src/pages/Dashboard.tsx`

**Interfaces:**
- Consumes: `ActionButton`.
- Produces:
  - `<FetchControls/>` — a Card titled "Fetch controls" containing five `ActionButton`s (Bootstrap schedule, Crawl tick, Refresh images, Refresh OpenF1 metadata, Sync circuits). Bootstrap and Crawl invalidate `[['crawl-status']]` so the status cards refresh.
  - `Dashboard` renders `<FetchControls/>` beneath the status cards.

- [ ] **Step 1: Write the failing test**

`admin/src/test/FetchControls.test.tsx`:
```tsx
import { describe, it, expect } from 'vitest'
import { render, screen } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { ToastProvider } from '../ui/toast'
import { FetchControls } from '../components/FetchControls'

function wrap(ui: React.ReactNode) {
  const qc = new QueryClient()
  return <QueryClientProvider client={qc}><ToastProvider>{ui}</ToastProvider></QueryClientProvider>
}

describe('FetchControls', () => {
  it('renders all five trigger buttons', () => {
    render(wrap(<FetchControls />))
    for (const label of ['Bootstrap schedule', 'Crawl tick', 'Refresh images', 'Refresh OpenF1 metadata', 'Sync circuits']) {
      expect(screen.getByRole('button', { name: label })).toBeInTheDocument()
    }
  })
})
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd admin && npx vitest run src/test/FetchControls.test.tsx`
Expected: FAIL — `../components/FetchControls` does not exist.

- [ ] **Step 3: Implement `admin/src/components/FetchControls.tsx`**

```tsx
import { Card, Flex, Text } from '@radix-ui/themes'
import { ActionButton } from './ActionButton'

const CRAWL_KEY: string[][] = [['crawl-status']]

export function FetchControls() {
  return (
    <Card size="3">
      <Flex direction="column" gap="3">
        <Text size="1" className="label">Fetch controls</Text>
        <Flex gap="2" wrap="wrap">
          <ActionButton label="Bootstrap schedule" path="/admin/bootstrap" successMessage="Schedule bootstrapped" invalidateKeys={CRAWL_KEY} />
          <ActionButton label="Crawl tick" path="/admin/crawl" successMessage="Crawl tick triggered" invalidateKeys={CRAWL_KEY} />
          <ActionButton label="Refresh images" path="/admin/refresh-images" successMessage="Images refreshed" />
          <ActionButton label="Refresh OpenF1 metadata" path="/admin/refresh-openf1-metadata" successMessage="OpenF1 metadata refreshed" />
          <ActionButton label="Sync circuits" path="/admin/circuits/sync" successMessage="Circuits synced" />
        </Flex>
      </Flex>
    </Card>
  )
}
```

- [ ] **Step 4: Modify `admin/src/pages/Dashboard.tsx`** to render the panel

Add the import at the top:
```tsx
import { FetchControls } from '../components/FetchControls'
```
Then render `<FetchControls />` as the last child of the outer `<Flex direction="column" gap="4">`, after the `{data && (…)}` block:
```tsx
      )}
      <FetchControls />
    </Flex>
  )
}
```
(So `FetchControls` shows regardless of crawl-status load state.)

- [ ] **Step 5: Run the test + full gates**

Run: `cd admin && npx vitest run src/test/FetchControls.test.tsx`
Expected: PASS (1 test).

Run: `cd admin && npm test`
Expected: full suite green (toast, auth, client, client_unauthorized, TokenGate, ActionButton, FetchControls, AppShell).

Run: `cd admin && npm run build`
Expected: `tsc -b` clean + `vite build` writes dist/.

- [ ] **Step 6: Manual smoke (optional)**

With the Vite server pointed at a backend and unlocked, the Dashboard shows a "Fetch controls" card. Clicking **Crawl tick** should toast "Crawl tick triggered" and the status cards refresh shortly after. (Against production, this triggers a real crawl — harmless, idempotent, but it is a live action.)

- [ ] **Step 7: Commit**

```bash
git add admin/src/components/FetchControls.tsx admin/src/test/FetchControls.test.tsx admin/src/pages/Dashboard.tsx
git commit -m "feat(admin-ui): fetch controls panel on the Dashboard"
```

---

## Self-Review

**Spec coverage (spec §6 Fetches, plan roadmap item 3):**
- Trigger buttons over existing admin POST routes (bootstrap/crawl/refresh-images/refresh-openf1-metadata/circuits-sync) → Task 4 (`FetchControls`) ✓
- Async/pending state per button → Task 3 (`ActionButton` disabled + `…`) ✓
- Toast on success/failure → Task 1 (toast) + Task 3 (`useAdminAction`) ✓
- Query invalidation so the status panel refreshes → Task 3/4 (`invalidateKeys: [['crawl-status']]`) ✓
- Stale-token recovery (Plan 2 review forward note: 401 → clear token → gate) → Task 2 ✓

**Type consistency:** `useToast`/`ToastTone` (Task 1) consumed by `AuthProvider` (Task 2), `useAdminAction` (Task 3). `setUnauthorizedHandler` (Task 2, client.ts) registered by `AuthProvider`. `useAuth` (Task 2) consumed by the refactored `TokenGate`. `useAdminAction` (Task 3) consumed by `ActionButton` (Task 3) consumed by `FetchControls` (Task 4). Provider nesting in `main.tsx` (Task 2): `Theme > ToastProvider > AuthProvider > QueryClientProvider > TokenGate > RouterProvider` — every hook resolves (AuthProvider needs ToastProvider; useAdminAction needs both QueryClientProvider and ToastProvider).

**Open notes for the implementer:**
- Task 2 changes `TokenGate`'s unlock signal from local state to `useAuth().token`; the Plan-2 `TokenGate.test.tsx` must be wrapped in the providers (Step 7) or it throws "useAuth must be used within an AuthProvider".
- `useRef` import in `toast.tsx` is lowercase `useRef` (the brief code block is correct; do not transcribe a capitalized `useRef`).
- Radix `Button variant="surface"` is used for the trigger buttons to read as secondary; if that variant name differs in the installed Radix version, use `variant="soft"` and note it.

## Next plans in this series

4. **Session result editing** — backend `PATCH/POST/DELETE /admin/sessions/:id/results...` + a `SessionDetail` page with an inline-editable results grid + per-session re-fetch/re-score buttons (reusing `ActionButton`).
5. **Leagues admin** — backend cross-user league write routes + `Leagues`/`LeagueDetail`.
6. **Season management + remaining pages** — `Seasons`, drivers/constructors edit, users, predictions, standings, notifications.
