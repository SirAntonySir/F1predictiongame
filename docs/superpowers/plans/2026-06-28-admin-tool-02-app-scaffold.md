# Admin Tool — Plan 2: Admin App Scaffold (Vite + React + TS + Radix)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up a runnable, app-styled admin SPA in `admin/` — Vite + React + TypeScript + Radix Themes — with a token gate (validated against the Plan 1 `GET /admin/crawl/status` endpoint), a typed API client that injects `X-Admin-Token`, a TanStack Query provider, and an app shell with sidebar navigation and a Dashboard that shows live crawl status.

**Architecture:** A standalone Vite SPA in `admin/`, a sibling of `backend/` and `lib/`. It talks directly to the backend at `VITE_API_URL` (default `http://localhost:3000`); the backend already sets CORS `origin: true`, so no proxy is needed. The admin token is entered once in the UI and kept in `localStorage`; every request carries it as `X-Admin-Token`. Styling mirrors the Flutter app's theme (dark surfaces, red `#E10600` accent, Anton/Inter type) via CSS variables layered over Radix Themes.

**Tech Stack:** Vite, React 18, TypeScript, Radix Themes, TanStack Query (react-query) v5, react-router-dom v6, Vitest + React Testing Library + jsdom (light tests).

## Global Constraints

- This entire plan creates files under `admin/` ONLY. Do not modify `backend/`, `lib/`, or any file outside `admin/` except the repo-root `Makefile` (Task 1 adds two targets) and `.gitignore` if needed for `admin/node_modules` / `admin/dist`.
- **Concurrency:** another session may be editing `backend/` and pushing to `main`. NEVER `git add -A`/`git add .`/`git commit -a`. Stage only the exact `admin/...` (and `Makefile`) paths each task names. If `git status` shows files you didn't create, leave them unstaged.
- Backend base URL: `import.meta.env.VITE_API_URL ?? 'http://localhost:3000'` (matches the Makefile's `API_URL`). The dev admin token is `local-dev-token` (the backend's `ADMIN_TOKEN` in dev).
- Token storage key: `localStorage['f1pg_admin_token']`. Sent as header `X-Admin-Token` on every request.
- Token validation endpoint (exists from Plan 1): `GET /admin/crawl/status` → 200 (valid token) or 401 (missing/invalid). Response body shape: `{ lastTickAt: string | null, lastTickStatus: 'ok' | 'error' | null, pendingCandidates: { id: number, type: string }[], provisionalSessions: { id: number, eventName: string, type: string }[] }`.
- Theme tokens (ported from `lib/theme/colors.dart` + `typography.dart`), use these EXACT values:
  - surfaces: `--surface: #0E0E10`, `--surface-muted: #16161A`, `--stroke: #2A2A2E`
  - text: `--on-surface: #F2F2F2`, `--on-surface-muted: #9A9A9E`
  - accent: `--accent: #E10600`, `--ok: #19D36B`, `--near: #FFD233`, `--violet: #B147FF`
  - radius 14px on cards; fonts: **Anton** (display/headings), **Inter** (body/labels)
- Run commands from `admin/` unless stated. Tests: `npm test` (vitest run). Typecheck/build gate: `npm run build` (`tsc && vite build`).
- TypeScript strict mode on. No `any` unless unavoidable (annotate why).

## File Structure

```
admin/
  package.json            # deps + scripts
  vite.config.ts          # react plugin + vitest (jsdom) config
  tsconfig.json           # app TS config (strict)
  tsconfig.node.json      # TS config for vite.config.ts
  index.html              # entry; loads Anton + Inter from Google Fonts
  .gitignore              # node_modules, dist
  src/
    main.tsx              # React root: Theme + QueryClientProvider + Router
    vite-env.d.ts         # Vite/import.meta.env types
    theme/
      tokens.css          # ported app palette + font vars, Radix overrides
    api/
      client.ts           # getToken/setToken/clearToken + apiFetch + ApiError
      types.ts            # CrawlStatus and shared response types
      hooks.ts            # useCrawlStatus (TanStack Query)
    auth/
      TokenGate.tsx       # token entry + validation gate
    components/
      AppShell.tsx        # sidebar nav + header + <Outlet/>
    pages/
      Dashboard.tsx       # crawl status panel (placeholder for fetch controls)
      Placeholder.tsx     # generic "coming soon" page for unbuilt routes
    router.tsx            # route table (AppShell + pages)
    test/
      setup.ts            # RTL jest-dom matchers
      client.test.ts      # apiFetch unit tests
      TokenGate.test.tsx  # gate behavior
      AppShell.test.tsx   # shell renders nav
```

