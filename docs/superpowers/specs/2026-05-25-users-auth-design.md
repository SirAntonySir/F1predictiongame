# Users, Auth & Leagues — Design

**Date:** 2026-05-25
**Status:** Approved (pending user review of this document)
**Sub-project:** 2 of 5 in the F1 Prediction Game rebuild

## Context

Sub-project 1 stood up the read-only data foundation: F1 schedule, sessions, results, standings, crawled from Jolpica-F1. The backend has no concept of a user. Every read endpoint is anonymous and every write endpoint is gated by a single static admin token.

This sub-project adds the identity layer the rest of the rebuild depends on. Without users, predictions cannot be associated with anyone, scoring cannot exist, and the pre-season questionnaire has nowhere to store answers.

It is deliberately scoped to identity + grouping. Predictions, scoring, and the questionnaire are separate sub-projects.

## Goal

Add user accounts, sessions, and a lightweight "leagues" concept to the existing Fastify backend, in the same architectural shape as sub-project 1 (`api → repo → db`, single Node process, Postgres only, no new infra). The Flutter app (being rebuilt in parallel) should be able to support signup → login → create-or-join-a-league → see fellow members against this backend with no other backend work required.

## Decisions

| # | Decision | Rationale |
|---|---|---|
| D1 | **Signup model:** open signup, gated per-league by a join code | App is intended to grow beyond the original friend group, but participation is always within an invite-bounded league. |
| D2 | **Auth method:** email + password (bcrypt), designed so OAuth identities can be attached later | Lowest infra now (no SMTP/OAuth provider), and the user table doesn't have to be rebuilt when OAuth is added. |
| D3 | **Session model:** opaque random token, stored as `sha256(token)` in an `app_session` table | Revocable, simple mental model, no JWT key management. Matches scale. |
| D4 | **Leagues:** multiple leagues; each user can own at most one and be a member of many | Matches "Anton's league," "Lukas's league," etc. without modeling org structure. |
| D5 | **Identity fields:** email, password hash, display name | Anything else (avatar, country, favorite driver) deferred to later sub-projects or to the questionnaire. |
| D6 | **Email verification & password reset:** out of scope this sub-project | Both require SMTP. Add as a focused later sub-project when SMTP lands. |
| D7 | **Rate limiting on login/signup:** out of scope this sub-project | Acceptable for a small private app; revisit before public launch. |
| D8 | **No new top-level architecture** — new tables, new repos, new route files, one new leaf module (`src/auth/`) | Slot into the existing layering. No new services, queues, caches. |

## Architecture

```
[ Node process — unchanged shape ]
  ├── Fastify HTTP
  │     ├── /api/*           (public read endpoints from sub-project 1)
  │     ├── /api/auth/*      (NEW — signup/login public, me/logout authenticated)
  │     ├── /api/leagues/*   (NEW — all authenticated)
  │     └── /admin/*         (token-gated, unchanged)
  └── Scheduler
        ├── every 15 min: tick (unchanged)
        ├── Mondays 03:00 UTC: weekly schedule refresh (unchanged)
        └── daily 04:00 UTC:   expired-session sweep (NEW)
```

**Boundary rules** extend cleanly from sub-project 1:

- `api/` → `repo/` only.
- `auth/` is leaf-level. No imports from `repo/` or `api/`. Pure functions: password hashing, token generation, join-code generation.
- `repo/` → `db/` only.
- New repo files (`users`, `appSessions`, `leagues`, `leagueMembers`) follow the existing pattern: thin SQL wrappers returning domain types.

## Entity model

Four new tables; all sub-project 1 tables are untouched.

```
user                           app_session
────                           ───────────
id            uuid PK          id              uuid PK   (never sent to client)
email         citext UQ        user_id         uuid FK → user(id) ON DELETE CASCADE
password_hash text             token_hash      bytea UQ  (sha256(token); raw token only in login response)
display_name  text             created_at      timestamptz
created_at    timestamptz      last_used_at    timestamptz
updated_at    timestamptz      expires_at      timestamptz   (90d sliding)
                               user_agent      text NULL
                               INDEX (user_id)
                               INDEX (expires_at)

league                         league_member
──────                         ─────────────
id            uuid PK          league_id   uuid FK → league(id) ON DELETE CASCADE
owner_user_id uuid UQ FK       user_id     uuid FK → user(id)  ON DELETE CASCADE
              → user(id)       joined_at   timestamptz
              ON DELETE CASCADE PK (league_id, user_id)
name          text             INDEX (user_id)
join_code     text UQ          (6-char [A-Z0-9])
created_at    timestamptz
```

