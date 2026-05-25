# Frontend Redesign — Design

**Date:** 2026-05-25
**Status:** Draft pending user review
**Sub-project:** Flutter UI redesign — runs in parallel with sub-project 1 (Data Foundation)

## Context

The current Flutter app is a three-tab thin client over Ergast: each screen fetches its own HTTP inline, prediction "scores" are hardcoded mock data, and there is no shared design language. This sub-project replaces the entire UI with a designed, themed Flutter app — implemented now against a typed mock client that mirrors the data-foundation backend's response contract, so swapping to the real `f1pg-backend` is a one-line change when sub-project 1 lands.

Out-of-scope concerns (auth, real predictions, real scoring, pre-season questionnaire) are stubbed client-side: the *shape* of those flows is in the UI, the *write path* is not.

## Goal

Ship a new Flutter app — six screens, one design system, both themes — that:
- Looks unmistakably like an F1 product and unmistakably *not* like a stock Material app.
- Works end-to-end against in-app fixtures today.
- Drops into the real backend's read API with a single `--dart-define` flip.
- Stays plain enough that screen-local state remains `setState`.

## Decisions

| # | Decision | Rationale |
|---|---|---|
| D1 | **Visual direction:** "Pop / Apparel" — colour-blocked, condensed display type, racing-stripe motif, team-coloured podium tiles | Reads as F1 without being broadcast-mimicry. Confirmed via three-option mockup. |
| D2 | **Themes:** Light + Dark, with in-app toggle persisted to `shared_preferences` | Both directions look right; users get a manual override on top of OS preference. |
| D3 | **Accent colour:** F1 red `#e10600` | Single brand colour; team colours appear only on driver/podium content. |
| D4 | **Display font:** `Anton` (Google Fonts). **Body:** `Inter` | Anton for race names + big numerics matches the condensed-display feel; Inter for everything else. |
| D5 | **User model:** Personal account, friend-group league | Each player has a "me"; leaderboards are per-league. Auth is stubbed (pick-a-user) until the auth sub-project. |
| D6 | **Navigation:** 4-tab bottom nav (Home / Calendar / Predict / Standings), drill-downs from there | Session-results is a drill-down from Home or Calendar; Season Insights is a sub-tab inside Standings. Keeps the bar uncluttered. |
| D7 | **State:** No state library. `ChangeNotifier` + `ListenableBuilder` for shared state; `setState` for screen-local | Honours the existing CLAUDE.md instruction not to introduce a state-management library casually. |
| D8 | **Routing:** `go_router` with a `ShellRoute` for the bottom nav | Nested routes (race → session) need it; tiny, official, well-supported. |
| D9 | **Data:** `ApiClient` interface with `HttpApiClient` (real) and `MockApiClient` (fixtures). Toggle via `--dart-define=USE_MOCK=true` | Decouples UI work from sub-project 1's deploy timeline. Same models, two transports. |
| D10 | **Prediction storage:** Local-only (`shared_preferences`) until the predictions sub-project lands | The UI for submission/locking is real; the write path is a stub. |
| D11 | **Scoring:** Pure functions in `domain/scoring.dart`. Per-session rules from data-foundation spec | Testable in isolation; rules are isolated constants so values can be tuned without touching call-sites. |

## Architecture

### Repo layout

The existing `lib/Screens` and `lib/Components` are deleted as part of the rebuild.

```
lib/
├── main.dart                       # bootstrap: themes, controllers, router
├── app.dart                        # MaterialApp.router + ListenableBuilder for theme
├── theme/
│   ├── tokens.dart                 # spacing, radii, strokes, durations
│   ├── colors.dart                 # brand + state + neutral palettes (light/dark)
│   ├── team_colors.dart            # canonical team colour map (was duplicated 3x)
│   ├── typography.dart             # Anton + Inter text styles
│   └── app_theme.dart              # ThemeData.light + ThemeData.dark
├── components/                     # design-system primitives (see "Components")
├── nav/
│   ├── router.dart                 # go_router config + ShellRoute
│   ├── app_shell.dart              # bottom nav + IndexedStack
│   └── bottom_nav.dart             # the 4-item bar
├── screens/
│   ├── home/                       # HomeScreen + sections (hero, pick card, last result, league)
│   ├── calendar/                   # CalendarScreen + RaceTile composer
│   ├── predict/                    # PredictScreen + tabs + slots + driver grid
│   ├── session/                    # SessionResultsScreen (pick-vs-result + full classification)
│   ├── standings/
│   │   ├── standings_screen.dart   # hosts the 3 sub-tabs
│   │   ├── league_tab.dart
│   │   ├── f1_tab.dart
│   │   └── insights_tab.dart
│   └── auth/
│       └── login_screen.dart       # pick-a-user stub
├── api/
│   ├── api_client.dart             # abstract interface
│   ├── http_api_client.dart        # real backend transport
│   ├── mock_api_client.dart        # fixture-backed
│   └── models/                     # one file per entity (Season, Event, Session, ...)
├── domain/
│   ├── prediction.dart             # Pick, PredictionEntry
│   ├── league.dart
│   └── scoring.dart                # pure functions, per-session-type
├── state/
│   ├── auth_controller.dart
│   ├── league_controller.dart
│   ├── theme_controller.dart
│   └── predictions_store.dart
└── mock/
    └── fixtures/                   # JSON files matching backend response shapes
```

