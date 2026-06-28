# Admin Tool — Design Spec

**Date:** 2026-06-28
**Status:** Approved (design); pending implementation plan
**Author:** Anton + Claude

## 1. Purpose

A web admin tool for the F1 Prediction Game, for the **developer (Anton) only**. It lets me:

- Browse the backend database tables (leagues, members, users, sessions, results, predictions, drivers, constructors, standings, crawl state).
- Monitor and **re-trigger data fetches** (Jolpica/OpenF1 crawler, bootstrap, refetch, refresh) with buttons.
- **Inline-edit / correct** key data that comes from the fetches (session results, driver/constructor metadata).
- See **leagues and members** with edit modes (rename, password, regenerate code, kick members, delete league).
- **Manage seasons** (bootstrap a calendar, activate the current season, rescore, set preseason subjective truth).

It is **styled to mirror the Flutter app** (dark surfaces, red accent, Anton/Inter type).

### Non-goals (YAGNI)

- No multi-user auth / roles / per-admin audit — it's a single-developer tool behind the shared admin token.
- No new per-event/session visibility flags or schema migrations for "visibility" — season management is **season-level only** (`season.is_current` + bootstrap).
- No heavy E2E test suite.
- Not deployed/public by default — local-first dev tool (can be pointed at prod with the prod token).

## 2. Context (existing system)

- **Backend:** `F1predictiongame/backend` — Fastify 5 + Drizzle ORM + PostgreSQL, TypeScript ESM, `tsx watch` dev on port 3000. CORS `origin: true`. Data ingested from **Jolpica** (Ergast successor) and **OpenF1**, plus Wikipedia images and a circuits SVG source.
- **Crawler:** scheduler runs a tick every minute (fetch finished session results, best laps, rescore), reconcile hourly (flip provisional OpenF1 rows to official Jolpica), weekly bootstrap, daily session sweep, per-minute notification dispatch.
- **Existing admin routes** (all gated by `X-Admin-Token`, middleware in `src/api/routes/admin.ts`):
  `POST /admin/bootstrap`, `/admin/crawl`, `/admin/refresh-images`, `/admin/refresh-openf1-metadata`,
  `/admin/rescore-session/:id`, `/admin/refetch-session/:id` (`?skipStandings=1&skipBestLaps=1`),
  `/admin/rescore-season/:year`, `/admin/circuits/sync`,
  `/admin/seasons/:year/subjective-truth`, `/admin/preseason-rescore/:year`,
  `/admin/seasons/:year/activate`, `/admin/notifications/broadcast`.
- **Auth:** admin = shared `ADMIN_TOKEN` env var, header `X-Admin-Token`. Users = bearer session tokens (blake2b-hashed in `app_session`). **No `is_admin` concept** on users.
- **Key tables** (from `src/db/schema.ts`): `season`, `event`, `session`, `session_result`, `driver`, `constructor`, `driver_standing`, `constructor_standing`, `circuit`, `circuit_svg`, `user`, `app_session`, `league`, `league_member`, `prediction`, `prediction_pick`, `prediction_import`, `score`, `preseason_*`, `subjective_truth`, `session_best_lap`, `device_token`, `notification_*`.

### Gaps the admin tool must fill

- Leagues/members are **user-scoped** in the app API (`GET /api/leagues/:id` needs membership); there is **no cross-user admin read** of all leagues, users, or predictions, and **no crawl-state read** beyond `/api/health`. → new per-resource admin read endpoints.
- There are **no field-level edit endpoints** — only whole-session refetch. To "correct data from the fetches" we need validated admin PATCH endpoints. → new inline-edit endpoints.

## 3. Architecture

Two coupled deliverables in the existing repo:

1. **`backend/` additions** — new `X-Admin-Token`-gated routes (per-resource reads + inline-edit writes), following the existing `admin.ts` + repo-layer patterns.
2. **`admin/` (new)** — Vite + React + TypeScript + Radix SPA, sibling of `backend/` and `lib/`.

**Decisions (approved):**

- **Read layer:** per-resource typed admin endpoints (not a generic table dumper).
- **Edit depth:** inline edit for key tables (`session_result`, `driver`, `constructor`, `league`/members) + reuse refetch/rescore.
- **Season management:** season-level only — bootstrap, activate, rescore, subjective truth. No new visibility schema.
- **Auth:** shared `X-Admin-Token`, entered once in the UI, stored in `localStorage`, sent on every admin call. Dev-only tool.
- **Location:** `admin/` folder in this repo.
- **UI kit:** **Radix Themes** (styled components) with a custom dark theme + red accent; drop to **Radix Primitives** where finer control is needed.
- **Data layer:** **TanStack Query** + a thin typed `fetch` client (injects base URL + token). Mutations invalidate the relevant queries so a triggered fetch refreshes the affected views.

