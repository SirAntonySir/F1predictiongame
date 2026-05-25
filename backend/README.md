# f1pg-backend

Node + Fastify + Postgres backend for the F1 Prediction Game. Crawls
Jolpica-F1 every 15 minutes and exposes a read-only HTTP API.

This is sub-project 1 of 5 in the rebuild. Subsequent sub-projects add
users/auth, scoring, the pre-season questionnaire, and the frontend redesign.

## Local development

Prereqs: Node 22+, Docker.

```bash
cp .env.example .env
docker compose up -d
npm install
npm run db:migrate

# Then either:
npm run dev           # auto-reload via tsx
# or:
npm run build && npm start
```

```bash
# Trigger a bootstrap to populate the current season schedule
curl -X POST -H "x-admin-token: local-dev-token" http://localhost:3000/admin/bootstrap

# Then browse the API
curl http://localhost:3000/api/health | jq
curl http://localhost:3000/api/seasons/current | jq
curl http://localhost:3000/api/events | jq
```

## Tests

```bash
docker compose up -d
npm test
```

Tests run against the local Postgres (port 5433). Each test truncates all
tables in `beforeEach`, so they share one DB. Single-fork by design — see
`vitest.config.ts`.

## Architecture

Single Node process. Fastify serves HTTP; `node-cron` runs the crawler in-process.

```
[ Node process ]
  ├── Fastify HTTP
  │     ├── /api/* (public read endpoints)
  │     └── /admin/* (token-gated)
  └── Scheduler
        ├── every 15 min: tick (fetch finished sessions, refresh standings)
        └── Mondays 03:00 UTC: weekly schedule refresh
```

Boundary rules:
- `api/` → `repo/` only (never `db/`, `jolpica/`, `crawler/` directly)
- `crawler/` → `jolpica/`, `wikipedia/`, `repo/`
- `repo/` → `db/` only
- `domain/` has zero imports

## API

Authenticated endpoints require `Authorization: Bearer <token>` where `<token>` comes from `/api/auth/signup` or `/api/auth/login`. Sessions slide a 90-day expiry on every request.

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/health` | DB up/down + last tick info |
| GET | `/api/seasons/current` | Current season metadata |
| GET | `/api/events` | All events in current season with their sessions |
| GET | `/api/events/:round` | Single event by round |
| GET | `/api/sessions/:id` | Session metadata |
| GET | `/api/sessions/:id/results` | Ordered classification for a session |
| GET | `/api/next-session` | Soonest scheduled session |
| GET | `/api/standings/drivers` | Current driver standings, with driver image |
| GET | `/api/standings/constructors` | Current constructor standings, with constructor image |
| GET | `/api/drivers/:code` | Driver lookup (image included) |
| GET | `/api/constructors/:id` | Constructor lookup (image included) |
| POST | `/api/auth/signup` | Create account, returns `{ user, token }` |
| POST | `/api/auth/login` | Login, returns `{ user, token }` |
| POST | `/api/auth/logout` | Revoke caller's session (bearer) |
| GET  | `/api/auth/me` | Current user + caller's leagues (bearer) |
| PATCH | `/api/auth/me` | Update display name (bearer) |
| POST | `/api/leagues` | Create caller's league (bearer, 1-per-user) |
| GET  | `/api/leagues/mine` | List leagues caller belongs to (bearer) |
| GET  | `/api/leagues/:id` | League + members; `joinCode` visible to owner only (bearer + member) |
| PATCH | `/api/leagues/:id` | Rename (bearer + owner) |
| POST | `/api/leagues/:id/regenerate-code` | New join code (bearer + owner) |
| DELETE | `/api/leagues/:id` | Delete league (bearer + owner) |
| POST | `/api/leagues/join` | Join via `{ joinCode }` (bearer) |
| DELETE | `/api/leagues/:id/members/me` | Leave league (bearer + member, not owner) |
| DELETE | `/api/leagues/:id/members/:userId` | Kick member (bearer + owner) |
| GET  | `/api/predictions/upcoming` | Caller's upcoming scorable sessions, with `myPicks` (bearer) |
| GET  | `/api/sessions/:id/my-prediction` | Caller's prediction for a session (bearer) |
| PUT  | `/api/sessions/:id/my-prediction` | Submit/replace caller's picks; 409 after lock (bearer) |
| DELETE | `/api/sessions/:id/my-prediction` | Remove caller's prediction; 409 after lock (bearer) |
| GET  | `/api/sessions/:id/predictions` | Everyone's picks; only after lock (bearer) |
| GET  | `/api/leagues/:id/leaderboard` | League leaderboard, sums of `score.points_total` (bearer + member) |
| GET  | `/api/leagues/:id/leaderboard/sessions` | Per-session per-member breakdown (bearer + member) |
| GET  | `/api/users/me/scores` | Caller's score history (bearer) |
| POST | `/admin/bootstrap` | Re-fetch schedule + populate season (token-gated, idempotent) |
| POST | `/admin/crawl` | Force an immediate tick (token-gated) |
| POST | `/admin/refresh-images` | Re-attempt Wikipedia fetch for null image URLs (token-gated) |
| POST | `/admin/rescore-session/:id` | Force rescore of one session (token-gated) |
| POST | `/admin/rescore-season/:year` | Rescore every finished session in a season (token-gated) |

Admin endpoints require `X-Admin-Token: <ADMIN_TOKEN>` header.

Drivers/constructors expose an `image` field equal to `imageUrlOverride ?? imageUrl`.
Both backing fields can be null — clients must degrade gracefully.

## Scoring

Per race weekend, four scorable session kinds:

| Kind | Picks | Per-position exact | Wrong position | Team bonus | Max |
|---|---|---|---|---|---|
| Qualifying | P1, P2 | 3 each | 1 each | +1 if pole pick's team matches pole | 7 |
| Sprint Shootout | P1 | 1 | — | +1 if P1 pick's team matches | 2 |
| Sprint Race | P1, P2, P3 | 2 each | 1 each | +1 if winning team correct | 7 |
| Race | P1–P5 | 3 each | 1 each | +2 if winning team correct | 17 |

Picks lock at the session's scheduled start. The crawler auto-rescores after writing
results, so FIA penalty updates flow through to scores automatically. Manual rescore
is available via the `/admin/rescore-*` endpoints.

## Deploy

`render.yaml` is a Render Blueprint. From the Render dashboard:

1. **New → Blueprint** → connect this repo.
2. Render creates Postgres + web service from the blueprint.
3. The `ADMIN_TOKEN` is auto-generated; copy it from the web service's
   Environment tab to call admin endpoints later.
4. After first deploy, hit `/admin/bootstrap` once to populate the current
   season schedule. The scheduler will take over from there.

⚠️ Render's free Postgres plan expires after 90 days. Upgrade or migrate before then.

## Known limitations

- **Sprint Qualifying** isn't a real Jolpica endpoint (HTTP 400 / 404). Sessions of
  type `sprint_quali` will never receive results until a source becomes available.
  Tick logs and retries until the 7-day cap.
- **Free Render Postgres** has a 90-day expiry. Plan for this.
- **Wikipedia images** are best-effort. Team logos in particular may be missing or
  low-quality; populate `image_url_override` manually if you want curated assets.

## What's NOT in this sub-project

Pre-season questionnaire, Flutter UI changes. Each gets its own sub-project in
subsequent rebuild cycles.
