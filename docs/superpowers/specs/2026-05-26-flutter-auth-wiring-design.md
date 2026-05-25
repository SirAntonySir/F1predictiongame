# Flutter Auth Wiring — Design

**Date:** 2026-05-26
**Status:** Draft (pending user review)
**Predecessor:** [2026-05-25 backend auth + leagues spec](2026-05-25-users-auth-design.md)
**Companion to:** the post-merge state on `main` (frontend redesign + full backend stack)

## Context

The backend has had real email/password auth, sessions, and leagues since sub-project 2. The Flutter app — currently shipping with a "tap-a-player" picker, a hardcoded demo league, and prediction/preseason stores that persist only to `SharedPreferences` — has never been wired to those endpoints. `ApiClient` is read-only and unauthenticated.

This sub-project is the first slice of "wire the frontend to the backend." It is deliberately scoped to **auth + a minimal league-onboarding gate**. Predictions wiring and preseason wiring are explicit follow-ups (see Out of Scope).

## Goal

Replace the local "tap-a-player" login with real email/password auth against the existing backend. After signup, the user lands on a join-or-create-league screen so they end up inside a real `league` before reaching the rest of the app. All future authenticated endpoints (predictions, preseason, leagues management) inherit the bearer token attached by the HTTP client.

## Decisions

| # | Decision | Rationale |
|---|---|---|
| D1 | **Auth gate shape:** login screen first, with a "Sign up" link to a separate signup screen | Returning users open the app more often than new ones; default to the cheaper path for them. |
| D2 | **Token storage:** `flutter_secure_storage` (platform keychain) | Standard practice for bearer tokens. One dependency. Same code path on every platform. |
| D3 | **Boot flow:** brief splash → `GET /api/auth/me` → route by result | Avoids flashing home and bouncing on expired tokens. 401 wipes the token and routes to login. |
| D4 | **Post-signup gate:** dedicated `LeagueOnboardingScreen` with join-by-code (primary) and create-your-own (secondary) | The user explicitly requested join-by-code. Backend allows each user to own at most one league, so "create" is bounded. |
| D5 | **Existing local stores** (`predictions_v1`, `preseason_v1` keys in `SharedPreferences`) **wiped on first successful auth** (login or signup) | Keyed by fake user ids from the previous demo; would never match a real backend user id. Implemented as a one-shot inside `AuthController.signup` and `AuthController.login` after the token + `/me` succeed. |
| D6 | **Mid-session 401 handling:** `HttpApiClient` fires `onUnauthorized()` once, `AuthController.invalidate()` wipes state, `GoRouter` redirect sends user to `/login` | Single source of truth for "your session died," no per-screen retry logic. |
| D7 | **Out of scope:** password reset, display-name editing, league rename / regen-code / leave / kick, predictions wiring, preseason wiring | Each is its own follow-up. Forgot-password requires SMTP (not in backend yet). |

## Architecture

### Layered shape (no new top-level architecture)

```
main.dart
  └─ creates: SecureTokenStorage  → AuthController
                                  → HttpApiClient (token + onUnauthorized)
  └─ await auth.bootstrap()         (splash visible while this runs)
  └─ runApp(F1PgApp(...))

lib/
  state/
    auth_controller.dart    ← rewritten
    token_storage.dart      ← NEW: interface + SecureTokenStorage + InMemoryTokenStorage (tests)
  api/
    api_client.dart         ← new methods (signup/login/me/logout/createLeague/joinLeague) + new exception types
    http_api_client.dart    ← bearer attach, 401/409/422 mapping, onUnauthorized hook
  screens/
    login_screen.dart       ← rewritten (email + password + "Sign up" link)
    signup_screen.dart      ← NEW
    league_onboarding_screen.dart  ← NEW
    splash_screen.dart      ← NEW (minimal; only used during bootstrap before runApp)
    settings_screen.dart    ← edited: logout button calls auth.logout()
  nav/
    router.dart             ← extended redirect (3-state gate: not logged in / no league / ready)
```

### `AuthController` shape