### Dependencies

**Runtime adds:** `go_router`, `google_fonts`, `shared_preferences`, `intl`.
**Already present:** `http`, `flutter`, `cupertino_icons`.
**Dev adds:** `mocktail`, `golden_toolkit`.

No state-management library, no codegen, no DI framework.

## Design system

### Tokens

| Token | Value |
|---|---|
| `accent` | `#e10600` |
| `stroke` | `#000` (light), `#2a2a2e` (dark) |
| `surface` | `#fff` (light), `#0e0e10` (dark) |
| `surfaceMuted` | `#fafafa` (light), `#16161a` (dark) |
| `ok` / `near` / `miss` | `#19d36b` / `#ffd233` / `#000` |
| `live` | `#e10600` |
| Display sizes | 28 / 24 / 20 / 16 |
| Body sizes | 14 / 13 / 12 / 11 |
| Label sizes | 10 / 9 (uppercase, 1.5–2px tracking) |
| Spacing | 4 / 6 / 8 / 12 / 14 / 18 / 24 |
| Radii | 8 / 12 / 14 / 18 / 999 |
| Stroke widths | 1.5 (subtle) / 2 (cards) |
| CTA shadow | `0 6px 0 #000` |

### Team colours

Canonical, single-source map in `theme/team_colors.dart`. Includes aliases for renames (e.g. `alphatauri` → `rb`, `alfa` → `kick_sauber`). The existing duplication across three screen files goes away.

### Component primitives

All live in `lib/components/`. Each has a golden test in both themes.

| Primitive | Used by |
|---|---|
| `AppCard` (2px border, 14-radius, optional CTA shadow) | foundation for most tiles |
| `RaceTile` (round + name + when + state badge + optional hit/miss dots) | Calendar, Home |
| `PodTile` (team-colour block + position + driver code + hit marker) | Home last-result, Session pick-vs-result, Standings podium |
| `Slot` (numbered prediction slot — empty/filled states) | Predict |
| `DriverTile` (4-col grid tile, team stripe, picked badge) | Predict |
| `ScoreBanner` (red hero with stripe pattern + big number) | Session, Insights |
| `SessionChip` (FP1 / Q / R / SQ / S with done/active states) | Home hero |
| `Countdown` (D/H/M, fixed-width digits, 1Hz `Ticker`) | Home, Predict |
| `BottomNav` (4 items, red pill indicator) | shell |
| `LeagueRow` (rank + initials avatar + name + trend + points) | Standings |
| `TrajectoryChart` (custom-painted line chart, 3 series) | Insights |
| `FactCard` (badge + line of copy) | Insights |
| `TrendBadge` (▲/▼/━ pill) | Standings |

## Screens

Mockups live in `.superpowers/brainstorm/31940-1779702265/content/screen-*.html` (gitignored, kept locally for reference).

### Home — `/home`
Brand + league switcher · hero countdown card with weekend session chips (FP1·FP2·FP3·Q·R, done/next states) · "Your pick" status card (locked/open/CTA) · "Last race" recap with podium tiles and per-pick ✓/✗ markers · league snapshot showing top 4 with "you" highlighted. Section headers link to drill-downs.

### Calendar — `/calendar`
Chronological vertical list of race weekends, grouped by month dividers. Each `RaceTile` shows round number, country + circuit, date range, and a state badge: `NEXT` (black), `LIVE` (red, with red left rail), or relative date for future. Past tiles show 5 hit/miss dots (Race Top-5 picks) and total points scored. Sprint weekends get a black `SPRINT` corner tag. Filter chips: All / Upcoming / Past / Sprint. Tap a tile → `/race/:round`.

### Predict — `/predict`
Defaults to the next pickable session for the current weekend. Session tabs at top (Quali · Sprint Quali · Sprint · Race — only those relevant to this weekend, locked ones greyed). Below: numbered slots P1..Pn (size depends on session — Quali 2, Race 5, SprintQuali 1, Sprint 3), and a 4-column driver grid below. Tap a tile → assign to next empty slot. Tap a filled slot → clear. Picked drivers black-out in the grid with a badge showing which slot. CTA "Lock pick" at the bottom with countdown to lock; remains tappable as "Update pick" until then.