## 4. Backend additions

All new routes live under `/admin/*`, reuse the existing `X-Admin-Token` preHandler, and use the repo layer (no raw SQL in handlers). All writes are Zod-validated, FK-safe, and return clear error codes. Where an edit changes scoring inputs, the handler triggers a rescore (or returns a flag so the UI can offer a "rescore now" button).

### 4.1 Reads (per-resource)

| Route | Returns |
|---|---|
| `GET /admin/leagues` | All leagues: `id, name, ownerUserId, ownerDisplayName, memberCount, joinCode, hasPassword, createdAt` |
| `GET /admin/leagues/:id` | League + members `[{ userId, displayName, email, role, joinedAt }]` + counts |
| `GET /admin/users?query=&limit=&offset=` | Paginated users: `id, email, displayName, createdAt, leagueCount` |
| `GET /admin/users/:id` | User detail: leagues, prediction count, score summary |
| `GET /admin/sessions?season=` | All sessions (all seasons if no param): `id, eventName, round, type, status, source, scheduledStart, lastReconciledAt` — the fetch-health view |
| `GET /admin/predictions?sessionId=&userId=&leagueId=` | Predictions + picks for the filter (at least one filter required) |
| `GET /admin/crawl/status` | Expands `/api/health`: `lastTickAt, lastTickStatus, pendingCandidates[], provisionalSessions[], recentlyReconciled[]` |

Existing public reads (`/api/events`, `/api/sessions/:id/results`, `/api/standings/*`, `/api/drivers/:code`, `/api/constructors/:id`, `/api/seasons`) are reused by the admin UI for non-privileged data.

### 4.2 Writes (inline edit + corrections)

| Route | Effect |
|---|---|
| `PATCH /admin/sessions/:id/results/:position` | Edit a `session_result` row (`driverCode, driverName, constructorId, constructorName, points, status, raceTime, q1, q2, q3`). Validates FK + position uniqueness. Optionally rescores. |
| `POST /admin/sessions/:id/results` / `DELETE /admin/sessions/:id/results/:position` | Add / remove a result row (for manual classification fixes). |
| `PATCH /admin/drivers/:code` | Edit `givenName, familyName, nationality, imageUrlOverride, headshotUrl`. |
| `PATCH /admin/constructors/:id` | Edit `name, nationality, teamColour, imageUrlOverride`. |
| `PATCH /admin/leagues/:id` | Cross-user: rename, set/clear password. |
| `DELETE /admin/leagues/:id` | Delete a league (cascades). |
| `DELETE /admin/leagues/:id/members/:userId` | Remove any member (admin, not owner-scoped). |
| `POST /admin/leagues/:id/regenerate-code` | New join code. |

### 4.3 Reused as-is (buttons only)

`bootstrap`, `crawl`, `refetch-session/:id`, `rescore-session/:id`, `rescore-season/:year`, `seasons/:year/activate`, `seasons/:year/subjective-truth`, `preseason-rescore/:year`, `refresh-images`, `refresh-openf1-metadata`, `circuits/sync`, `notifications/broadcast`.

## 5. Frontend structure

```
admin/
  src/
    api/
      client.ts        # fetch wrapper: base URL + X-Admin-Token, error normalisation
      types.ts         # TS types mirroring backend responses
      hooks/           # TanStack Query hooks per resource (useLeagues, useSession, mutations)
    theme/
      tokens.css       # ported app palette + fonts as CSS variables
      theme.ts         # Radix Themes config (dark, red accent, radius)
    components/
      AppShell.tsx     # sidebar nav + header
      DataTable.tsx    # sortable/filterable table (Radix Table)
      EditDialog.tsx   # generic edit form in a Radix Dialog
      ActionButton.tsx # async button: pending/spinner, toast on result/error, query invalidation
      StatusBadge.tsx  # provisional/final/scheduled/finished pills
      TokenGate.tsx    # asks for ADMIN_TOKEN, validates against /admin/crawl/status
      Toaster.tsx      # Radix Toast host (mirrors app BrandedToast tone)
    pages/
      Dashboard.tsx        # crawl health + fetch control panel
      Seasons.tsx          # list + bootstrap/activate/rescore/subjective-truth
      Events.tsx           # season -> events -> sessions tree
      SessionDetail.tsx    # result grid (inline edit) + refetch/rescore
      Drivers.tsx / Constructors.tsx
      Standings.tsx
      Leagues.tsx / LeagueDetail.tsx
      Users.tsx
      Predictions.tsx
      Notifications.tsx    # broadcast composer
    router.tsx
    main.tsx
  index.html
  vite.config.ts
  package.json
  tsconfig.json
```

