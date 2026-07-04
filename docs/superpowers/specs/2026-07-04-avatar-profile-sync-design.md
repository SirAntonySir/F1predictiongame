# Avatar on Profile & Leaderboard — Design

## Goal

Show each user's customized driver avatar to *other* users: as a circular
head-crop in the player detail screen header and as a small thumbnail in the
league leaderboard rows (and top-3 podium). This requires persisting the
avatar to the user's profile in the database, since today it lives only in
local `SharedPreferences` on the owner's device.

## Context

The avatar is rendered entirely client-side. `AvatarConfig` (preset id +
per-region color overrides + pose + icon variant) is a small JSON blob; the
recolor engine (`lib/avatar/avatar_palette.dart`) plus the bundled pose SVGs
turn it into artwork. So the backend only needs to **store and serve the
config JSON** — every client can render any user's avatar from bundled
assets. No image storage, no server-side rendering.

Current state:
- `user` table (`backend/src/db/schema.ts`) has `displayName`, no avatar.
- `AvatarController` (`lib/state/avatar_controller.dart`) is local-only
  SharedPreferences, keyed by a single global key, never user-scoped, and
  never synced to the backend.
- The frontend never calls `PATCH /api/auth/me` — display name is read-only
  in settings. Avatar sync is this endpoint's first frontend consumer.
- Player detail is one composite endpoint
  (`GET /api/leagues/:leagueId/players/:userId`, `players.ts`) returning a
  `player` object.
- The league leaderboard comes from `leagueLeaderboard()` raw SQL in
  `repo/scores.ts`, rendered via `LeagueRow` (`lib/components/league_row.dart`)
  inside `lib/screens/standings/league_tab.dart`.

## Decisions (from brainstorming)

- **Render style:** circular head crop (helmet + shoulders), not full figure.
- **Scope:** player detail header + league leaderboard rows/podium only.
  Home, search, and session-results rows stay text-only (future work).
- **Storage:** opaque JSON string on the `user` row. Backend validates it is
  parseable JSON under a size cap; it never introspects the contents.
- **Null = default:** a user who never customized has `null`. The client
  renders `null` as the default livery (`AvatarConfig.fromJson(null)` yields
  Undercut/pose-1), so every surface shows an avatar; no initials fallback.
- **Sync model:** server is the source of truth across devices; seed from
  local once for existing users.

## Backend

### Migration + schema
- New Drizzle migration adds nullable `avatar_config text` to `user`.
- `schema.ts`: `avatarConfig: text('avatar_config')`.
- `domain/types.ts` `User` gains `avatarConfig: string | null`; `repo/users.ts`
  `toUser()` maps it.

### Repo
- `repo/users.ts`: add `updateAvatarConfig(id, json: string): Promise<User>`
  (mirrors `updateDisplayName`).

