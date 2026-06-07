# Live in-progress race ticker — design spec

- **Date:** 2026-06-07
- **Status:** Approved (design), pending implementation plan
- **Scope:** Feature 1 only — a live running-order ticker with projected points that replaces the "next session" view while a scorable session is in progress.

> **Revision 2026-06-07 (post-design):** Projection moved **server-side**. The frontend Dart scorer
> (`lib/domain/scoring.dart` — 8/4/0, no team bonus) does **not** match the backend rules (race 3/1/+2,
> quali 3/1/+1, sprint 2/1/+1, shootout 1/0/+1), so on-device projection would not equal the official
> score. Therefore **§5.2 / §5.4 / §5.5 are superseded**: `GET /api/sessions/:id/live` is
> **authenticated** and returns the live `order` **plus** `myProjected` (the caller) and `leagueProjected`
> (each league member), all computed by the **backend** scoring engine using the live order as the
> finishers. The app renders these directly — no client-side scoring. The divergent Dart fallback scorer
> is tracked as a separate cleanup task.

## 1. Goal

While a **scorable session is running** (race / qualifying / sprint / sprint-shootout), stop showing the
"next" session/countdown and instead show the **live running order**, the user's **projected points**, and
**each league member's projected points**, rendered with the **same colored rows** used after a session
finishes. The view persists through the post-session "provisional" gap and ends the moment the backend has
ingested official results and scored the session.

This fixes a concrete current bug: while a session is live it is already locked (`scheduledStart` has
passed), so `GET /api/next-session` returns the session *after* the running one — the app advertises the
"next" race while a race is on track.

## 2. Out of scope (separate specs)

- All notification work: the backend push platform, the "scores are done" push (Feature 2), migrating
  pick-reminders to the backend, and custom/admin notifications.
- Real-time streaming / websockets (we poll).
- Android-specific polish (development targets iOS; nothing here should break other platforms).
- The Postgres free-tier expiry (Render free Postgres is deleted ~30 days after creation + a 14-day
  grace period) — a separate, more urgent infra decision: keeping prod on free will lose data.

## 3. Decisions (from brainstorming)

1. **Full live ticker** backed by OpenF1 live data (not a placeholder).
2. **All scorable sessions** get it: race, qualifying, sprint, sprint-shootout. Race/sprint live position =
   true running order; quali/shootout live "position" = timing-screen order by best lap (noisier, labeled
   provisional).
3. Surfaces: **Home hero card** and the **session results screen** (the one that also shows league picks).
4. Projections cover **me and every league member**, computed **on-device** with the existing
   `domain/scoring.dart` `scoreSession`.
5. Backend serves live data **on-demand with a short server-side cache** (no background worker).
6. Infra: Render web service moves to an **always-on** plan (folded into this feature).

## 4. Current-state facts this design relies on

- **Client-side scoring already exists and is trusted.** `lib/domain/scoring.dart` exposes
  `scoreSession(SessionType, List<String> picks, List<SessionResult>)` and is already used as the fallback
  in [session_results_screen.dart](../../../lib/screens/session_results_screen.dart) (`_score()`, ~line 382)
  when the backend score is absent. `outcomeFor(...)`, `requiredPicks(...)`, and `PickOutcome` live in
  `lib/domain/prediction.dart`.
- **Colored rows + member tickets render from `List<SessionResult>` + picks.** The "FULL CLASSIFICATION"
  block, row tint (`BrandColors.ok` exact / `BrandColors.near` in-top-N / `t.rowHighlight` miss), team-color
  stripe `teamColor(constructorId)` (`lib/theme/team_colors.dart`), `_YourScoreTicket`, and `_MemberPickTicket`
  are all driven by the `SessionResult` shape + pick lists.
