# Admin Tool — Plan 6: Seasons, Users, Predictions pages

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans (inline). Steps use checkbox (`- [ ]`) syntax.

**Goal:** Fill three sidebar placeholders with real pages that reuse existing endpoints — **Seasons** (bootstrap / activate / rescore action buttons), **Users** (searchable list), **Predictions** (browse predictions for a session). Frontend-only; no backend changes.

**Architecture:** All endpoints already exist (Plan 1 admin reads + the original admin action routes). New hooks + pages + router entries; reuse `apiFetch`, `useToast`, `ActionButton`.

## Global Constraints
- **Concurrency:** another session may edit `admin/src/pages/Dashboard.tsx` + `admin/src/utils/`. NEVER `git add -A`/`.`/`commit -a`; stage only the exact paths.
- TS strict; build gate `npm run build`; tests `npm test`; no new deps; keep `className="display"`/`className="label"`; tests rendering Radix `Select`/overlay need a `<Theme>` wrapper.
- Existing endpoints: `GET /api/seasons → Season[]`; `POST /admin/bootstrap`; `POST /admin/seasons/:year/activate`; `POST /admin/rescore-season/:year`; `POST /admin/preseason-rescore/:year`; `GET /admin/users?query=&limit=&offset= → { users, total }` (`AdminUserRow = { id, email, displayName, createdAt, leagueCount }`); `GET /admin/predictions?sessionId=&userId=&leagueId= → { predictions }` (`AdminPredictionRow = { predictionId, userId, displayName, sessionId, source, updatedAt, picks: { position, driverCode }[] }`).
- `useSeasons()` already exists in `admin/src/api/sessions.ts`. `ActionButton` props: `{ label, path, method?, invalidateKeys?, successMessage }`.

## File Structure
- Modify `admin/src/api/types.ts` — `AdminUserRow`, `AdminPrediction`.
- Create `admin/src/api/admin.ts` — `useAdminUsers(query)`, `useAdminPredictions(filter)`.
- Create `admin/src/pages/Seasons.tsx`, `admin/src/pages/Users.tsx`, `admin/src/pages/Predictions.tsx`.
- Modify `admin/src/router.tsx` — wire the three.
- Create tests for each page.

---

### Task 1: Seasons page
- `Seasons.tsx`: `useSeasons()` → a Card per season (year + `current` badge), with `ActionButton`s: **Activate** (`/admin/seasons/:year/activate`, invalidate `['seasons']`), **Rescore season** (`/admin/rescore-season/:year`), **Preseason rescore** (`/admin/preseason-rescore/:year`). A top-level **Bootstrap current** button (`/admin/bootstrap`, invalidate `['seasons']`).
- Router `/seasons` → `<Seasons/>`.
- Test (with `<Theme>`): renders a season year + an Activate button.

### Task 2: Users page
- `types.ts`: `AdminUserRow`. `admin.ts`: `useAdminUsers(query: string)` → `GET /admin/users?query=...` → `{ users, total }`.
- `Users.tsx`: a search `TextField` (debounce not required — query on change), a table (display name, email, league count, created). 
- Router `/users` → `<Users/>`.
- Test: renders a user row from a mocked response; typing in search re-queries with `?query=`.

### Task 3: Predictions page
- `types.ts`: `AdminPrediction`. `admin.ts`: `useAdminPredictions(sessionId: string)` → `GET /admin/predictions?sessionId=...`, enabled when sessionId non-empty.
- `Predictions.tsx`: a `TextField` for a session id, a table of predictions (display name, source, picks rendered as `P1 VER · P2 LEC …`).
- Router `/predictions` → `<Predictions/>`.
- Test: with a session id entered, renders a prediction row.

## Self-Review
- Reuses existing endpoints only; no backend/deploy.
- Query keys: `['seasons']` (shared with Sessions page selector), `['admin-users', query]`, `['admin-predictions', sessionId]`.