### Routes
- `auth.ts`:
  - `patchMeBody` gains `avatar: z.string().max(2000).optional()`, validated
    to be parseable JSON (a `.refine(s => tryJsonParse(s))`). An explicit
    empty-string or `null` is **not** accepted here; clearing is out of scope
    (a user always has at least the default config once they've saved).
  - `PATCH /api/auth/me` handler: if `body.avatar !== undefined`, call
    `updateAvatarConfig`.
  - `publicUser()` returns `avatar: u.avatarConfig` — so `/me`, signup, and
    login responses all carry it.
- `players.ts`: add `avatar_config` to the membership select; return
  `player.avatar = membership.avatarConfig ?? null`.
- `repo/scores.ts` `leagueLeaderboard`: add `u.avatar_config AS "avatarConfig"`
  to the SELECT and `u.avatar_config` to GROUP BY; `LeaderboardRow` type gains
  `avatarConfig: string | null`.

### Validation helper
A tiny `isValidAvatarJson(s: string): boolean` (JSON.parse in try/catch,
returns boolean) lives with the auth route or a shared util. The cap (2000)
is generous: a fully-custom config with 9 region overrides serializes to a
few hundred bytes.

## Frontend

### Models
- `User` (`api/models/user.dart`): add `final String? avatar;` parsed from
  `j['avatar']`.
- `PlayerHeader` (`api/models/player_profile.dart`): add
  `final String? avatarConfig;` from `j['avatar']`.
- `LeaderboardRow` (`api/models/leaderboard_row.dart`): add
  `final String? avatarConfig;` from `j['avatarConfig']`.

### API client
- `ApiClient` / `HttpApiClient`: add
  `Future<User> patchMe({String? displayName, String? avatar})` hitting
  `PATCH /api/auth/me`, returning the updated user. (displayName included now
  for symmetry / future settings use; only `avatar` is wired this pass.)

### Controller sync (`AvatarController` + `AuthController`)
`AvatarController` needs API + auth access to push. Wiring mirrors how other
controllers get the client (assigned in `main.dart`).
- **On save** (`_save`, reached by the builder's SAVE): persist to
  SharedPreferences as today, then best-effort `api.patchMe(avatar: json)`.
  A network failure is swallowed (local save still succeeds; next successful
  sync reconciles).
- **On login/bootstrap** (in `AuthController` after `me()` resolves):
  - server `avatar != null` → load it into `AvatarController` (overwrite local
    cache; server wins).
  - server `avatar == null` **and** the local config differs from a
    freshly-constructed default → push local up once (`patchMe`) so existing
    users' avatars migrate. "Differs from default" is a whole-config compare
    (`config.toJson() != const AvatarConfig().toJson()`), which catches a
    non-default preset even with no per-region overrides — not just
    `isCustom`.
- SharedPreferences remains the fast/offline boot cache the splash reads
  directly; server sync layers on top.

### Rendering — `AvatarThumbnail` (new)
One reusable widget, circular head crop, used by both surfaces.
- Input: `String? configJson`, `double size`.
- Because a leaderboard has many rows and pose SVGs are thousands of paths,
  it **rasterizes once to a `ui.Image` and caches** keyed by
  `(pose, configJson, sizePx)`. The parsed `SplashArt` per pose asset is also
  memoized (parse once per pose, not per widget).
- While the first render resolves (async), show a neutral disc placeholder.
- Per-pose "portrait" crop rect frames helmet + shoulders. Pose-1's rect is
  already measured (the app-icon bake: side 1199.4 at (130.4, -85.2)). Pose-2
  and pose-3 need a quick measured crop (throwaway render tool, same method as
  the icon bake, deleted after).
- Rendering path reuses `SplashArt.parse` + `recolorArt` + `debugPaintSplashArt`
  (or an equivalent static paint) from `painted_splash.dart`.

### UI placement
- **Player detail header** (`lib/screens/player_screen.dart`): insert an
  `AvatarThumbnail(configJson: p.player.avatarConfig, size: ~44)` between the
  back button and the name in the header Row.
- **`LeagueRow`** (`lib/components/league_row.dart`): add optional
  `String? avatarConfig`; render a small (~28) circular `AvatarThumbnail`
  between the rank column and the name column. `league_tab.dart` passes
  `r.avatarConfig`. The podium (`_PodiumStep`) reuses the same widget.

## Testing

### Backend (extend existing integration suites)
- `PATCH /api/auth/me` with a valid avatar persists it and returns it;
  invalid JSON → 400; oversize → 400 (extend `api_auth.test.ts`).
- `/api/auth/me` response includes `avatar` after a set.
- Player profile endpoint returns `player.avatar` (extend players test).
- `leagueLeaderboard` rows include `avatarConfig` (extend a scores/leaderboard
  repo or route test).
- Backend tests run via `make backend-test` (env sourced by the Makefile).

### Frontend
- Model round-trips: `User.avatar`, `PlayerHeader.avatarConfig`,
  `LeaderboardRow.avatarConfig` parse present/absent JSON.
- `AvatarThumbnail`: renders for a given config, reuses the cache on a second
  build with the same key, handles `null` (default livery).
- Controller sync via a fake `ApiClient`: save pushes `patchMe`; bootstrap
  adopts a server avatar; bootstrap with server-null + local-custom seeds up.

## Scope boundaries (YAGNI)

- Only the player detail header and league leaderboard rows/podium.
- No new avatar endpoint; reuse `PATCH /api/auth/me` and existing reads.
- No server-side image rendering; client renders from bundled assets.
- No avatar history, no per-league avatars, no clearing-to-null flow.
- Home leaderboard, search results, and session-results member rows unchanged.

## Migration / rollout notes

- Existing users are `null` until they save or until seed-from-local pushes
  their current local avatar up on next login. Expect many identical default
  (Undercut) avatars at first; this is intended.
- The stored blob is the exact `AvatarConfig.toJson()` string, including the
  `icon` (app-icon variant) and `pose` fields. `icon` is irrelevant to other
  viewers but harmless to store; `pose` drives which crop/pose renders.