```dart
class AuthController extends ChangeNotifier {
  AuthController({required this.storage});
  late ApiClient api;                   // set in main.dart after HttpApiClient is constructed
  final TokenStorage storage;

  User? user;
  List<UserLeague> leagues = const [];
  String? get token => _token;
  String? _token;

  bool   get isLoggedIn => _token != null && user != null;
  bool   get hasLeague  => leagues.isNotEmpty;
  String? get currentUserId => user?.id;

  Future<void> bootstrap();                                  // load token, call /me, populate or invalidate
  Future<void> signup(String email, String pw, String name); // signup → set token → me
  Future<void> login(String email, String pw);               // login → set token → me
  Future<void> refreshMe();                                  // re-fetch user + leagues
  Future<void> logout();                                     // POST /logout, wipe state + storage
  void invalidate();                                         // called on 401; wipes state + storage, notifies
}
```

The `api` field is settable to break the construction cycle (`AuthController` needs `ApiClient`, `HttpApiClient` needs `auth.token`). It is assigned exactly once in `main.dart` before `bootstrap()` runs.

### `TokenStorage` interface

```dart
abstract class TokenStorage {
  Future<String?> read();
  Future<void>    write(String token);
  Future<void>    clear();
}

class SecureTokenStorage  implements TokenStorage { /* flutter_secure_storage */ }
class InMemoryTokenStorage implements TokenStorage { /* used in tests */ }
```

Single key, e.g. `'f1pg.auth.token'`. No other auth state persists across launches.

### `ApiClient` additions

```dart
Future<AuthResult>  signup({required String email, required String password, required String displayName});
Future<AuthResult>  login({required String email, required String password});
Future<MeResult>    me();
Future<void>        logout();
Future<LeagueView>  createLeague({required String name});
Future<LeagueView>  joinLeague({required String code});
```

DTO shapes (new files in `lib/api/models/`):

- `AuthResult { User user; String token; }`
- `MeResult   { User user; List<UserLeague> leagues; }`
- `User       { String id; String email; String displayName; DateTime createdAt; }`
- `UserLeague { String id; String name; String role; }`  // role: 'owner' | 'member'
- `LeagueView { String id; String name; String joinCode; String role; List<LeagueMember> members; }`
- `LeagueMember { String id; String displayName; String role; }`

New exception types in `lib/api/api_client.dart`:

- `UnauthorizedException` — 401 from any endpoint
- `ForbiddenException(String message)` — 403
- `ConflictException(String message)` — 409 (e.g. email taken, code already used)
- `ValidationException(String message)` — 422 (e.g. password too short)
- `BadRequestException(String message)` — 400

Backend error body shape (confirmed in `backend/src/api/errors.ts`):

```json
{ "error": { "code": "VALIDATION", "message": "Password must be at least 8 characters" } }
```

`HttpApiClient` reads `body.error.message` to populate exception messages; falls back to a generic message if the body is unparseable.

### `HttpApiClient` changes

Constructor gains two params:

```dart
HttpApiClient({
  required this.baseUrl,
  required String? Function() tokenProvider,
  required VoidCallback onUnauthorized,
  http.Client? client,
})
```

A private `_request(method, path, {body})` helper centralizes:

- attach `Authorization: Bearer <token>` when `tokenProvider()` returns non-null
- attach `Content-Type: application/json` on writes
- map 400 → `BadRequestException(body.error.message)`
- map 401 → fire `onUnauthorized()` once + throw `UnauthorizedException`
- map 403 → `ForbiddenException(body.error.message)`
- map 404 → `NotFoundException`
- map 409 → `ConflictException(body.error.message)`
- map 422 → `ValidationException(body.error.message)`
- map ≥500 (or 502) → `UpstreamException`

Existing `_get` is refactored to call `_request('GET', ...)`. New writes use the same helper.

### Router gate (`lib/nav/router.dart`)

The current redirect is `not logged in → /login; logged in but at /login → /home`. Extended to a three-state gate:

```dart
redirect: (context, state) {
  final loc = state.matchedLocation;
  final authRoutes = {'/login', '/signup'};
  final onboardingRoute = '/onboarding/league';

  if (!auth.isLoggedIn) {
    return authRoutes.contains(loc) ? null : '/login';
  }
  if (!auth.hasLeague) {
    return loc == onboardingRoute ? null : onboardingRoute;
  }
  if (authRoutes.contains(loc) || loc == onboardingRoute) return '/home';
  return null;
},
```

`refreshListenable: auth` keeps the existing wiring; `invalidate()` notifies and the redirect handles the rest.

### Splash

The splash is **not** a `GoRoute`. It's a `MaterialApp` shown directly from `main.dart` while `auth.bootstrap()` runs, then replaced with `F1PgApp` once bootstrap resolves. This means by the time the router exists, auth state is already resolved and the redirect logic is deterministic on the first frame. The splash shows a small spinner and, on network error, a retry button. Token-present + network-up takes one round-trip.

### Mid-session 401 flow

```
any authenticated call → 401
  → HttpApiClient maps to UnauthorizedException, calls onUnauthorized() (debounced via a flag)
  → AuthController.invalidate(): _token = null, user = null, leagues = []; storage.clear(); notifyListeners()
  → GoRouter.refreshListenable fires; redirect runs; user lands on /login
  → SnackBar "Session expired, please log in again." shown once (set via a transient flag the LoginScreen consumes)
```

## Screen specs

### `LoginScreen` (rewrite)

| Element | Notes |
|---|---|
| Email field | TextFormField, keyboard `emailAddress`, autofills, validator: non-empty + basic email regex |
| Password field | obscure, validator: non-empty |
| Primary button | "Log in" → `auth.login(email, password)`. Disabled while in flight. |
| Error display | inline below button — maps `UnauthorizedException` to "Invalid email or password", `ValidationException` to its message, network errors to "Couldn't reach the server" |
| Secondary action | "No account? Sign up" → `context.go('/signup')` |
| Session-expired banner | if AuthController flag set, show snackbar on first build, then clear flag |

### `SignupScreen` (new)

| Element | Notes |
|---|---|
| Email field | as above |
| Password field | obscure, validator: ≥ 8 chars |
| Display name field | trimmed, validator: 1–40 chars |
| Primary button | "Create account" → `auth.signup(...)`. Disabled while in flight. |
| Error display | `ConflictException` → "Email already registered"; `ValidationException` → its message; other → generic |
| Secondary action | "Already have an account? Log in" → `context.go('/login')` |

### `LeagueOnboardingScreen` (new)

Single screen, two cards stacked:

| Card | Fields | Action |
|---|---|---|
| Join a league | join code (auto-uppercase as the user types) | "Join" → `api.joinLeague(code:...)` → `auth.refreshMe()` → router pushes to `/home` |
| Create a league | name (1–40) | "Create" → `api.createLeague(name:...)` → `auth.refreshMe()` → `/home` |

`NotFoundException` on join → "Unknown join code." `ConflictException` → backend message ("Already a member", "You already own this league").

### `SplashScreen` (new, not a `GoRoute`)

Centered spinner. If `auth.bootstrap()` throws (network), shows "Couldn't reach the server" + Retry button. Retry re-runs `bootstrap()`.

### `SettingsScreen` (edit)

Add a "Log out" tile at the bottom → `auth.logout()`. Confirm dialog before firing.

## Data flow on key actions

### App launch (cold)

```
main()
  └─ SecureTokenStorage.read() → token? T : null
  └─ AuthController.bootstrap():
       ├─ T == null → state stays unauthenticated, splash dismisses
       └─ T present → api.me() → store user + leagues; on 401 → invalidate
  └─ runApp(F1PgApp(...))
  └─ GoRouter redirect runs once, lands at /login | /onboarding/league | /home
```

### Successful signup

```
SignupScreen submit
  → api.signup(email, password, displayName) → { user, token }
  → AuthController._token = token; storage.write(token)
  → AuthController.user = user; leagues = const []  (signup endpoint doesn't return them; safe assumption)
  → notifyListeners
  → GoRouter sees isLoggedIn && !hasLeague → /onboarding/league
```