---

### Task 1: Scaffold Vite + React + TS app with Radix Themes and ported theme

**Files:**
- Create: `admin/package.json`, `admin/vite.config.ts`, `admin/tsconfig.json`, `admin/tsconfig.node.json`, `admin/index.html`, `admin/.gitignore`, `admin/src/main.tsx`, `admin/src/vite-env.d.ts`, `admin/src/theme/tokens.css`, `admin/src/App.tsx` (temporary smoke component), `admin/src/test/setup.ts`, `admin/src/test/smoke.test.tsx`
- Modify: `Makefile` (repo root) — add `admin-install` and `admin` targets

**Interfaces:**
- Produces: a runnable Vite app; `npm run build` and `npm test` both pass. Later tasks replace `App.tsx` content with the real shell.

- [ ] **Step 1: Create `admin/package.json`**

```json
{
  "name": "f1pg-admin",
  "private": true,
  "version": "0.1.0",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "tsc -b && vite build",
    "preview": "vite preview",
    "test": "vitest run",
    "test:watch": "vitest"
  },
  "dependencies": {
    "@radix-ui/themes": "^3.1.4",
    "@tanstack/react-query": "^5.59.16",
    "react": "^18.3.1",
    "react-dom": "^18.3.1",
    "react-router-dom": "^6.28.0"
  },
  "devDependencies": {
    "@testing-library/jest-dom": "^6.6.3",
    "@testing-library/react": "^16.0.1",
    "@testing-library/user-event": "^14.5.2",
    "@types/react": "^18.3.12",
    "@types/react-dom": "^18.3.1",
    "@vitejs/plugin-react": "^4.3.3",
    "jsdom": "^25.0.1",
    "typescript": "^5.6.3",
    "vite": "^5.4.10",
    "vitest": "^2.1.4"
  }
}
```

> If any version fails to resolve at install, use the latest compatible release of that package and note it in the report.

- [ ] **Step 2: Create config files**

`admin/tsconfig.json`:
```json
{
  "compilerOptions": {
    "target": "ES2022",
    "useDefineForClassFields": true,
    "lib": ["ES2022", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "skipLibCheck": true,
    "moduleResolution": "bundler",
    "allowImportingTsExtensions": false,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "noEmit": true,
    "jsx": "react-jsx",
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noFallthroughCasesInSwitch": true,
    "types": ["vitest/globals", "@testing-library/jest-dom"]
  },
  "include": ["src"],
  "references": [{ "path": "./tsconfig.node.json" }]
}
```

`admin/tsconfig.node.json`:
```json
{
  "compilerOptions": {
    "composite": true,
    "skipLibCheck": true,
    "module": "ESNext",
    "moduleResolution": "bundler",
    "allowSyntheticDefaultImports": true,
    "strict": true,
    "noEmit": true
  },
  "include": ["vite.config.ts"]
}
```

`admin/vite.config.ts`:
```ts
/// <reference types="vitest/config" />
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  server: { port: 5173 },
  test: {
    globals: true,
    environment: 'jsdom',
    setupFiles: ['src/test/setup.ts'],
    css: false
  }
})
```

`admin/src/vite-env.d.ts`:
```ts
/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_API_URL?: string
}
interface ImportMeta {
  readonly env: ImportMetaEnv
}
```

`admin/.gitignore`:
```
node_modules
dist
*.local
```