### Session Results — `/race/:round/:session`
Lands here from Home or Calendar. Header shows race + round + session type. Session tabs (Quali / Race / Sprint — only those that ran). **Score banner**: total points, breakdown ("3 exact · 1 in top-5 · 1 miss"), league rank for this round. **Pick-vs-result block**: side-by-side rows, your pick on the left, actual on the right, with a green/yellow/black dot in the middle and the points awarded. Below: full classification (P1–P20) with your picks highlighted in cream and marked with ✓ or ~. Status row legend at the bottom of the diff block.

### Standings — `/standings/league` (default), `/standings/f1`, `/standings/insights`

**League tab:** league name + member count chip · podium hero (1/2/3 with gold/silver/bronze blocks) · sortable full table (Total / Avg) with `LeagueRow`s, "you" highlighted, trend pills · horizontal round-by-round point strip for the user.

**F1 tab:** same shape applied to Ergast/Jolpica `/api/standings/drivers` and `/api/standings/constructors`. Driver image (Wikipedia) replaces the initials avatar where available; falls back to a coloured circle.

**Insights tab:** "Your season" 2×2 stat grid (total / avg / hit-rate / best round) · `TrajectoryChart` (cumulative points: you / leader / league avg, 3 lines) · "Your favourite picks" — list of most-picked drivers with hit-rate bar · "League gossip" — 3–5 `FactCard`s derived from the season data · "Driver form · last 3 races" — horizontal bars sorted by recent points.

### Settings — `/settings`

Minimal: theme toggle (Light / Dark / System), the current user (with "Sign out" → returns to `/login`), the current league, and an "About" block (app version, link to the backend health endpoint). Reached via a gear icon in the top bar of any tab.

## Navigation & state

### Router

`go_router` with a `ShellRoute` wrapping the four tab routes. The shell hosts an `IndexedStack` so each tab preserves scroll, countdown, and form state on tab switch (the existing app already relies on `IndexedStack` for the same reason).

```
/login                            (outside shell)
/                                 (ShellRoute → AppShell)
├── /home
├── /calendar
├── /predict
└── /standings
    ├── /standings/league         (default)
    ├── /standings/f1
    └── /standings/insights
/race/:round                      (outside shell — full-screen drill-down)
└── /race/:round/:session
/settings                         (outside shell — full-screen drill-down)
```

### State

Three `ChangeNotifier`s lifted to the app root, provided via a small `InheritedNotifier`:
- **`AuthController`** — current user, `login(userId)`, `logout()`. Stub backed by the league member list. Persists "current user" id to `shared_preferences`.
- **`LeagueController`** — current league + members. Single league ("The Box") at launch; the switcher chip in the top bar is wired but has only that entry.
- **`ThemeController`** — `ThemeMode.light | dark | system`. Persisted.

`PredictionsStore` (also a `ChangeNotifier`) holds in-memory picks keyed by `(sessionId, userId)`, mirrored to `shared_preferences`. `submit(sessionId, picks)` is a stub write; `picksFor(sessionId)` and `lockState(sessionId)` are reads consumed by Predict, Home, and Session-Results screens.

Screen-local state (countdown tickers, scroll positions, expanded/collapsed sections, the in-flight pick draft on Predict) stays `setState`.

## Data layer

### `ApiClient` interface

One Dart abstract class, methods 1:1 with the data-foundation spec's public endpoints:

```
Future<Season> currentSeason()
Future<List<Event>> events()
Future<Event> event(int round)
Future<Session> session(int id)
Future<List<SessionResult>> sessionResults(int id)
Future<Session> nextSession()
Future<List<DriverStanding>> driverStandings()
Future<List<ConstructorStanding>> constructorStandings()
Future<Driver> driver(String code)
Future<Constructor> constructor(String id)
```

### Two implementations

- **`HttpApiClient`** — `package:http` requests to `${API_URL}/api/...`. URL via `--dart-define=API_URL=...`. ISO-8601 timestamps parsed to local `DateTime` per response convention.
- **`MockApiClient`** — reads JSON from `lib/mock/fixtures/*.json`, shaped exactly like the backend would return. Bundled as Flutter assets. Includes a "current weekend" fixture covering Quali done + Race upcoming so every screen has interesting data on first launch.

### Selection

`--dart-define=USE_MOCK=true` (default `true`). One factory in `main.dart` picks the implementation; nothing else in the app knows the difference.

### Models

Hand-written `fromJson` constructors, no codegen. One file per entity, mirroring the backend's `domain/types.ts`. Images come back as a single `image` field (the backend already merges `image_url_override ?? image_url`).

### What stays mocked even with real backend

The backend exposes read-only F1 data only. Anything user/prediction/league-shaped has *no* real endpoint yet and is served from in-memory + `shared_preferences` until the next sub-projects:

| Data | Source today | Source after this sub-project | Source when fully shipped |
|---|---|---|---|
| Events / sessions / results / standings | `MockApiClient` | `HttpApiClient` | `HttpApiClient` |
| Driver / constructor images | `MockApiClient` | `HttpApiClient` (Wikipedia-backed) | same |
| Current user / login | `AuthController` stub | same | auth sub-project endpoint |
| Predictions (read + write) | `PredictionsStore` (local) | same | predictions sub-project endpoints |
| League leaderboard | computed client-side from local picks + real results | same | scoring sub-project endpoint |
| League members | hardcoded ("The Box": Anton, Lukas, Simon, Paul, Peter) | same | league sub-project |

## Scoring

`domain/scoring.dart` exports pure functions:

```dart
int scoreQualifying(List<String> picks, List<SessionResult> result);  // Top-2
int scoreRace(List<String> picks, List<SessionResult> result);        // Top-5
int scoreSprintQualifying(List<String> picks, List<SessionResult>);    // Top-1
int scoreSprint(List<String> picks, List<SessionResult>);              // Top-3

enum PickOutcome { exact, inTopN, miss }
PickOutcome outcomeFor(String pick, int slot, List<SessionResult> result, int topN);
```

Per-outcome point values live in a `ScoringRules` constants block. **Open question:** exact point values per outcome — this sub-project ships placeholder values (8 exact, 4 inTopN, 0 miss) and they get tuned in the scoring sub-project. Call-sites do not change.

## Error handling

| Surface | Behavior |
|---|---|
| API failure on first load | Full-screen empty state ("Can't reach the pit wall · Try again") with retry |
| API failure on background refresh | Toast at the bottom; keep stale data on screen |
| Empty / not-yet-published session result | "Results not in yet" placeholder card in place of the result block |
| User missed pick lock | Predict screen shows "Locked · no entry" card instead of the slot picker |
| Driver/constructor image null | Coloured circle with initials, sized to match the image slot |
| Country flag missing | Three-letter country code chip instead |
| Offline detection | One-line banner under the top bar; everything else degrades to cached data |

No global error overlay; all error states are inline so the rest of the app keeps working.

## Testing

| Layer | Approach |
|---|---|
| Tokens / component primitives | Golden tests in both themes (`golden_toolkit`), one golden file per primitive per theme |
| `domain/scoring.dart` | Unit tests — table-driven, one row per (picks, result, expected_points) combination |
| `MockApiClient` | Unit — round-trip a fixture, assert against the parsed model |
| Screens | Widget tests — pump screen with `MockApiClient`, assert key elements render and tap handlers fire |
| Integration | One flow: open Predict → fill 5 slots → tap Lock → land on Home with pick card showing locked picks |
| Theme switching | Widget test — toggle `ThemeController`, assert surface colour changes |

CI is currently absent in this repo. Setting it up is **not** in scope for this sub-project; tests must pass locally via `flutter test`.

## Done-list (definition of done)

- [ ] Old `lib/Screens/` and `lib/Components/` deleted; new layout in place
- [ ] All design tokens, theme data (light + dark), team-colour map landed
- [ ] All 13 component primitives implemented with passing goldens in both themes
- [ ] 6 screens (Home, Calendar, Predict, Session Results, Standings × 3 sub-tabs) + Settings + Login stub render against `MockApiClient` fixtures
- [ ] Login stub gates the app on first launch; current user persists
- [ ] Theme toggle in Settings persists across launches
- [ ] `flutter analyze` clean; `flutter test` green
- [ ] App launches on iOS + Android + Web with `USE_MOCK=true`
- [ ] App launches on at least one platform with `USE_MOCK=false` against the deployed backend (when sub-project 1 ships)
- [ ] Brainstorm mockups archived in `.superpowers/brainstorm/` for reference

## Known unknowns

1. **Exact scoring values** — placeholder constants ship; tuning happens in the scoring sub-project. UI shows whatever the rules return.
2. **Driver number / portrait availability** — Jolpica may not expose driver numbers consistently. Fixture covers a happy path; real-backend behaviour verified at integration time.
3. **Sprint Qualifying ("Sprint Shootout") session type** — depends on data-foundation sub-project's resolution. The Predict screen handles it the same way as the others; if the data isn't there, the tab is absent.

## Out of scope (other sub-projects)

- Auth backend, account creation, password / OAuth.
- Server-side prediction submission, storage, validation, lock enforcement.
- Server-side scoring computation and leaderboard endpoints.
- Pre-season questionnaire (form, storage, season-end resolution).
- League CRUD (create / join / invite). One hardcoded league for now.
- Push notifications, share / export, in-app purchases.
- Localisation (English copy only).