### Successful join

```
LeagueOnboardingScreen.join submit
  → api.joinLeague(code:...) → league view
  → auth.refreshMe()           (canonical list from backend)
  → notifyListeners
  → GoRouter sees isLoggedIn && hasLeague → /home
```

### Logout

```
Settings tap "Log out" → confirm → api.logout()
  → AuthController.invalidate()  (storage.clear, state wipe, notify)
  → GoRouter redirect → /login
```

### Mid-session 401

```
api.<something>() → 401
  → HttpApiClient.onUnauthorized() (fires at most once)
  → AuthController.invalidate()
  → GoRouter redirect → /login (snackbar shown once)
```

## Testing

| Layer | Test | Notes |
|---|---|---|
| unit | `AuthController.signup` happy path stores token + state | with fake `ApiClient`, `InMemoryTokenStorage` |
| unit | `AuthController.login` happy + invalid creds | UnauthorizedException surfaces |
| unit | `AuthController.bootstrap` with stored valid token → fetches /me | |
| unit | `AuthController.bootstrap` with stored token returning 401 → state wiped | |
| unit | `AuthController.logout` clears storage + notifies | |
| unit | `AuthController.invalidate` is idempotent | called multiple times safely |
| unit | `HttpApiClient.login/signup/me/logout` map status codes correctly | via `package:http/testing.dart`'s `MockClient` |
| unit | `HttpApiClient.createLeague` + `joinLeague` map 404/409 correctly | |
| unit | `HttpApiClient` attaches `Authorization: Bearer` when token present | |
| unit | `HttpApiClient` does NOT attach header when token null | |
| widget | Router gate: unauthenticated state → redirect to /login | |
| widget | Router gate: authenticated, no leagues → /onboarding/league | |
| widget | Router gate: authenticated, has leagues → /home | |
| widget | `LoginScreen` empty submit shows validation errors | |
| widget | `LoginScreen` calls `auth.login` with entered values | |
| widget | `SignupScreen` calls `auth.signup` with entered values | |
| widget | `LeagueOnboardingScreen` join path → calls `api.joinLeague` + `auth.refreshMe` | |
| widget | `LeagueOnboardingScreen` create path → calls `api.createLeague` + `auth.refreshMe` | |

Existing tests (`predictions_store_test.dart`, `controllers_test.dart`, `preseason_*`) keep passing — local stores are not removed in this PR.

## Out of Scope

Explicit follow-up sub-projects:

- **Predictions wiring** — replace `PredictionsStore` (local) with API-backed reads/writes (`/api/sessions/:id/my-prediction`, `/api/predictions/upcoming`).
- **Preseason wiring** — replace `PreseasonStore` with `/api/preseason/*`.
- **League management** — rename, regenerate code, leave league, list members, kick member, league switcher in the app shell.
- **Display-name editing** via `PATCH /api/auth/me`.
- **Password reset / email verification** — blocked on backend SMTP support.

## Risks & open questions

| # | Risk / question | Mitigation |
|---|---|---|
| R1 | Construction cycle between `AuthController` (needs `ApiClient`) and `HttpApiClient` (needs `auth.token`) | Resolved with a settable `late ApiClient api` on `AuthController`, assigned exactly once in `main.dart`. |
| R2 | Stale `predictions_v1` / `preseason_v1` from the demo era could surface | Wiped on first successful auth (D5). Stores stay in-place but become irrelevant after wiping. |
| R3 | Network race: 401 fires multiple times on parallel requests, snackbar shows multiple times | Debounce via boolean flag on `HttpApiClient`; reset after the next 2xx. |
| R4 | Backend's `currentSeason` and other anonymous reads still need to work pre-login | These remain unauthenticated — `HttpApiClient` attaches the header only when `tokenProvider()` returns non-null, so they're unaffected. |
| R5 | Existing `LeagueController` holds hardcoded demo league | Left in tree; not consumed by anything in this PR. Will be replaced in the league management PR. |
