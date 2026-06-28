# Admin Tool — Plan 5: Leagues Admin

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans (inline execution chosen). Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cross-user league management for the admin tool — backend `X-Admin-Token` write endpoints (rename, set/clear password, regenerate join code, delete league, kick member) plus a `Leagues` list page and a `LeagueDetail` page with member management.

**Architecture:** Backend reuses the existing user-facing league patterns (`leaguesRepo`, `leagueMembersRepo`, `hashPassword`, `generateUniqueJoinCode`) but without owner-scoping — a token-gated `adminLeagues` route module. Reads already exist from Plan 1 (`GET /admin/leagues`, `GET /admin/leagues/:id`). Frontend adds two pages reusing the established hook/toast/AlertDialog patterns.

**Tech Stack:** Backend — Fastify, Drizzle, Zod, Vitest (real Postgres). Frontend — React, TS, Radix Themes, TanStack Query, Vitest+RTL+jsdom.

## Global Constraints

- **Concurrency:** another session may edit `backend/`/`lib/`/`admin/Dashboard.tsx`. NEVER `git add -A`/`.`/`commit -a`; stage only the exact paths each task names.
- Backend: ESM `.js` imports; errors via `ApiError`; repo layer only; token preHandler covers `/admin/*` (register on root app after `registerAdminSessionResultRoutes`); integration tests, admin token `'local-dev-token'`, `buildApp({ scheduler: null })` + `app.inject`. Postgres up; single-file test runs.
- Frontend: TS strict; build gate `npm run build`; tests `npm test`; no new deps; keep `className="display"`/`className="label"`; reuse `apiFetch`/`ApiError`, `useToast`, AlertDialog confirm pattern; tests that render Radix `Select`/overlay need a `<Theme>` wrapper.
- Existing types (Plan 1 backend): `AdminLeagueRow = { id, name, ownerUserId, ownerDisplayName, memberCount, joinCode, hasPassword, createdAt }`; `AdminMemberRow = { userId, displayName, email, role: 'owner'|'member', joinedAt }`. `GET /admin/leagues → { leagues }`, `GET /admin/leagues/:id → { league, members }`.

## File Structure

Backend:
- Create `backend/src/api/routes/adminLeagues.ts` — `registerAdminLeagueRoutes(app)`.
- Modify `backend/src/index.ts` — register it.
- Create `backend/test/integration/api_admin_leagues_write.test.ts`.

Frontend:
- Modify `admin/src/api/types.ts` — `AdminLeague`, `AdminLeagueMember`, `AdminLeagueDetail`.
- Create `admin/src/api/leagues.ts` — read + mutation hooks.
- Create `admin/src/pages/Leagues.tsx`, `admin/src/pages/LeagueDetail.tsx`.
- Modify `admin/src/router.tsx` — `/leagues` + `/leagues/:id`.
- Create `admin/src/test/Leagues.test.tsx`, `admin/src/test/LeagueDetail.test.tsx`.

---

### Task 1: Backend league write endpoints

`registerAdminLeagueRoutes(app)`:
- `PATCH /admin/leagues/:id` — body `{ name?: string (1..80), password?: string|null }`. 404 if league missing. `name` → `updateName`; `password` present → `null` clears, string (min 4) → `hashPassword` then `updatePasswordHash`. Returns `{ ok: true, league: AdminLeagueRow }` (re-read via `listAllWithMeta().find` or a `findById`-derived row — use `leaguesRepo.findById` + shape to AdminLeagueRow-lite `{ id, name, hasPassword, joinCode }`). Returns enough for the UI to refresh.
- `POST /admin/leagues/:id/regenerate-code` — 404 if missing; `generateUniqueJoinCode(c => findByJoinCode(c) !== null)`, `updateJoinCode`, returns `{ ok: true, joinCode }`.
- `DELETE /admin/leagues/:id` — 404 if missing; `deleteById`; `{ ok: true }`.
- `DELETE /admin/leagues/:id/members/:userId` — 404 if league missing; if `userId === league.ownerUserId` → `CONFLICT` ("Can't remove the owner — delete the league instead"); else `leagueMembersRepo.remove`; `{ ok: true }`.

Tests (`api_admin_leagues_write.test.ts`): token gate (401), rename, set+clear password (`hasPassword` reflects), regenerate code (changes), delete league (gone), kick member (member removed), kick-owner → 409, missing league → 404. Seed via `users.insertUser`, `leagues.createLeagueWithOwner`, `leagueMembers.add`.

Register in `index.ts` after `registerAdminSessionResultRoutes(app)`.

---

### Task 2: Frontend Leagues list page

- `types.ts`: `AdminLeague = { id, name, ownerUserId, ownerDisplayName, memberCount, joinCode, hasPassword, createdAt }`; `AdminLeagueMember = { userId, displayName, email, role: 'owner'|'member', joinedAt }`; `AdminLeagueDetail = { league: AdminLeague, members: AdminLeagueMember[] }`.
- `leagues.ts`: `useAdminLeagues()` (GET `/admin/leagues` → `.leagues`).
- `Leagues.tsx`: table — name (Link to `/leagues/:id`), owner display name, member count, password lock badge.
- Router: `/leagues` → `<Leagues/>`.
- Test: lists a league, name links to `/leagues/:id`.

---

### Task 3: Frontend LeagueDetail page + mutations

- `leagues.ts` mutations: `useAdminLeague(id)` (GET `/admin/leagues/:id`), `useUpdateLeague(id)` (PATCH name/password), `useRegenerateCode(id)` (POST), `useDeleteLeague()` (DELETE, navigates to `/leagues`), `useKickMember(id)` (DELETE member). All toast + invalidate `['admin-league', id]` / `['admin-leagues']`.
- `LeagueDetail.tsx`: shows name/join code/owner; an edit form (name + password set/clear); Regenerate code button; Delete league (AlertDialog confirm); members table with Kick (AlertDialog confirm) — owner row shows "owner", no kick button.
- Router: `/leagues/:id` → `<LeagueDetail/>`.
- Test: renders members; Kick on a member sends DELETE to `/admin/leagues/:id/members/:userId`; owner has no kick.

---

## Self-Review
- Reads (Plan 1) + writes (Task 1) cover the spec's league admin surface (rename, password, regenerate, delete, kick).
- Owner-kick guarded (409). Delete confirmed in UI. Token-gated.
- Query keys: `['admin-leagues']`, `['admin-league', id]` consistent across hooks.