- [ ] **Step 3: Create `admin/index.html`** (loads Anton + Inter)

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>F1PG Admin</title>
    <link rel="preconnect" href="https://fonts.googleapis.com" />
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
    <link
      href="https://fonts.googleapis.com/css2?family=Anton&family=Inter:wght@400;500;700;800&display=swap"
      rel="stylesheet"
    />
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.tsx"></script>
  </body>
</html>
```

- [ ] **Step 4: Create `admin/src/theme/tokens.css`** (ported palette + Radix overrides)

```css
:root {
  --surface: #0E0E10;
  --surface-muted: #16161A;
  --stroke: #2A2A2E;
  --on-surface: #F2F2F2;
  --on-surface-muted: #9A9A9E;
  --accent: #E10600;
  --ok: #19D36B;
  --near: #FFD233;
  --violet: #B147FF;
  --radius-card: 14px;
  --font-display: 'Anton', system-ui, sans-serif;
  --font-body: 'Inter', system-ui, sans-serif;
}

html, body, #root { height: 100%; margin: 0; }
body {
  background: var(--surface);
  color: var(--on-surface);
  font-family: var(--font-body);
}

/* Radix Theme surface tuning to match the app's near-black panels. */
.radix-themes {
  --color-background: var(--surface);
  --color-panel-solid: var(--surface-muted);
  --gray-a6: var(--stroke);
}

h1, h2, h3, .display {
  font-family: var(--font-display);
  letter-spacing: -0.01em;
  font-weight: 400;
}
.label {
  font-family: var(--font-body);
  font-weight: 800;
  letter-spacing: 0.12em;
  text-transform: uppercase;
}
```

- [ ] **Step 5: Create `admin/src/App.tsx`** (temporary smoke component, replaced in Task 4)

```tsx
export function App() {
  return (
    <div style={{ padding: 24 }}>
      <h1 className="display">F1PG Admin</h1>
      <p className="label" style={{ color: 'var(--accent)' }}>scaffold online</p>
    </div>
  )
}
```

- [ ] **Step 6: Create `admin/src/main.tsx`**

```tsx
import React from 'react'
import ReactDOM from 'react-dom/client'
import { Theme } from '@radix-ui/themes'
import '@radix-ui/themes/styles.css'
import './theme/tokens.css'
import { App } from './App'

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <Theme appearance="dark" accentColor="red" grayColor="gray" radius="medium">
      <App />
    </Theme>
  </React.StrictMode>
)
```

- [ ] **Step 7: Create the test setup + smoke test**

`admin/src/test/setup.ts`:
```ts
import '@testing-library/jest-dom/vitest'
```

`admin/src/test/smoke.test.tsx`:
```tsx
import { render, screen } from '@testing-library/react'
import { App } from '../App'

it('renders the admin scaffold heading', () => {
  render(<App />)
  expect(screen.getByRole('heading', { name: /f1pg admin/i })).toBeInTheDocument()
})
```

- [ ] **Step 8: Install dependencies and run the gates**

Run:
```
cd /Users/anton/Dev/Projects/F1predictiongame/admin && npm install
```
Expected: installs without fatal errors (peer-dep warnings are fine).

Run: `cd /Users/anton/Dev/Projects/F1predictiongame/admin && npm test`
Expected: 1 test passes (smoke test renders the heading).

Run: `cd /Users/anton/Dev/Projects/F1predictiongame/admin && npm run build`
Expected: `tsc -b` reports no type errors and `vite build` writes `dist/` successfully.

- [ ] **Step 9: Add Makefile targets**

In the repo-root `Makefile`, under the frontend section, add:
```makefile
.PHONY: admin-install
admin-install:  ## install admin tool deps
	cd admin && npm install

.PHONY: admin
admin:          ## run the admin tool dev server (vite)
	cd admin && VITE_API_URL=$(API_URL) npm run dev