**Key choices:**

- **`citext` email** avoids case-folding bugs at every query site. Requires the `citext` extension; enabled in migration `0002`.
- **`gen_random_uuid()`** needs the `pgcrypto` extension; enabled in the same migration.
- **Token never stored in plaintext.** The raw 32-byte token (base64url, ~43 chars) is returned exactly once in the signup/login response. The DB only holds `sha256(token)`. If the DB leaks, sessions are not directly resumable.
- **Sliding expiry.** Every authenticated request sets `expires_at = now() + 90d`. Write-per-request is acceptable at this scale. If it ever shows up in profiling, easy mitigation is "only slide when `expires_at - now() < 80d`" — single-line change. Documented knob, not solved now.
- **`league.owner_user_id` is unique** — that's how "one league per user" is enforced.
- **Owner is also a member.** League creation inserts a `league_member` row in the same transaction so leaderboard queries don't need a special case.

## API surface

### Auth

| Method | Path | Auth | Notes |
|---|---|---|---|
| POST | `/api/auth/signup` | none | `{ email, password, displayName }` → `{ user, token }` (auto-login) |
| POST | `/api/auth/login` | none | `{ email, password }` → `{ user, token }` |
| POST | `/api/auth/logout` | bearer | Deletes the caller's session row |
| GET | `/api/auth/me` | bearer | `{ user, leagues: [...minimal refs...] }` — convenience for app boot |
| PATCH | `/api/auth/me` | bearer | `{ displayName? }`. Password change is a separate future endpoint. |

### Leagues

| Method | Path | Auth | Notes |
|---|---|---|---|
| POST | `/api/leagues` | bearer | `{ name }` → creates league owned by caller. `409 CONFLICT` if caller already owns one. Owner auto-added as member. |
| GET | `/api/leagues/mine` | bearer | All leagues caller belongs to, each with `role: 'owner' \| 'member'`. |
| GET | `/api/leagues/:id` | bearer + member | League details + member list. `403 FORBIDDEN` if not a member. |
| PATCH | `/api/leagues/:id` | bearer + owner | `{ name? }`. |
| POST | `/api/leagues/:id/regenerate-code` | bearer + owner | Returns `{ joinCode }`. Old code invalidated. |
| DELETE | `/api/leagues/:id` | bearer + owner | Cascades members. |
| POST | `/api/leagues/join` | bearer | `{ joinCode }` → adds caller as member. 404 unknown, 409 already a member or own league. |
| DELETE | `/api/leagues/:id/members/me` | bearer + member (not owner) | Leave. Owner must `DELETE /api/leagues/:id` instead. |
| DELETE | `/api/leagues/:id/members/:userId` | bearer + owner | Kick a member. 400 if `:userId` is the owner. |

### Response shapes

- `user` = `{ id, email, displayName, createdAt }`. Password hash never exposed.
- `league` = `{ id, name, ownerUserId, memberCount, createdAt }`. `joinCode` only included when the caller is the owner.
- `leagueMember` = `{ userId, displayName, role, joinedAt }`.

### Validation

zod schemas per body. Email lowercased + trimmed before insert. Password `min(8)` — length-only, no symbol/case rules. Display name 1–40 chars. Join code is server-generated; never accepted from client on create.

## Request handling & authorization

**Token transport.** `Authorization: Bearer <token>` on every authenticated request.

**Auth `preHandler` hook,** registered on `/api/auth/*` (skipping signup/login) and the whole `/api/leagues/*` subtree:

```
1. Read Authorization header → 401 UNAUTHORIZED if missing/malformed
2. Compute sha256(token) → look up app_session by token_hash
3. If not found → 401
4. If expires_at < now() → delete row, 401
5. Slide expiry: UPDATE app_session SET last_used_at=now(), expires_at=now()+90d
6. Load user → attach to req.user (Fastify decorator + module augmentation
   declared in src/api/auth-context.ts)
```