- **League picks are available during a live session.** `leagueSessionPredictions(...)` returns members'
  picks once `sessionLocked` is true, which it is from `scheduledStart` onward. Member `pointsTotal` will be
  null during live (backend hasn't scored) → we compute projected points on-device.
- **No live data today.** The OpenF1 client ([backend/src/openf1/client.ts](../../../backend/src/openf1/client.ts))
  wraps only `/sessions`, `/drivers`, `/session_result`, all used post-hoc. Results are ingested ~30 min after
  `scheduledEnd` by the 15-min crawler, which then scores. Session status is only `scheduled | finished` —
  there is no "live" status.
- **`session.openf1SessionKey`** exists (nullable) on the session model/row and is used for sprint-shootout
  and cross-check today.
- **Render is on the free tier** ([render.yaml](../../../render.yaml)): the web service sleeps after ~15 min
  idle, so on-demand OpenF1 fetches would cold-start 30–60s.

## 5. Architecture

### 5.1 Infra prerequisite (A)

- [render.yaml](../../../render.yaml): web service `plan: free → starter` (no spin-down). Eliminates the
  cold-start on the first live poll and makes the in-process crawler/cron reliable. ~$7/mo.

### 5.2 Backend — live endpoint

**Route:** `GET /api/sessions/:id/live` — public (consistent with `GET /api/sessions/:id/results`).
Add to [backend/src/api/routes/public.ts](../../../backend/src/api/routes/public.ts) (or a new `live.ts`).

**Response:**

```jsonc
{
  "sessionId": 123,
  "state": "live",            // pre | live | provisional | final | unavailable
  "asOf": "2026-06-07T14:32:10Z",
  "order": [
    {
      "position": 1,
      "driverCode": "VER",
      "driverName": "Max Verstappen",
      "constructorId": "red_bull",
      "constructorName": "Red Bull",
      "status": "ok",          // best-effort; "dnf"/"dns"/"dsq" when known
      "raceTime": "+4.512"      // gap-to-leader if intervals available, else null
    }
  ]
}
```

`order` entries match the JSON the app already parses into `SessionResult`, so the existing model and the
colored-row rendering work unchanged. `points`/`fastestLap`/`q1..q3` are omitted/null for live (prediction
points are computed client-side; `points` here is championship points, irrelevant live).

**`state` semantics:**

| state | meaning | client behavior |
|---|---|---|
| `pre` | session started by clock but OpenF1 has no/empty order yet (formation, pre-grid) | "Race starting…" |
| `live` | order flowing | live ticker |
| `provisional` | `now ≥ scheduledEnd`, official results not yet ingested | ticker labeled "PROVISIONAL — official pending" |
| `final` | backend already has official results for this session | client should refetch `/results` |
| `unavailable` | no OpenF1 session key resolvable, or upstream down | "live timing unavailable" fallback |

**OpenF1 client additions** ([backend/src/openf1/client.ts](../../../backend/src/openf1/client.ts)):

- `getPosition(sessionKey)` → `GET /position?session_key=K`. The endpoint returns time-series rows; reduce to
  the **latest** `{driver_number → position}`.
- Reuse `getDrivers(sessionKey)` for code / name / team name / team colour.
- *(Optional)* `getIntervals(sessionKey)` → `GET /intervals?session_key=K` for the gap-to-leader column;
  if skipped, `raceTime` is null.

**Parser** ([backend/src/openf1/parsers.ts](../../../backend/src/openf1/parsers.ts)): join latest positions
with the drivers lookup, map team name → `constructorId` (reuse existing mapping), produce the `order` array
sorted by position. Drivers missing from the position feed are omitted. Status is best-effort.

**Session-key resolution** ([backend/src/repo/sessions.ts](../../../backend/src/repo/sessions.ts)):
use `session.openf1SessionKey` if set; otherwise resolve lazily from `getSessions(year)` by matching
`date_start ≈ scheduledStart` and the OpenF1 session name → our `SessionType` (Race / Qualifying / Sprint /
Sprint Shootout(Qualifying)). On success, cache in memory and persist to the session row. On failure →
`state: "unavailable"`.

**Caching:** in-memory map keyed by `sessionId`, TTL ~10–15s on the OpenF1 fetch, so concurrent client polls
share a single upstream call. Single-instance assumption is fine at current scale.

**Gating:** scorable session types only (`race`, `qualifying`, `sprint`, `sprint_quali`). Practice → 404.
If `session.status === 'finished'` → return `state: "final"` (don't hit OpenF1).

### 5.3 "Live session" detection (shared)

Add a session-level predicate to `lib/domain/` (e.g. extend `race_phase.dart` or new `live_session.dart`):

> A session is **live** when it is scorable AND `now ≥ scheduledStart` AND `status != finished` AND
> `now < scheduledEnd + 6h` (safety cap so a never-scored session doesn't show "live" forever).

This single predicate spans the running phase *and* the provisional gap, and flips off the instant the
crawler marks the session `finished`. Used by both the Home hero and the results screen. (Distinct from the
existing per-**event** `classifyCalendar` / `RaceState`, which stays as-is.)

### 5.4 Frontend — shared `LiveSessionController`

A new app-scoped `ChangeNotifier` (`lib/state/live_session_controller.dart`) isolates polling:

- **Input:** the events/sessions list (already fetched for Home/results) → finds the currently-live scorable
  session via the §5.3 predicate (at most one).
- **Behavior:** while a live session exists and the app is foregrounded, polls `GET /sessions/:id/live`
  every ~20–30s. Pauses on background (`WidgetsBindingObserver`) and when there are no live sessions; stops
  cleanly on dispose.
- **Output:** `LiveSnapshot { sessionId, state, asOf, List<SessionResult> order }?` plus a `liveSessionId`.
- Both consumers read this; neither re-implements polling.

### 5.5 Frontend — results screen live mode

In [session_results_screen.dart](../../../lib/screens/session_results_screen.dart), when the active session
is the live one, `_payloadFor` sources `order` from the `LiveSessionController` (or a one-off `/live` fetch)
instead of the 404-ing `/results`, still fetches `leagueSessionPredictions`, and sets a `live`/`state` flag
on `_SessionPayload`. Rendering **reuses existing widgets**:

- `_YourScoreTicket` ← `scoreSession(type, myPicks, liveOrder)`, labeled **"YOUR SCORE · PROJECTED"**.
- "FULL CLASSIFICATION" colored rows ← rendered from `liveOrder` unchanged; section re-titled **"LIVE ORDER"**
  with a **● LIVE** / **PROVISIONAL** badge in the header.
- "LEAGUE PICKS" `_MemberPickTicket` ← each member's projected total via
  `scoreSession(type, member.picks, liveOrder)`; **sort members by projected points** (live mini-leaderboard).
- On `state: final` or the session flipping to `finished` while viewed → refetch `/results` and render the
  authoritative scored view (the existing path).

### 5.6 Frontend — Home hero

[home_screen.dart](../../../lib/screens/home_screen.dart) / [home_cache_controller.dart](../../../lib/state/home_cache_controller.dart):
when `LiveSessionController` reports a live session, the hero swaps from next/countdown to a compact **live
card**: `● LIVE · {event} {session}`, top-3 live positions (colored), my projected points; tap → the full
live results screen for that session. The normal "next" hero is suppressed while live. When the session
becomes `finished`, the existing **"last finished session"** card takes over and the following session
becomes the new "next".

### 5.7 States & transitions (summary)

| Phase | Condition | Home / Results show |
|---|---|---|
| Scheduled | `now < start` | Next + countdown (unchanged) |
| Live | `start ≤ now < end`, `status=scheduled`, data flowing | Live order + projected, **LIVE** |
| Provisional | `now ≥ end`, `status=scheduled` | Last order + projected, **PROVISIONAL — official pending** |
| Scored | `status=finished` | Official `/results` + official scores; Home → last-finished card. *(Feature 2 push fires here, later.)* |
| Unavailable | no key / OpenF1 down during live | "Race in progress — live timing unavailable" fallback |

## 6. Edge handling

- OpenF1 partial/empty order → render what we have; `pre` state when empty.
- Quali/shootout: live "position" is timing-screen order (best lap); projection is genuinely provisional and
  labeled so.
- Not logged in / no league → live order still shows (public); no member projections.
- Keep the Dart `scoreSession` and backend TS `scoreSession` in sync (already true; they are independent
  implementations of the same rules).

## 7. Acceptance criteria

1. During a live race, Home shows a LIVE card (live top-3 + my projected points) and does **not** show the
   session-after-the-running-one as "next".
2. The results screen for the live session shows the live order in colored rows, my projected score, and each
   league member's projected score sorted high→low, all updating on a ~20–30s cadence.
3. After `scheduledEnd` but before scoring, the same view persists labeled PROVISIONAL.
4. Once the crawler scores the session (`status=finished`), both surfaces switch to official results/scores
   automatically, and the next session returns as "next".
5. When OpenF1 has no data / no key, the app shows a graceful fallback rather than an error or a stale "next".
6. Other (non-scorable, future, past) sessions behave exactly as today.

## 8. Testing

- **Backend** (run via `make backend-test` — vitest needs env sourced by the Makefile):
  OpenF1 position parser (latest-per-driver reduction, drivers join, team→`constructorId`), session-key
  resolution matching, cache TTL, and route `state` selection — using fixture OpenF1 payloads.
- **Frontend:** domain tests for projected score + member sort from a synthetic live order; widget tests for
  results-screen live mode (colored rows + projected labels) and Home live-card-suppresses-next, via an
  injected fake `ApiClient`. `LiveSessionController` unit test for poll/pause/stop lifecycle.
- **Manual:** requires a live session; gate behind a fixture/replay or verify during an actual session.

## 9. Risks & first step

- **Primary risk: OpenF1 live behavior** — whether `/position` updates mid-session, when the session key
  becomes available, and latency. The backend only uses OpenF1 post-hoc today, so this is unproven here.
  **Implementation step 1 is a short spike**: hit `/position` + `/drivers` for a real session key, confirm
  field shape + freshness, before building the endpoint and UI. Everything else is low-risk reuse.
- Render `starter` cost (~$7/mo) — accepted.

## 10. Files

**New**
- `backend/src/api/routes/live.ts` *(or extend `public.ts`)* — the `/sessions/:id/live` route.
- `lib/state/live_session_controller.dart` — polling + live-session detection.
- `lib/domain/live_session.dart` *(or extend `race_phase.dart`)* — the live predicate.

**Modified**
- `render.yaml` — `plan: starter`.
- `backend/src/openf1/client.ts`, `backend/src/openf1/parsers.ts` — `getPosition` (+ optional `getIntervals`)
  and the live-order parser.
- `backend/src/repo/sessions.ts` — persist a resolved `openf1SessionKey`.
- `lib/screens/session_results_screen.dart` — live mode in `_payloadFor` / `_Body`.
- `lib/screens/home_screen.dart`, `lib/state/home_cache_controller.dart` — live hero + suppress next.
- `lib/api/api_client.dart`, `lib/api/http_api_client.dart` — `sessionLive(id)` method + a `LiveSnapshot`
  model (reusing `SessionResult` for `order`).