```

- [ ] **Step 10: Commit**

```bash
git add admin/package.json admin/package-lock.json admin/vite.config.ts \
  admin/tsconfig.json admin/tsconfig.node.json admin/index.html admin/.gitignore \
  admin/src/main.tsx admin/src/vite-env.d.ts admin/src/theme/tokens.css \
  admin/src/App.tsx admin/src/test/setup.ts admin/src/test/smoke.test.tsx Makefile
git commit -m "feat(admin-ui): scaffold Vite+React+TS+Radix app with app theme"
```

---

### Task 2: Typed API client + token storage

**Files:**
- Create: `admin/src/api/client.ts`, `admin/src/api/types.ts`, `admin/src/test/client.test.ts`

**Interfaces:**
- Consumes: `import.meta.env.VITE_API_URL`.
- Produces:
  - `getToken(): string | null`, `setToken(t: string): void`, `clearToken(): void` (localStorage key `f1pg_admin_token`)
  - `class ApiError extends Error { status: number; code: string }`
  - `apiFetch<T>(path: string, opts?: { method?: string; body?: unknown; token?: string }): Promise<T>` — prefixes the base URL, sets `X-Admin-Token` (from `opts.token` or `getToken()`), JSON-encodes body, throws `ApiError` on non-2xx (parsing `{ error: { code, message } }` when present), returns parsed JSON.
  - `CrawlStatus` type in `types.ts` (matches the Plan 1 response).

- [ ] **Step 1: Write the failing tests**

`admin/src/test/client.test.ts`:
```ts
import { beforeEach, afterEach, describe, it, expect, vi } from 'vitest'
import { apiFetch, ApiError, getToken, setToken, clearToken } from '../api/client'

describe('token storage', () => {
  beforeEach(() => localStorage.clear())
  it('round-trips the token', () => {
    expect(getToken()).toBeNull()
    setToken('abc')
    expect(getToken()).toBe('abc')
    clearToken()
    expect(getToken()).toBeNull()
  })
})

describe('apiFetch', () => {
  beforeEach(() => { localStorage.clear(); setToken('tok123') })
  afterEach(() => vi.restoreAllMocks())

  it('prefixes base URL and sends the admin token header', async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      new Response(JSON.stringify({ ok: true }), { status: 200, headers: { 'content-type': 'application/json' } })
    )
    vi.stubGlobal('fetch', fetchMock)
    const out = await apiFetch<{ ok: boolean }>('/admin/crawl/status')
    expect(out).toEqual({ ok: true })
    const [url, init] = fetchMock.mock.calls[0]
    expect(String(url)).toMatch(/\/admin\/crawl\/status$/)
    expect((init.headers as Record<string, string>)['X-Admin-Token']).toBe('tok123')
  })

  it('throws ApiError with status and code on non-2xx', async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      new Response(JSON.stringify({ error: { code: 'UNAUTHORIZED', message: 'Invalid admin token' } }),
        { status: 401, headers: { 'content-type': 'application/json' } })
    )
    vi.stubGlobal('fetch', fetchMock)
    await expect(apiFetch('/admin/crawl/status')).rejects.toMatchObject({
      name: 'ApiError', status: 401, code: 'UNAUTHORIZED'
    })
  })
})
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd admin && npx vitest run src/test/client.test.ts`
Expected: FAIL — `../api/client` does not exist.

- [ ] **Step 3: Implement `admin/src/api/types.ts`**

```ts
export type CrawlStatus = {
  lastTickAt: string | null
  lastTickStatus: 'ok' | 'error' | null
  pendingCandidates: { id: number; type: string }[]
  provisionalSessions: { id: number; eventName: string; type: string }[]
}
```

- [ ] **Step 4: Implement `admin/src/api/client.ts`**

```ts
const TOKEN_KEY = 'f1pg_admin_token'
const BASE_URL = import.meta.env.VITE_API_URL ?? 'http://localhost:3000'

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
```

- [ ] **Step 5: Run to verify it passes**

Run: `cd admin && npx vitest run src/test/client.test.ts`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add admin/src/api/client.ts admin/src/api/types.ts admin/src/test/client.test.ts
git commit -m "feat(admin-ui): typed API client with X-Admin-Token + token storage"
```