**League authorization** is layered on top, not a hook (needs the route's `:id` param): two small helpers `requireLeagueMember(leagueId)` and `requireLeagueOwner(leagueId)` are called at the top of the handler and throw `ApiError('FORBIDDEN', …)` on failure.

**Login response message.** Unknown-email and wrong-password both return the same `UNAUTHORIZED` with message "Invalid email or password" so the API doesn't leak which emails are registered.

**Logout** deletes only the session row corresponding to the presented token. Global "log out everywhere" is not in this sub-project (future: `DELETE /api/auth/sessions`).

**Session sweeper.** A daily job added to the existing `Scheduler` (no new infra): `DELETE FROM app_session WHERE expires_at < now()`. Implementation lives in `src/auth/sweeper.ts` and is wired from `src/crawler/scheduler.ts`.

**CORS.** Already `origin: true` in `src/index.ts`. No change.

## Errors

Three new codes added to the existing `ApiError` union:

| Code | Status | Used for |
|---|---|---|
| `FORBIDDEN` | 403 | Authenticated but not allowed |
| `CONFLICT` | 409 | Duplicate email, second-league attempt, already-member, kicking the owner |
| `VALIDATION` | 422 | zod parse failure on a request body (distinct from `BAD_REQUEST` which stays for malformed path/query params) |

`UNAUTHORIZED` (already 401) is reused for missing/invalid/expired tokens and login failure.

Error bodies keep the existing shape: `{ error: { code, message } }`. zod failures collapse to a single human-readable message in the first cut. Field-keyed errors are a non-breaking additive change if the UI later wants them.

## Code layout

```
backend/src/
  auth/                  NEW
    password.ts          bcrypt wrappers (hash, verify)
    tokens.ts            random token gen, sha256
    joinCodes.ts         6-char [A-Z0-9] generator with collision retry
    sweeper.ts           daily expired-session cleanup
  api/
    auth-context.ts      NEW — Fastify req.user decorator + module augmentation
    routes/
      auth.ts            NEW
      leagues.ts         NEW
  repo/
    users.ts             NEW
    appSessions.ts       NEW
    leagues.ts           NEW
    leagueMembers.ts     NEW
  db/
    schema.ts            EXTEND — add 4 tables
    migrations/
      0002_users_auth.sql   NEW — extensions + 4 tables + indexes
```

`src/index.ts` registers the two new route groups alongside the existing ones, and `Scheduler` gains one extra `cron.schedule` call.

## Testing

Following sub-project 1's conventions in `vitest.config.ts`: single-fork, real Postgres on port 5433, truncate-all-tables in `beforeEach`.

**Repo layer** (`test/repo/*.test.ts`): one file per new repo. CRUD round-trips, unique constraints (duplicate email, one-league-per-owner), cascade deletes, lookup-by-token-hash.

**Auth primitives** (`test/auth/*.test.ts`): pure-function tests for `password.ts`, `tokens.ts`, `joinCodes.ts`. No DB.

**Route layer** (`test/api/auth.test.ts`, `test/api/leagues.test.ts`): build the full Fastify app via the existing `buildApp` helper, hit it via `app.inject`. Highest value — covers the preHandler hook, error mapping, end-to-end flows:

- signup → login → me → logout, with token correctness at each step
- expired/invalid/missing token → 401
- duplicate email → 409
- non-owner mutating league → 403
- join-code lifecycle: create league, join, regenerate, old code rejected
- kick member, leave league, owner-cannot-leave

**Test data builders.** New `test/helpers/factories.ts` with `makeUser(overrides?)`, `makeLeague(ownerId, overrides?)`. Keeps tests terse once auth is in the picture.

**Out of scope for tests:** load testing, asserting the sweeper's cron schedule itself (the underlying delete function is tested directly).

## What's explicitly NOT in this sub-project

- Email verification, password reset (need SMTP)
- OAuth providers
- Rate limiting on `/login` and `/signup`
- "Sessions list / revoke other devices" UI
- Predictions, scoring, pre-season questionnaire (their own sub-projects)
- Any Flutter changes — the Flutter rebuild is its own sub-project, happening in parallel