## 6. Feature → screen mapping

- **Tables browser:** each resource is a `DataTable` page; editable tables open `EditDialog`.
- **Fetches / Dashboard:** `/admin/crawl/status` health summary + a control panel of `ActionButton`s (bootstrap, crawl, refresh-images, refresh-openf1-metadata, circuits/sync). Each shows the JSON result/errors in a toast and invalidates affected queries. Per-session **Re-fetch** / **Re-score** buttons live on `SessionDetail`.
- **Data correction:** `SessionDetail` renders the `session_result` grid inline-editable; a `StatusBadge` shows provisional (`source=openf1`, `lastReconciledAt` null) vs final (`jolpica`/reconciled).
- **Leagues & members:** `Leagues` list → `LeagueDetail` with a member table (kick, view picks via predictions filter), edit name/password, regenerate code, delete.
- **Season management:** `Seasons` page lists seasons with an `is_current` badge and buttons: **Bootstrap**, **Activate (make current)**, **Rescore season**, **Preseason rescore**, and a **Subjective truth** editor (surprise/disappointment driver+constructor).
- **Notifications:** broadcast composer (title/body/route) → `POST /admin/notifications/broadcast`.

## 7. Styling (mirror the app)

Port `lib/theme/colors.dart`, `tokens.dart`, `typography.dart` into `tokens.css` variables:

- Surfaces: `--surface: #0E0E10`, `--surface-muted: #16161A`, `--stroke: #2A2A2E`.
- Text: `--on-surface: #F2F2F2`, `--on-surface-muted: #9A9A9E`.
- Accent: `--accent: #E10600` (red), `--ok: #19D36B`, `--near: #FFD233`, `--violet: #B147FF`.
- Radii: 14px (cards), pill for chips. Card stroke: 2px solid `--stroke`.
- Type: **Anton** (Google Font) for headings/numbers with tight tracking; **Inter** for body (500) and **labels** (800, uppercase, letter-spaced 1.5–2). Loaded via Google Fonts (`@fontsource` or `<link>`).

Radix Themes configured: `appearance="dark"`, `accentColor="red"`, `radius="medium"`, `panelBackground` tuned to the surfaces above; components overridden with the CSS variables so cards/tables/dialogs read like `AppCard`/`Slot`.

## 8. Dev workflow & testing

- **Makefile targets:** `admin-install` (`cd admin && npm install`), `admin` (`cd admin && npm run dev`). Vite reads `VITE_API_URL` (default `http://localhost:3000`, matching the Makefile's `API_URL`). Token entered in the UI, not baked into the build.
- **Backend tests (vitest, under `make backend-test`):** new endpoints — auth gate (401 without token), validation (bad FK / duplicate position → 4xx), result edit triggers rescore, league cross-user edit/kick/delete, read pagination/filters.
- **Frontend tests:** light — typecheck (`tsc --noEmit`) + a couple of component tests (`TokenGate` gating, `DataTable` render). No E2E.

## 9. Build order (incremental slices)

1. Backend read endpoints (`/admin/leagues`, `/admin/users`, `/admin/sessions`, `/admin/predictions`, `/admin/crawl/status`) + their vitest.
2. Admin app scaffold: Vite/React/TS, Radix theme + ported tokens, `AppShell`, `TokenGate`, API client, TanStack Query.
3. Dashboard: crawl health + fetch control panel (wire existing trigger routes).
4. Session result editing: backend PATCH/POST/DELETE result routes + `SessionDetail` inline grid.
5. Leagues: backend admin league write routes + `Leagues`/`LeagueDetail`.
6. Season management: `Seasons` page over existing bootstrap/activate/rescore/subjective-truth.
7. Drivers/Constructors edit, Users, Predictions, Standings, Notifications pages.

## 10. Risks & notes

- **CORS:** backend already allows all origins, so the Vite dev server can call it directly; no proxy strictly required (can add a Vite proxy if we later lock CORS down).
- **Rescore side-effects:** editing a `session_result` row changes user scores — handlers must rescore (or clearly offer it) so leaderboards stay consistent. Tests must cover this.
- **Token in localStorage:** acceptable for a personal dev tool; documented as such. If the tool is ever deployed, revisit (the prod admin token would be exposed to that browser).
- **Denormalised columns:** `session_result` carries `driver_name`/`constructor_name` alongside FKs — edit endpoints should keep them consistent.