---

### Task 3: TanStack Query hook + TokenGate

**Files:**
- Create: `admin/src/api/hooks.ts`, `admin/src/auth/TokenGate.tsx`, `admin/src/test/TokenGate.test.tsx`

**Interfaces:**
- Consumes: `apiFetch`, `setToken`, `getToken`, `clearToken`, `ApiError`, `CrawlStatus`.
- Produces:
  - `useCrawlStatus()` — `useQuery` hook returning `CrawlStatus`, key `['crawl-status']`, `queryFn: () => apiFetch<CrawlStatus>('/admin/crawl/status')`.
  - `<TokenGate>{children}</TokenGate>` — if no stored token, renders a token-entry form; on submit it validates by calling `apiFetch('/admin/crawl/status', { token })`, and on success stores the token and renders `children`. On failure shows an inline error and does not store. If a token is already stored, renders `children` directly. Exposes a "Sign out" affordance via context is NOT required here (kept minimal).

- [ ] **Step 1: Write the failing test**

`admin/src/test/TokenGate.test.tsx`:
```tsx
import { afterEach, describe, it, expect, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { TokenGate } from '../auth/TokenGate'

afterEach(() => { localStorage.clear(); vi.restoreAllMocks() })

describe('TokenGate', () => {
  it('shows the token form when no token is stored', () => {
    render(<TokenGate><div>secret</div></TokenGate>)
    expect(screen.getByLabelText(/admin token/i)).toBeInTheDocument()
    expect(screen.queryByText('secret')).not.toBeInTheDocument()
  })

  it('stores the token and reveals children on a valid token', async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      new Response(JSON.stringify({ lastTickAt: null, lastTickStatus: null, pendingCandidates: [], provisionalSessions: [] }),
        { status: 200, headers: { 'content-type': 'application/json' } })
    )
    vi.stubGlobal('fetch', fetchMock)
    render(<TokenGate><div>secret</div></TokenGate>)
    await userEvent.type(screen.getByLabelText(/admin token/i), 'local-dev-token')
    await userEvent.click(screen.getByRole('button', { name: /unlock|sign in|enter/i }))
    expect(await screen.findByText('secret')).toBeInTheDocument()
    expect(localStorage.getItem('f1pg_admin_token')).toBe('local-dev-token')
  })

  it('shows an error and keeps the form on an invalid token', async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      new Response(JSON.stringify({ error: { code: 'UNAUTHORIZED', message: 'Invalid admin token' } }),
        { status: 401, headers: { 'content-type': 'application/json' } })
    )
    vi.stubGlobal('fetch', fetchMock)
    render(<TokenGate><div>secret</div></TokenGate>)
    await userEvent.type(screen.getByLabelText(/admin token/i), 'wrong')
    await userEvent.click(screen.getByRole('button', { name: /unlock|sign in|enter/i }))
    expect(await screen.findByText(/invalid admin token/i)).toBeInTheDocument()
    expect(screen.queryByText('secret')).not.toBeInTheDocument()
    expect(localStorage.getItem('f1pg_admin_token')).toBeNull()
  })
})
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd admin && npx vitest run src/test/TokenGate.test.tsx`
Expected: FAIL — `../auth/TokenGate` does not exist.

- [ ] **Step 3: Implement `admin/src/api/hooks.ts`**

```ts
import { useQuery } from '@tanstack/react-query'
import { apiFetch } from './client'
import type { CrawlStatus } from './types'

export function useCrawlStatus() {
  return useQuery({
    queryKey: ['crawl-status'],
    queryFn: () => apiFetch<CrawlStatus>('/admin/crawl/status')
  })
}
```

- [ ] **Step 4: Implement `admin/src/auth/TokenGate.tsx`**

```tsx
import { useState, type ReactNode } from 'react'
import { Box, Button, Card, Flex, Heading, Text, TextField } from '@radix-ui/themes'
import { apiFetch, getToken, setToken, ApiError } from '../api/client'

export function TokenGate({ children }: { children: ReactNode }) {
  const [unlocked, setUnlocked] = useState(() => getToken() !== null)
  const [value, setValue] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  if (unlocked) return <>{children}</>

  async function submit(e: React.FormEvent) {
    e.preventDefault()
    setBusy(true)
    setError(null)
    try {
      // Validate by hitting a token-gated endpoint with the candidate token.
      await apiFetch('/admin/crawl/status', { token: value })
      setToken(value)
      setUnlocked(true)
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

- [ ] **Step 5: Run to verify it passes**

Run: `cd admin && npx vitest run src/test/TokenGate.test.tsx`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add admin/src/api/hooks.ts admin/src/auth/TokenGate.tsx admin/src/test/TokenGate.test.tsx
git commit -m "feat(admin-ui): TokenGate + useCrawlStatus query hook"
```

---

### Task 4: App shell, router, Dashboard — wire it together

**Files:**
- Create: `admin/src/components/AppShell.tsx`, `admin/src/pages/Dashboard.tsx`, `admin/src/pages/Placeholder.tsx`, `admin/src/router.tsx`, `admin/src/test/AppShell.test.tsx`
- Modify: `admin/src/main.tsx` (mount Router + QueryClientProvider + TokenGate), delete `admin/src/App.tsx` and `admin/src/test/smoke.test.tsx`

**Interfaces:**
- Consumes: `TokenGate`, `useCrawlStatus`, router pages.
- Produces:
  - `<AppShell/>` — a left sidebar with `NavLink`s (Dashboard, Sessions, Leagues, Users, Predictions, Seasons, Drivers, Constructors) and a header; renders `<Outlet/>` for the active page. Only Dashboard is real; the rest route to `Placeholder`.
  - `<Dashboard/>` — calls `useCrawlStatus()` and renders last tick + pending candidates + provisional sessions; shows a loading and error state.
  - `router` (a `createBrowserRouter` config) with `AppShell` as the layout route.

- [ ] **Step 1: Write the failing test**

`admin/src/test/AppShell.test.tsx`:
```tsx
import { describe, it, expect } from 'vitest'
import { render, screen } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { AppShell } from '../components/AppShell'

describe('AppShell', () => {
  it('renders the sidebar navigation links', () => {
    render(
      <MemoryRouter>
        <AppShell />
      </MemoryRouter>
    )
    expect(screen.getByRole('link', { name: /dashboard/i })).toBeInTheDocument()
    expect(screen.getByRole('link', { name: /leagues/i })).toBeInTheDocument()
    expect(screen.getByRole('link', { name: /sessions/i })).toBeInTheDocument()
  })
})
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd admin && npx vitest run src/test/AppShell.test.tsx`
Expected: FAIL — `../components/AppShell` does not exist.

- [ ] **Step 3: Implement `admin/src/components/AppShell.tsx`**

```tsx
import { NavLink, Outlet } from 'react-router-dom'
import { Box, Flex, Heading } from '@radix-ui/themes'

const NAV: { to: string; label: string }[] = [
  { to: '/', label: 'Dashboard' },
  { to: '/sessions', label: 'Sessions' },
  { to: '/leagues', label: 'Leagues' },
  { to: '/users', label: 'Users' },
  { to: '/predictions', label: 'Predictions' },
  { to: '/seasons', label: 'Seasons' },
  { to: '/drivers', label: 'Drivers' },
  { to: '/constructors', label: 'Constructors' }
]

export function AppShell() {
  return (
    <Flex style={{ minHeight: '100vh' }}>
      <Box
        p="4"
        style={{ width: 220, borderRight: '2px solid var(--stroke)', background: 'var(--surface-muted)' }}
      >
        <Heading size="4" className="display" mb="4" style={{ color: 'var(--accent)' }}>
          F1PG ADMIN
        </Heading>
        <Flex direction="column" gap="1" asChild>
          <nav>
            {NAV.map((n) => (
              <NavLink
                key={n.to}
                to={n.to}
                end={n.to === '/'}
                className="label"
                style={({ isActive }) => ({
                  padding: '8px 10px',
                  borderRadius: 'var(--radius-card)',
                  color: isActive ? 'var(--accent)' : 'var(--on-surface-muted)',
                  textDecoration: 'none'
                })}
              >
                {n.label}
              </NavLink>
            ))}
          </nav>
        </Flex>
      </Box>
      <Box p="5" style={{ flex: 1 }}>
        <Outlet />
      </Box>
    </Flex>
  )
}
```

- [ ] **Step 4: Implement the pages**

`admin/src/pages/Placeholder.tsx`:
```tsx
import { Heading, Text, Flex } from '@radix-ui/themes'

export function Placeholder({ title }: { title: string }) {
  return (
    <Flex direction="column" gap="2">
      <Heading size="6" className="display">{title}</Heading>
      <Text size="2" style={{ color: 'var(--on-surface-muted)' }}>Coming in a later slice.</Text>
    </Flex>
  )
}
```

`admin/src/pages/Dashboard.tsx`:
```tsx
import { Card, Flex, Heading, Text, Badge, Box } from '@radix-ui/themes'
import { useCrawlStatus } from '../api/hooks'

export function Dashboard() {
  const { data, isLoading, error } = useCrawlStatus()

  return (
    <Flex direction="column" gap="4">
      <Heading size="6" className="display">Dashboard</Heading>
      {isLoading && <Text size="2">Loading crawl status…</Text>}
      {error && <Text size="2" color="red">Failed to load crawl status.</Text>}
      {data && (
        <Flex gap="4" wrap="wrap">
          <Card size="2" style={{ minWidth: 220 }}>
            <Text size="1" className="label">Last tick</Text>
            <Box mt="1">
              <Text size="3">{data.lastTickAt ?? '—'}</Text>{' '}
              {data.lastTickStatus && (
                <Badge color={data.lastTickStatus === 'ok' ? 'green' : 'red'}>
                  {data.lastTickStatus}
                </Badge>
              )}
            </Box>
          </Card>
          <Card size="2" style={{ minWidth: 220 }}>
            <Text size="1" className="label">Pending candidates</Text>
            <Box mt="1"><Text size="6" className="display">{data.pendingCandidates.length}</Text></Box>
          </Card>
          <Card size="2" style={{ minWidth: 220 }}>
            <Text size="1" className="label">Provisional sessions</Text>
            <Box mt="1"><Text size="6" className="display">{data.provisionalSessions.length}</Text></Box>
          </Card>
        </Flex>
      )}
    </Flex>
  )
}
```

- [ ] **Step 5: Implement `admin/src/router.tsx`**

```tsx
import { createBrowserRouter } from 'react-router-dom'
import { AppShell } from './components/AppShell'
import { Dashboard } from './pages/Dashboard'
import { Placeholder } from './pages/Placeholder'

export const router = createBrowserRouter([
  {
    path: '/',
    element: <AppShell />,
    children: [
      { index: true, element: <Dashboard /> },
      { path: 'sessions', element: <Placeholder title="Sessions" /> },
      { path: 'leagues', element: <Placeholder title="Leagues" /> },
      { path: 'users', element: <Placeholder title="Users" /> },
      { path: 'predictions', element: <Placeholder title="Predictions" /> },
      { path: 'seasons', element: <Placeholder title="Seasons" /> },
      { path: 'drivers', element: <Placeholder title="Drivers" /> },
      { path: 'constructors', element: <Placeholder title="Constructors" /> }
    ]
  }
])
```

- [ ] **Step 6: Replace `admin/src/main.tsx`** (full new contents)

```tsx
import React from 'react'
import ReactDOM from 'react-dom/client'
import { Theme } from '@radix-ui/themes'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { RouterProvider } from 'react-router-dom'
import '@radix-ui/themes/styles.css'
import './theme/tokens.css'
import { TokenGate } from './auth/TokenGate'
import { router } from './router'

const queryClient = new QueryClient()

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <Theme appearance="dark" accentColor="red" grayColor="gray" radius="medium">
      <QueryClientProvider client={queryClient}>
        <TokenGate>
          <RouterProvider router={router} />
        </TokenGate>
      </QueryClientProvider>
    </Theme>
  </React.StrictMode>
)
```

- [ ] **Step 7: Remove the temporary scaffold files**

```bash
git rm admin/src/App.tsx admin/src/test/smoke.test.tsx
```

- [ ] **Step 8: Run the test + full gates**

Run: `cd admin && npx vitest run src/test/AppShell.test.tsx`
Expected: PASS (1 test).

Run: `cd admin && npm test`
Expected: all tests pass (client, TokenGate, AppShell — the smoke test is removed).

Run: `cd admin && npm run build`
Expected: `tsc -b` clean, `vite build` writes `dist/`.

- [ ] **Step 9: Manual smoke (optional but recommended)**

With the backend running (`make up` from repo root, in another terminal), run `make admin`, open `http://localhost:5173`, enter `local-dev-token`, and confirm the shell renders with the sidebar and the Dashboard shows crawl-status cards. (If the backend isn't running, the gate will show "Could not reach the backend" — that's expected.)

- [ ] **Step 10: Commit**

```bash
git add admin/src/components/AppShell.tsx admin/src/pages/Dashboard.tsx \
  admin/src/pages/Placeholder.tsx admin/src/router.tsx admin/src/main.tsx \
  admin/src/test/AppShell.test.tsx
git commit -m "feat(admin-ui): app shell, router, Dashboard wired to crawl status"
```

---

## Self-Review

**Spec coverage (spec §3 UI kit, §5 frontend structure, §7 styling, §8 dev workflow):**
- Vite + React + TS + Radix Themes scaffold → Task 1 ✓
- Ported app theme (exact tokens + Anton/Inter) → Task 1 (`tokens.css`, `index.html`) ✓
- API client injecting `X-Admin-Token` + base URL → Task 2 ✓
- TanStack Query provider + hook → Task 3 (`hooks.ts`), Task 4 (`main.tsx` provider) ✓
- TokenGate validated against a real endpoint → Task 3 ✓
- AppShell sidebar nav + Dashboard → Task 4 ✓
- Makefile `admin-install` / `admin` targets → Task 1 ✓
- Light tests (client, TokenGate, AppShell) + `tsc` build gate → Tasks 1–4 ✓

**Type consistency:** `apiFetch<T>`, `ApiError {status, code}`, `getToken/setToken/clearToken`, `CrawlStatus`, `useCrawlStatus` are defined once (Tasks 2–3) and consumed in Tasks 3–4. `TokenGate` validates with `apiFetch('/admin/crawl/status', { token })` using the `token` override added in Task 2's `FetchOpts`. The temporary `App.tsx`/`smoke.test.tsx` from Task 1 are explicitly removed in Task 4 so they don't linger.

**Open notes for the implementer:**
- `npm install` will generate `admin/package-lock.json` — commit it (Task 1 stages it). Do not commit `admin/node_modules` or `admin/dist` (gitignored).
- Radix Themes prop names (e.g. `<TextField.Root>`) are for v3; if the installed major differs, adapt the import/usage and note it.
- CORS: backend already allows all origins, so the dev server calls it directly. If CORS is ever locked down, add a Vite `server.proxy` for `/admin` and `/api`.

## Next plans in this series

3. **Fetch dashboard** — expand Dashboard with trigger buttons (bootstrap/crawl/refresh/circuits) over the existing admin POST routes, with toast + query invalidation; per-session re-fetch/re-score.
4. **Session result editing** — backend `PATCH/POST/DELETE /admin/sessions/:id/results...` + `SessionDetail` inline grid.
5. **Leagues admin** — backend cross-user league write routes + `Leagues`/`LeagueDetail`.
6. **Season management + remaining pages** — `Seasons`, drivers/constructors edit, users, predictions, standings, notifications.
