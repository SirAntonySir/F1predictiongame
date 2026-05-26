# Flutter Auth + Predictions/Scores Wiring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the demo-era mock auth and local `PredictionsStore` with real backend-wired auth (token storage, login/signup/onboarding), then connect the Predict screen and a new Score Detail screen to the real prediction and scoring APIs, so Anton can log in as `anton@tippspiel.test`, see his imported Excel picks, and inspect per-session score breakdowns against the validation table.

**Architecture:** Two phases in a single plan. **Phase A (Auth)** introduces `TokenStorage`, bearer-aware `HttpApiClient`, a new `AuthController` state machine, splash/login/signup/onboarding screens, and a three-state router gate. **Phase B (Predictions+Scores)** drops the local `PredictionsStore`, adds DTO models + ApiClient methods for predictions and scores, a `PredictionsController` in-memory cache, a rewritten `PredictScreen` that reads/writes the backend, and a new `ScoreDetailScreen` rendering the scoring breakdown.

**Tech Stack:** Flutter SDK ^3.5.4, Dart, `http`, `go_router`, `shared_preferences`, `flutter_secure_storage` (new), `mocktail`, `flutter_test`.

**Specs:**
- `docs/superpowers/specs/2026-05-26-flutter-auth-wiring-design.md`
- `docs/superpowers/specs/2026-05-26-flutter-predictions-scores-wiring-design.md`

---

## File Structure

### Phase A — Auth (new + modified files)

**New:**
- `lib/api/models/user.dart`
- `lib/api/models/auth_result.dart`
- `lib/api/models/me_result.dart`
- `lib/api/models/user_league.dart`
- `lib/api/models/league_view.dart`
- `lib/api/models/league_member.dart`
- `lib/state/token_storage.dart`
- `lib/screens/splash_screen.dart`
- `lib/screens/signup_screen.dart`
- `lib/screens/league_onboarding_screen.dart`
- `test/api/models/auth_models_test.dart`
- `test/api/http_api_client_auth_test.dart`
- `test/api/http_api_client_leagues_test.dart`
- `test/state/auth_controller_test.dart`
- `test/state/token_storage_test.dart`
- `test/screens/login_screen_test.dart`
- `test/screens/signup_screen_test.dart`
- `test/screens/league_onboarding_screen_test.dart`
- `test/nav/router_gate_test.dart`

**Modified:**
- `pubspec.yaml` — add `flutter_secure_storage`
- `lib/api/api_client.dart` — add auth/league methods + new exception types
- `lib/api/http_api_client.dart` — `tokenProvider` + `onUnauthorized` + `_request` helper + new endpoints
- `lib/state/auth_controller.dart` — full rewrite
- `lib/screens/login_screen.dart` — full rewrite (email/password)
- `lib/screens/settings_screen.dart` — add logout tile
- `lib/nav/router.dart` — 3-state gate, add `/signup`, `/onboarding/league`
- `lib/main.dart` — new boot flow (token storage + bootstrap before runApp)
- `lib/app.dart` — drop unused `PredictionsStore`/`LeagueController` dependencies (Phase B handles new wiring)
- `lib/state/app_state.dart` — same

### Phase B — Predictions + Scores (new + modified)

**New:**
- `lib/api/models/pick.dart`
- `lib/api/models/prediction_view.dart`
- `lib/api/models/upcoming_prediction.dart`
- `lib/api/models/score_breakdown.dart` (3 classes in one file)
- `lib/api/models/my_score.dart`
- `lib/state/predictions_controller.dart`
- `lib/screens/score_detail_screen.dart`
- `test/api/models/prediction_models_test.dart`
- `test/api/models/score_models_test.dart`
- `test/api/http_api_client_predictions_test.dart`
- `test/api/http_api_client_scores_test.dart`
- `test/state/predictions_controller_test.dart`
- `test/screens/predict_screen_test.dart`
- `test/screens/score_detail_screen_test.dart`

**Modified:**
- `lib/api/api_client.dart` — add prediction + score methods
- `lib/api/http_api_client.dart` — implement them
- `lib/screens/predict_screen.dart` — rewire data path
- `lib/screens/home_screen.dart` — switch hero to `controller.upcoming`
- `lib/nav/router.dart` — add `/scores` route
- `lib/state/app_state.dart` — replace `PredictionsStore` with `PredictionsController`
- `lib/app.dart` — same
- `lib/main.dart` — construct `PredictionsController`

**Deleted:**
- `lib/state/predictions_store.dart`
- `test/state/predictions_store_test.dart`

---

## Conventions for Subagents Executing This Plan

- **Test command:** `flutter test` from repo root. Single file: `flutter test test/<path>`. Do NOT modify `vitest.config.ts` (that's backend; this plan only touches Flutter).
- **Backend dev server** is needed only for the final smoke task. Tests use `MockClient` / fakes; no live HTTP.
- **Commits:** stage only the files the task lists. Use explicit `git add <path>` — no `git add -A` or `git add .`.
- **Lint:** `flutter analyze` should be clean after each task. Run `dart format` if formatting drifts.
- **Import paths:** Flutter ESM-style with `package:predictiongame/...` for app code in tests; relative `../` paths inside `lib/`.
- **Coexistence:** Phase A leaves `PredictionsStore` in place (still referenced by old screens). Phase B removes it. Until Phase B begins, the auth-wired screens (login/signup/onboarding) must coexist with the old screens routed under the shell.

---

## Phase A — Auth Wiring

### Task A1: Add `flutter_secure_storage` dependency

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Add the package**

Run: `flutter pub add flutter_secure_storage:^9.2.4`
Expected: pubspec.yaml gets `flutter_secure_storage: ^9.2.4` under `dependencies`; lockfile updated.

- [ ] **Step 2: Verify**

Run: `grep flutter_secure_storage pubspec.yaml`
Expected: prints `flutter_secure_storage: ^9.2.4`.

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore: add flutter_secure_storage for bearer token persistence"
```

---

### Task A2: TokenStorage interface + InMemoryTokenStorage + tests

**Files:**
- Create: `lib/state/token_storage.dart`
- Create: `test/state/token_storage_test.dart`

- [ ] **Step 1: Write failing test**

Create `test/state/token_storage_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/state/token_storage.dart';

void main() {
  group('InMemoryTokenStorage', () {
    test('read returns null when empty', () async {
      final s = InMemoryTokenStorage();
      expect(await s.read(), isNull);
    });

    test('write then read returns the token', () async {
      final s = InMemoryTokenStorage();
      await s.write('abc');
      expect(await s.read(), 'abc');
    });

    test('clear removes the token', () async {
      final s = InMemoryTokenStorage();
      await s.write('abc');
      await s.clear();
      expect(await s.read(), isNull);
    });
  });
}
```

- [ ] **Step 2: Run, confirm fail**

Run: `flutter test test/state/token_storage_test.dart`
Expected: FAIL — `token_storage.dart` does not exist.

- [ ] **Step 3: Implement**

Create `lib/state/token_storage.dart`:

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class TokenStorage {
  Future<String?> read();
  Future<void>    write(String token);
  Future<void>    clear();
}

class SecureTokenStorage implements TokenStorage {
  static const _key = 'f1pg.auth.token';
  final FlutterSecureStorage _store;
  SecureTokenStorage({FlutterSecureStorage? store})
      : _store = store ?? const FlutterSecureStorage();

  @override
  Future<String?> read() => _store.read(key: _key);

  @override
  Future<void> write(String token) => _store.write(key: _key, value: token);

  @override
  Future<void> clear() => _store.delete(key: _key);
}

class InMemoryTokenStorage implements TokenStorage {
  String? _token;
  @override
  Future<String?> read() async => _token;
  @override
  Future<void> write(String token) async { _token = token; }
  @override
  Future<void> clear() async { _token = null; }
}
```

- [ ] **Step 4: Run, confirm pass**

Run: `flutter test test/state/token_storage_test.dart`
Expected: 3 PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/state/token_storage.dart test/state/token_storage_test.dart
git commit -m "feat(auth): TokenStorage interface + SecureTokenStorage + InMemoryTokenStorage"
```

---

### Task A3: Auth DTO models

**Files:**
- Create: `lib/api/models/user.dart`
- Create: `lib/api/models/user_league.dart`
- Create: `lib/api/models/league_member.dart`
- Create: `lib/api/models/league_view.dart`
- Create: `lib/api/models/auth_result.dart`
- Create: `lib/api/models/me_result.dart`
- Create: `test/api/models/auth_models_test.dart`

- [ ] **Step 1: Write failing test**

Create `test/api/models/auth_models_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/models/auth_result.dart';
import 'package:predictiongame/api/models/league_member.dart';
import 'package:predictiongame/api/models/league_view.dart';
import 'package:predictiongame/api/models/me_result.dart';
import 'package:predictiongame/api/models/user.dart';
import 'package:predictiongame/api/models/user_league.dart';

void main() {
  test('User.fromJson', () {
    final u = User.fromJson({
      'id': 'u1', 'email': 'a@b.com', 'displayName': 'A', 'createdAt': '2026-05-01T00:00:00.000Z',
    });
    expect(u.id, 'u1');
    expect(u.displayName, 'A');
    expect(u.createdAt.toIso8601String(), '2026-05-01T00:00:00.000Z');
  });

  test('UserLeague.fromJson', () {
    final l = UserLeague.fromJson({'id': 'L', 'name': 'My League', 'role': 'owner'});
    expect(l.role, 'owner');
  });

  test('LeagueMember.fromJson', () {
    final m = LeagueMember.fromJson({'userId': 'u2', 'displayName': 'B', 'role': 'member'});
    expect(m.id, 'u2');
    expect(m.displayName, 'B');
  });

  test('LeagueView.fromJson with optional joinCode', () {
    final l = LeagueView.fromJson({
      'league': {'id': 'L', 'name': 'My League', 'role': 'owner', 'joinCode': 'ABC123'},
      'members': [
        {'userId': 'u1', 'displayName': 'A', 'role': 'owner'},
        {'userId': 'u2', 'displayName': 'B', 'role': 'member'},
      ]
    });
    expect(l.id, 'L');
    expect(l.role, 'owner');
    expect(l.joinCode, 'ABC123');
    expect(l.members.length, 2);

    final asMember = LeagueView.fromJson({
      'league': {'id': 'L', 'name': 'My League', 'role': 'member'},
      'members': []
    });
    expect(asMember.joinCode, isNull);
  });

  test('AuthResult.fromJson', () {
    final r = AuthResult.fromJson({
      'user': {'id': 'u1', 'email': 'a@b.com', 'displayName': 'A', 'createdAt': '2026-05-01T00:00:00.000Z'},
      'token': 'tok',
    });
    expect(r.token, 'tok');
    expect(r.user.id, 'u1');
  });

  test('MeResult.fromJson', () {
    final r = MeResult.fromJson({
      'user': {'id': 'u1', 'email': 'a@b.com', 'displayName': 'A', 'createdAt': '2026-05-01T00:00:00.000Z'},
      'leagues': [
        {'id': 'L1', 'name': 'Eins', 'role': 'owner'},
        {'id': 'L2', 'name': 'Zwei', 'role': 'member'},
      ]
    });
    expect(r.leagues.length, 2);
    expect(r.leagues[1].role, 'member');
  });
}
```

- [ ] **Step 2: Run, confirm fail**

Run: `flutter test test/api/models/auth_models_test.dart`
Expected: all FAIL.

- [ ] **Step 3: Create the model files**

Create `lib/api/models/user.dart`:

```dart
class User {
  final String id;
  final String email;
  final String displayName;
  final DateTime createdAt;

  const User({
    required this.id,
    required this.email,
    required this.displayName,
    required this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> j) => User(
        id: j['id'] as String,
        email: j['email'] as String,
        displayName: j['displayName'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
      );
}
```

Create `lib/api/models/user_league.dart`:

```dart
class UserLeague {
  final String id;
  final String name;
  final String role; // 'owner' | 'member'

  const UserLeague({required this.id, required this.name, required this.role});

  factory UserLeague.fromJson(Map<String, dynamic> j) => UserLeague(
        id: j['id'] as String,
        name: j['name'] as String,
        role: j['role'] as String,
      );
}
```

Create `lib/api/models/league_member.dart`:

```dart
class LeagueMember {
  final String id;
  final String displayName;
  final String role;

  const LeagueMember({required this.id, required this.displayName, required this.role});

  factory LeagueMember.fromJson(Map<String, dynamic> j) => LeagueMember(
        id: j['userId'] as String,
        displayName: j['displayName'] as String,
        role: j['role'] as String,
      );
}
```

Create `lib/api/models/league_view.dart`:

```dart
import 'league_member.dart';

class LeagueView {
  final String id;
  final String name;
  final String? joinCode;
  final String role;
  final List<LeagueMember> members;

  const LeagueView({
    required this.id,
    required this.name,
    required this.role,
    required this.joinCode,
    required this.members,
  });

  factory LeagueView.fromJson(Map<String, dynamic> j) {
    final l = j['league'] as Map<String, dynamic>;
    final ms = (j['members'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(LeagueMember.fromJson)
        .toList();
    return LeagueView(
      id: l['id'] as String,
      name: l['name'] as String,
      role: l['role'] as String,
      joinCode: l['joinCode'] as String?,
      members: ms,
    );
  }
}
```

Create `lib/api/models/auth_result.dart`:

```dart
import 'user.dart';

class AuthResult {
  final User user;
  final String token;
  const AuthResult({required this.user, required this.token});

  factory AuthResult.fromJson(Map<String, dynamic> j) => AuthResult(
        user: User.fromJson(j['user'] as Map<String, dynamic>),
        token: j['token'] as String,
      );
}
```

Create `lib/api/models/me_result.dart`:

```dart
import 'user.dart';
import 'user_league.dart';

class MeResult {
  final User user;
  final List<UserLeague> leagues;
  const MeResult({required this.user, required this.leagues});

  factory MeResult.fromJson(Map<String, dynamic> j) => MeResult(
        user: User.fromJson(j['user'] as Map<String, dynamic>),
        leagues: (j['leagues'] as List)
            .cast<Map<String, dynamic>>()
            .map(UserLeague.fromJson)
            .toList(),
      );
}
```

- [ ] **Step 4: Run, confirm pass**

Run: `flutter test test/api/models/auth_models_test.dart`
Expected: all 6 PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/api/models/user.dart lib/api/models/user_league.dart lib/api/models/league_member.dart lib/api/models/league_view.dart lib/api/models/auth_result.dart lib/api/models/me_result.dart test/api/models/auth_models_test.dart
git commit -m "feat(auth): User/AuthResult/MeResult/LeagueView DTO models"
```

---

### Task A4: ApiClient interface — add auth & league methods + new exception types

**Files:**
- Modify: `lib/api/api_client.dart`

- [ ] **Step 1: Replace `lib/api/api_client.dart` with extended version**

Replace the file contents with:

```dart
import 'models/auth_result.dart';
import 'models/constructor.dart';
import 'models/driver.dart';
import 'models/event.dart';
import 'models/league_view.dart';
import 'models/me_result.dart';
import 'models/season.dart';
import 'models/session.dart';
import 'models/session_result.dart';
import 'models/standing.dart';

abstract class ApiClient {
  // existing read methods
  Future<Season> currentSeason();
  Future<List<Event>> events();
  Future<Event> event(int round);
  Future<Session> session(int id);
  Future<List<SessionResult>> sessionResults(int id);
  Future<Session> nextSession();
  Future<List<DriverStanding>> driverStandings();
  Future<List<ConstructorStanding>> constructorStandings();
  Future<Driver> driver(String code);
  Future<Constructor> constructor(String id);

  // auth
  Future<AuthResult> signup({required String email, required String password, required String displayName});
  Future<AuthResult> login({required String email, required String password});
  Future<MeResult>   me();
  Future<void>       logout();

  // leagues (onboarding)
  Future<LeagueView> createLeague({required String name});
  Future<LeagueView> joinLeague({required String code});
}

// Exceptions
class NotFoundException implements Exception {
  final String resource;
  const NotFoundException(this.resource);
  @override
  String toString() => 'NotFoundException: $resource';
}

class UpstreamException implements Exception {
  final String message;
  const UpstreamException(this.message);
  @override
  String toString() => 'UpstreamException: $message';
}

class UnauthorizedException implements Exception {
  const UnauthorizedException();
  @override
  String toString() => 'UnauthorizedException';
}

class ForbiddenException implements Exception {
  final String message;
  const ForbiddenException(this.message);
  @override
  String toString() => 'ForbiddenException: $message';
}

class ConflictException implements Exception {
  final String message;
  const ConflictException(this.message);
  @override
  String toString() => 'ConflictException: $message';
}

class ValidationException implements Exception {
  final String message;
  const ValidationException(this.message);
  @override
  String toString() => 'ValidationException: $message';
}

class BadRequestException implements Exception {
  final String message;
  const BadRequestException(this.message);
  @override
  String toString() => 'BadRequestException: $message';
}
```

- [ ] **Step 2: Type-check**

Run: `flutter analyze lib/api/api_client.dart`
Expected: no errors. Existing `HttpApiClient` will fail to type-check until Task A5 — that's expected. (Skip running `flutter analyze` on the whole project at this step.)

- [ ] **Step 3: Commit**

```bash
git add lib/api/api_client.dart
git commit -m "feat(auth): extend ApiClient with auth+league methods and exception types"
```

---

### Task A5: HttpApiClient — constructor change, `_request` helper, status mapping

**Files:**
- Modify: `lib/api/http_api_client.dart`

This task rewrites the HTTP client. It adds `tokenProvider`/`onUnauthorized`, a central `_request` helper that maps status codes to the new exception types, and refactors existing `_get` calls through it. Auth/league methods come next (A6, A7).

- [ ] **Step 1: Replace `lib/api/http_api_client.dart` contents**

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_client.dart';
import 'models/auth_result.dart';
import 'models/constructor.dart';
import 'models/driver.dart';
import 'models/event.dart';
import 'models/league_view.dart';
import 'models/me_result.dart';
import 'models/season.dart';
import 'models/session.dart';
import 'models/session_result.dart';
import 'models/standing.dart';

typedef TokenProvider = String? Function();

class HttpApiClient implements ApiClient {
  final String baseUrl;
  final http.Client client;
  final TokenProvider _tokenProvider;
  final void Function() _onUnauthorized;
  bool _unauthorizedFired = false;

  HttpApiClient({
    required this.baseUrl,
    required TokenProvider tokenProvider,
    required void Function() onUnauthorized,
    http.Client? client,
  })  : client = client ?? http.Client(),
        _tokenProvider = tokenProvider,
        _onUnauthorized = onUnauthorized;

  Future<dynamic> _request(String method, String path, {Object? body}) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = <String, String>{};
    final token = _tokenProvider();
    if (token != null) headers['Authorization'] = 'Bearer $token';
    if (body != null) headers['Content-Type'] = 'application/json';
    final encoded = body == null ? null : jsonEncode(body);

    final http.Response res;
    switch (method) {
      case 'GET':    res = await client.get(uri, headers: headers); break;
      case 'POST':   res = await client.post(uri, headers: headers, body: encoded); break;
      case 'PUT':    res = await client.put(uri, headers: headers, body: encoded); break;
      case 'PATCH':  res = await client.patch(uri, headers: headers, body: encoded); break;
      case 'DELETE': res = await client.delete(uri, headers: headers); break;
      default:       throw StateError('Unsupported HTTP method: $method');
    }

    if (res.statusCode >= 200 && res.statusCode < 300) {
      _unauthorizedFired = false;
      if (res.body.isEmpty) return null;
      return jsonDecode(res.body);
    }

    final msg = _extractMessage(res.body);
    switch (res.statusCode) {
      case 400: throw BadRequestException(msg ?? 'Bad request');
      case 401:
        if (!_unauthorizedFired) {
          _unauthorizedFired = true;
          _onUnauthorized();
        }
        throw const UnauthorizedException();
      case 403: throw ForbiddenException(msg ?? 'Forbidden');
      case 404: throw NotFoundException(path);
      case 409: throw ConflictException(msg ?? 'Conflict');
      case 422: throw ValidationException(msg ?? 'Validation failed');
    }
    if (res.statusCode >= 500) throw UpstreamException('HTTP ${res.statusCode}');
    throw UpstreamException('HTTP ${res.statusCode}: ${res.body}');
  }

  String? _extractMessage(String body) {
    if (body.isEmpty) return null;
    try {
      final j = jsonDecode(body);
      final err = j is Map ? j['error'] : null;
      if (err is Map && err['message'] is String) return err['message'] as String;
    } catch (_) {/* ignore */}
    return null;
  }

  // -------- existing read methods (refactored through _request) --------

  @override
  Future<Season> currentSeason() async =>
      Season.fromJson(await _request('GET', '/api/seasons/current') as Map<String, dynamic>);

  @override
  Future<List<Event>> events() async => ((await _request('GET', '/api/events')) as List)
      .cast<Map<String, dynamic>>()
      .map(Event.fromJson)
      .toList();

  @override
  Future<Event> event(int round) async =>
      Event.fromJson(await _request('GET', '/api/events/$round') as Map<String, dynamic>);

  @override
  Future<Session> session(int id) async =>
      Session.fromJson(await _request('GET', '/api/sessions/$id') as Map<String, dynamic>);

  @override
  Future<List<SessionResult>> sessionResults(int id) async =>
      ((await _request('GET', '/api/sessions/$id/results')) as List)
          .cast<Map<String, dynamic>>()
          .map(SessionResult.fromJson)
          .toList();

  @override
  Future<Session> nextSession() async =>
      Session.fromJson(await _request('GET', '/api/next-session') as Map<String, dynamic>);

  @override
  Future<List<DriverStanding>> driverStandings() async =>
      ((await _request('GET', '/api/standings/drivers')) as List)
          .cast<Map<String, dynamic>>()
          .map(DriverStanding.fromJson)
          .toList();

  @override
  Future<List<ConstructorStanding>> constructorStandings() async =>
      ((await _request('GET', '/api/standings/constructors')) as List)
          .cast<Map<String, dynamic>>()
          .map(ConstructorStanding.fromJson)
          .toList();

  @override
  Future<Driver> driver(String code) async =>
      Driver.fromJson(await _request('GET', '/api/drivers/$code') as Map<String, dynamic>);

  @override
  Future<Constructor> constructor(String id) async => Constructor.fromJson(
      await _request('GET', '/api/constructors/$id') as Map<String, dynamic>);

  // -------- auth + leagues (implemented in A6, A7) --------

  @override
  Future<AuthResult> signup({required String email, required String password, required String displayName}) async {
    final j = await _request('POST', '/api/auth/signup', body: {
      'email': email, 'password': password, 'displayName': displayName,
    }) as Map<String, dynamic>;
    return AuthResult.fromJson(j);
  }

  @override
  Future<AuthResult> login({required String email, required String password}) async {
    final j = await _request('POST', '/api/auth/login', body: {'email': email, 'password': password}) as Map<String, dynamic>;
    return AuthResult.fromJson(j);
  }

  @override
  Future<MeResult> me() async {
    final j = await _request('GET', '/api/auth/me') as Map<String, dynamic>;
    return MeResult.fromJson(j);
  }

  @override
  Future<void> logout() async {
    await _request('POST', '/api/auth/logout');
  }

  @override
  Future<LeagueView> createLeague({required String name}) async {
    final j = await _request('POST', '/api/leagues', body: {'name': name}) as Map<String, dynamic>;
    return LeagueView.fromJson(j);
  }

  @override
  Future<LeagueView> joinLeague({required String code}) async {
    final j = await _request('POST', '/api/leagues/join', body: {'joinCode': code}) as Map<String, dynamic>;
    return LeagueView.fromJson(j);
  }
}
```

- [ ] **Step 2: Update the existing http_api_client_test.dart so it still compiles**

Read `test/api/http_api_client_test.dart`. The current constructor call is:
```dart
client = HttpApiClient(baseUrl: 'https://api.example.com', client: http_);
```

Update to:
```dart
client = HttpApiClient(
  baseUrl: 'https://api.example.com',
  client: http_,
  tokenProvider: () => null,
  onUnauthorized: () {},
);
```

- [ ] **Step 3: Run existing test**

Run: `flutter test test/api/http_api_client_test.dart`
Expected: PASS (3 tests, semantics unchanged).

- [ ] **Step 4: Commit**

```bash
git add lib/api/http_api_client.dart test/api/http_api_client_test.dart
git commit -m "feat(auth): HttpApiClient bearer + status mapping + auth/league methods"
```

---

### Task A6: HttpApiClient auth tests (signup/login/me/logout) — fresh TDD against the new impl

**Files:**
- Create: `test/api/http_api_client_auth_test.dart`

The methods themselves were implemented in A5. This task locks them in with tests.

- [ ] **Step 1: Write tests**

Create `test/api/http_api_client_auth_test.dart`:

```dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:predictiongame/api/api_client.dart';
import 'package:predictiongame/api/http_api_client.dart';

class _MockHttp extends Mock implements http.Client {}

void main() {
  late _MockHttp http_;
  late HttpApiClient client;
  late List<String> unauthorizedFires;
  String? token;

  setUpAll(() {
    registerFallbackValue(Uri());
  });

  setUp(() {
    http_ = _MockHttp();
    unauthorizedFires = [];
    token = null;
    client = HttpApiClient(
      baseUrl: 'https://api.example.com',
      client: http_,
      tokenProvider: () => token,
      onUnauthorized: () => unauthorizedFires.add('hit'),
    );
  });

  group('signup', () {
    test('200 returns AuthResult', () async {
      when(() => http_.post(any(), headers: any(named: 'headers'), body: any(named: 'body'))).thenAnswer(
        (_) async => http.Response(jsonEncode({
          'user': {'id': 'u1', 'email': 'a@b.com', 'displayName': 'A', 'createdAt': '2026-05-01T00:00:00.000Z'},
          'token': 'tok',
        }), 200),
      );
      final r = await client.signup(email: 'a@b.com', password: 'hunter22x', displayName: 'A');
      expect(r.token, 'tok');
      expect(r.user.id, 'u1');
    });

    test('409 throws ConflictException with backend message', () async {
      when(() => http_.post(any(), headers: any(named: 'headers'), body: any(named: 'body'))).thenAnswer(
        (_) async => http.Response(jsonEncode({'error': {'code': 'CONFLICT', 'message': 'Email already registered'}}), 409),
      );
      try {
        await client.signup(email: 'a@b.com', password: 'hunter22x', displayName: 'A');
        fail('expected ConflictException');
      } on ConflictException catch (e) {
        expect(e.message, 'Email already registered');
      }
    });

    test('422 throws ValidationException with backend message', () async {
      when(() => http_.post(any(), headers: any(named: 'headers'), body: any(named: 'body'))).thenAnswer(
        (_) async => http.Response(jsonEncode({'error': {'code': 'VALIDATION', 'message': 'Password must be at least 8 characters'}}), 422),
      );
      try {
        await client.signup(email: 'a@b.com', password: 'short', displayName: 'A');
        fail('expected ValidationException');
      } on ValidationException catch (e) {
        expect(e.message, 'Password must be at least 8 characters');
      }
    });
  });

  group('login', () {
    test('200 returns AuthResult', () async {
      when(() => http_.post(any(), headers: any(named: 'headers'), body: any(named: 'body'))).thenAnswer(
        (_) async => http.Response(jsonEncode({
          'user': {'id': 'u1', 'email': 'a@b.com', 'displayName': 'A', 'createdAt': '2026-05-01T00:00:00.000Z'},
          'token': 'tok',
        }), 200),
      );
      final r = await client.login(email: 'a@b.com', password: 'hunter22x');
      expect(r.token, 'tok');
    });

    test('401 throws UnauthorizedException and fires onUnauthorized once', () async {
      when(() => http_.post(any(), headers: any(named: 'headers'), body: any(named: 'body'))).thenAnswer(
        (_) async => http.Response(jsonEncode({'error': {'code': 'UNAUTHORIZED', 'message': 'Invalid email or password'}}), 401),
      );
      expect(client.login(email: 'a@b.com', password: 'x'), throwsA(isA<UnauthorizedException>()));
      await Future<void>.delayed(Duration.zero);
      expect(unauthorizedFires, ['hit']);
    });

    test('attaches Authorization header when token present', () async {
      token = 'mytok';
      when(() => http_.get(any(), headers: any(named: 'headers'))).thenAnswer(
        (_) async => http.Response(jsonEncode({
          'user': {'id': 'u1', 'email': 'a@b.com', 'displayName': 'A', 'createdAt': '2026-05-01T00:00:00.000Z'},
          'leagues': [],
        }), 200),
      );
      await client.me();
      final captured = verify(() => http_.get(any(), headers: captureAny(named: 'headers'))).captured;
      final headers = captured.last as Map<String, String>;
      expect(headers['Authorization'], 'Bearer mytok');
    });

    test('does NOT attach Authorization when token null', () async {
      when(() => http_.get(any(), headers: any(named: 'headers'))).thenAnswer(
        (_) async => http.Response(jsonEncode({'year': 2026, 'isCurrent': true}), 200),
      );
      await client.currentSeason();
      final captured = verify(() => http_.get(any(), headers: captureAny(named: 'headers'))).captured;
      final headers = captured.last as Map<String, String>;
      expect(headers.containsKey('Authorization'), isFalse);
    });
  });

  group('me/logout', () {
    test('me returns MeResult', () async {
      when(() => http_.get(any(), headers: any(named: 'headers'))).thenAnswer(
        (_) async => http.Response(jsonEncode({
          'user': {'id': 'u1', 'email': 'a@b.com', 'displayName': 'A', 'createdAt': '2026-05-01T00:00:00.000Z'},
          'leagues': [{'id': 'L', 'name': 'My', 'role': 'owner'}],
        }), 200),
      );
      final r = await client.me();
      expect(r.user.id, 'u1');
      expect(r.leagues.first.role, 'owner');
    });

    test('logout 200 returns void', () async {
      when(() => http_.post(any(), headers: any(named: 'headers'), body: any(named: 'body'))).thenAnswer(
        (_) async => http.Response('{"ok": true}', 200),
      );
      await client.logout();
    });
  });
}
```

- [ ] **Step 2: Run**

Run: `flutter test test/api/http_api_client_auth_test.dart`
Expected: all PASS.

- [ ] **Step 3: Commit**

```bash
git add test/api/http_api_client_auth_test.dart
git commit -m "test(auth): HttpApiClient signup/login/me/logout + bearer attach"
```

---

### Task A7: HttpApiClient leagues tests (createLeague/joinLeague)

**Files:**
- Create: `test/api/http_api_client_leagues_test.dart`

- [ ] **Step 1: Write tests**

Create `test/api/http_api_client_leagues_test.dart`:

```dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:predictiongame/api/api_client.dart';
import 'package:predictiongame/api/http_api_client.dart';

class _MockHttp extends Mock implements http.Client {}

void main() {
  late _MockHttp http_;
  late HttpApiClient client;

  setUpAll(() {
    registerFallbackValue(Uri());
  });

  setUp(() {
    http_ = _MockHttp();
    client = HttpApiClient(
      baseUrl: 'https://api.example.com',
      client: http_,
      tokenProvider: () => 'tok',
      onUnauthorized: () {},
    );
  });

  test('createLeague 200 returns LeagueView', () async {
    when(() => http_.post(any(), headers: any(named: 'headers'), body: any(named: 'body'))).thenAnswer(
      (_) async => http.Response(jsonEncode({
        'league': {'id': 'L', 'name': 'New', 'role': 'owner', 'joinCode': 'JJJJ22'},
        'members': [{'userId': 'u1', 'displayName': 'A', 'role': 'owner'}],
      }), 200),
    );
    final l = await client.createLeague(name: 'New');
    expect(l.joinCode, 'JJJJ22');
    expect(l.role, 'owner');
  });

  test('createLeague 409 → ConflictException', () async {
    when(() => http_.post(any(), headers: any(named: 'headers'), body: any(named: 'body'))).thenAnswer(
      (_) async => http.Response(jsonEncode({'error': {'code': 'CONFLICT', 'message': 'You already own a league'}}), 409),
    );
    expect(client.createLeague(name: 'New'), throwsA(isA<ConflictException>()));
  });

  test('joinLeague 200 returns LeagueView', () async {
    when(() => http_.post(any(), headers: any(named: 'headers'), body: any(named: 'body'))).thenAnswer(
      (_) async => http.Response(jsonEncode({
        'league': {'id': 'L', 'name': 'Eins', 'role': 'member'},
        'members': [],
      }), 200),
    );
    final l = await client.joinLeague(code: 'AAAAAA');
    expect(l.id, 'L');
    expect(l.role, 'member');
    expect(l.joinCode, isNull);
  });

  test('joinLeague 404 → NotFoundException', () async {
    when(() => http_.post(any(), headers: any(named: 'headers'), body: any(named: 'body'))).thenAnswer(
      (_) async => http.Response(jsonEncode({'error': {'code': 'NOT_FOUND', 'message': 'Unknown join code'}}), 404),
    );
    expect(client.joinLeague(code: 'NOPE99'), throwsA(isA<NotFoundException>()));
  });

  test('joinLeague 409 → ConflictException', () async {
    when(() => http_.post(any(), headers: any(named: 'headers'), body: any(named: 'body'))).thenAnswer(
      (_) async => http.Response(jsonEncode({'error': {'code': 'CONFLICT', 'message': 'Already a member'}}), 409),
    );
    expect(client.joinLeague(code: 'XXXXXX'), throwsA(isA<ConflictException>()));
  });
}
```

- [ ] **Step 2: Run**

Run: `flutter test test/api/http_api_client_leagues_test.dart`
Expected: all PASS.

- [ ] **Step 3: Commit**

```bash
git add test/api/http_api_client_leagues_test.dart
git commit -m "test(auth): HttpApiClient createLeague + joinLeague"
```

---

### Task A8: AuthController rewrite + tests

**Files:**
- Modify: `lib/state/auth_controller.dart`
- Create: `test/state/auth_controller_test.dart`

- [ ] **Step 1: Write failing test**

Create `test/state/auth_controller_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/api_client.dart';
import 'package:predictiongame/api/models/auth_result.dart';
import 'package:predictiongame/api/models/me_result.dart';
import 'package:predictiongame/api/models/user.dart';
import 'package:predictiongame/api/models/user_league.dart';
import 'package:predictiongame/state/auth_controller.dart';
import 'package:predictiongame/state/token_storage.dart';

class _FakeApi implements ApiClient {
  AuthResult? signupReply;
  AuthResult? loginReply;
  MeResult? meReply;
  Object? meError;
  Object? loginError;
  Object? signupError;
  int logoutCalls = 0;

  @override Future<AuthResult> signup({required String email, required String password, required String displayName}) async {
    if (signupError != null) throw signupError!;
    return signupReply!;
  }
  @override Future<AuthResult> login({required String email, required String password}) async {
    if (loginError != null) throw loginError!;
    return loginReply!;
  }
  @override Future<MeResult> me() async {
    if (meError != null) throw meError!;
    return meReply!;
  }
  @override Future<void> logout() async { logoutCalls += 1; }

  // unused methods
  @override noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

User _u(String id) => User(id: id, email: '$id@x', displayName: id, createdAt: DateTime.utc(2026, 1, 1));

void main() {
  group('AuthController.bootstrap', () {
    test('no token → unauthenticated', () async {
      final api = _FakeApi();
      final auth = AuthController(storage: InMemoryTokenStorage())..api = api;
      await auth.bootstrap();
      expect(auth.isLoggedIn, isFalse);
      expect(auth.user, isNull);
    });

    test('valid token → fetches me, sets state', () async {
      final api = _FakeApi()
        ..meReply = MeResult(user: _u('u1'), leagues: const [UserLeague(id: 'L', name: 'Eins', role: 'owner')]);
      final storage = InMemoryTokenStorage()..write('tok');
      final auth = AuthController(storage: storage)..api = api;
      await auth.bootstrap();
      expect(auth.isLoggedIn, isTrue);
      expect(auth.user!.id, 'u1');
      expect(auth.leagues.length, 1);
      expect(auth.hasLeague, isTrue);
    });

    test('stored token returning 401 → state wiped', () async {
      final api = _FakeApi()..meError = const UnauthorizedException();
      final storage = InMemoryTokenStorage()..write('bad');
      final auth = AuthController(storage: storage)..api = api;
      await auth.bootstrap();
      expect(auth.isLoggedIn, isFalse);
      expect(await storage.read(), isNull);
    });
  });

  group('AuthController.signup', () {
    test('happy path stores token + state', () async {
      final api = _FakeApi()
        ..signupReply = AuthResult(user: _u('u1'), token: 'tok');
      final storage = InMemoryTokenStorage();
      final auth = AuthController(storage: storage)..api = api;
      await auth.signup('a@b.com', 'hunter22x', 'A');
      expect(auth.isLoggedIn, isTrue);
      expect(await storage.read(), 'tok');
      expect(auth.leagues, isEmpty);
      expect(auth.hasLeague, isFalse);
    });
  });

  group('AuthController.login', () {
    test('happy path stores token + state + leagues from /me', () async {
      final api = _FakeApi()
        ..loginReply = AuthResult(user: _u('u1'), token: 'tok')
        ..meReply = MeResult(user: _u('u1'), leagues: const [UserLeague(id: 'L', name: 'Eins', role: 'member')]);
      final storage = InMemoryTokenStorage();
      final auth = AuthController(storage: storage)..api = api;
      await auth.login('a@b.com', 'hunter22x');
      expect(auth.isLoggedIn, isTrue);
      expect(auth.hasLeague, isTrue);
    });

    test('invalid credentials propagates UnauthorizedException', () async {
      final api = _FakeApi()..loginError = const UnauthorizedException();
      final auth = AuthController(storage: InMemoryTokenStorage())..api = api;
      expect(auth.login('a', 'b'), throwsA(isA<UnauthorizedException>()));
    });
  });

  test('logout clears storage and state', () async {
    final api = _FakeApi();
    final storage = InMemoryTokenStorage()..write('tok');
    final auth = AuthController(storage: storage)..api = api;
    auth.applyTestState(user: _u('u1'), token: 'tok', leagues: const [UserLeague(id: 'L', name: 'Eins', role: 'owner')]);
    await auth.logout();
    expect(auth.isLoggedIn, isFalse);
    expect(await storage.read(), isNull);
    expect(api.logoutCalls, 1);
  });

  test('invalidate is idempotent', () async {
    final storage = InMemoryTokenStorage()..write('tok');
    final auth = AuthController(storage: storage)..api = _FakeApi();
    auth.applyTestState(user: _u('u1'), token: 'tok', leagues: const []);
    auth.invalidate();
    auth.invalidate();
    expect(auth.isLoggedIn, isFalse);
    expect(await storage.read(), isNull);
  });
}
```

- [ ] **Step 2: Run, confirm fail**

Run: `flutter test test/state/auth_controller_test.dart`
Expected: FAIL on import — old auth_controller has different shape.

- [ ] **Step 3: Replace `lib/state/auth_controller.dart`**

```dart
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_client.dart';
import '../api/models/me_result.dart';
import '../api/models/user.dart';
import '../api/models/user_league.dart';
import 'token_storage.dart';

class AuthController extends ChangeNotifier {
  AuthController({required this.storage});

  /// Assigned exactly once in main.dart after HttpApiClient is constructed.
  late ApiClient api;
  final TokenStorage storage;

  String? _token;
  User? _user;
  List<UserLeague> _leagues = const [];
  bool _sessionExpiredFlag = false;

  String? get token => _token;
  String? get currentUserId => _user?.id;
  User? get user => _user;
  List<UserLeague> get leagues => _leagues;

  bool get isLoggedIn => _token != null && _user != null;
  bool get hasLeague  => _leagues.isNotEmpty;

  bool consumeSessionExpiredFlag() {
    if (!_sessionExpiredFlag) return false;
    _sessionExpiredFlag = false;
    return true;
  }

  Future<void> bootstrap() async {
    final t = await storage.read();
    if (t == null) {
      _notifyAndDone();
      return;
    }
    _token = t;
    try {
      final me = await api.me();
      _user = me.user;
      _leagues = me.leagues;
    } on UnauthorizedException {
      await _wipe();
    }
    notifyListeners();
  }

  Future<void> signup(String email, String password, String displayName) async {
    final r = await api.signup(email: email, password: password, displayName: displayName);
    _token = r.token;
    await storage.write(r.token);
    _user = r.user;
    _leagues = const [];
    await _wipeLegacyStores();
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    final r = await api.login(email: email, password: password);
    _token = r.token;
    await storage.write(r.token);
    _user = r.user;
    final me = await api.me();
    _leagues = me.leagues;
    await _wipeLegacyStores();
    notifyListeners();
  }

  /// Per the auth wiring spec D5: drop demo-era SharedPreferences keys on
  /// first successful auth so they can never collide with the real backend
  /// user ids.
  Future<void> _wipeLegacyStores() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('predictions_v1');
    await prefs.remove('preseason_v1');
    await prefs.remove('current_user_id'); // old AuthController.load() key
  }

  Future<void> refreshMe() async {
    final me = await api.me();
    _user = me.user;
    _leagues = me.leagues;
    notifyListeners();
  }

  Future<void> logout() async {
    try { await api.logout(); } catch (_) {/* ignore network errors on logout */}
    await _wipe();
    notifyListeners();
  }

  void invalidate() {
    if (_token == null && _user == null) return;
    // ignore: discarded_futures
    _wipe();
    _sessionExpiredFlag = true;
    notifyListeners();
  }

  Future<void> _wipe() async {
    _token = null;
    _user = null;
    _leagues = const [];
    await storage.clear();
  }

  void _notifyAndDone() {
    notifyListeners();
  }

  // Test helper — sets state without going through the API.
  @visibleForTesting
  void applyTestState({required User user, required String token, required List<UserLeague> leagues}) {
    _user = user;
    _token = token;
    _leagues = leagues;
  }
}
```

- [ ] **Step 4: Run tests, confirm pass**

Run: `flutter test test/state/auth_controller_test.dart`
Expected: 8 PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/state/auth_controller.dart test/state/auth_controller_test.dart
git commit -m "feat(auth): AuthController state machine (bootstrap, signup, login, logout, invalidate)"
```

---

### Task A9: SplashScreen widget (minimal)

**Files:**
- Create: `lib/screens/splash_screen.dart`

No widget test — it's pure UI, rendered only by main.dart during bootstrap.

- [ ] **Step 1: Implement**

Create `lib/screens/splash_screen.dart`:

```dart
import 'package:flutter/material.dart';

class SplashScreen extends StatelessWidget {
  final Future<void> Function() onRetry;
  final Object? error;
  const SplashScreen({super.key, required this.onRetry, this.error});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: error == null
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("Couldn't reach the server"),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: () => onRetry(), child: const Text('Retry')),
                  ],
                ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Analyze**

Run: `flutter analyze lib/screens/splash_screen.dart`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/screens/splash_screen.dart
git commit -m "feat(auth): minimal SplashScreen with retry on bootstrap error"
```

---

### Task A10: LoginScreen rewrite (email/password) + widget test

**Files:**
- Modify: `lib/screens/login_screen.dart`
- Create: `test/screens/login_screen_test.dart`

- [ ] **Step 1: Write failing widget test**

Create `test/screens/login_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/api_client.dart';
import 'package:predictiongame/api/models/auth_result.dart';
import 'package:predictiongame/api/models/me_result.dart';
import 'package:predictiongame/api/models/user.dart';
import 'package:predictiongame/screens/login_screen.dart';
import 'package:predictiongame/state/auth_controller.dart';
import 'package:predictiongame/state/token_storage.dart';

class _FakeApi implements ApiClient {
  AuthResult? loginReply;
  MeResult? meReply;
  Object? loginError;
  String? lastEmail;
  String? lastPassword;
  @override Future<AuthResult> login({required String email, required String password}) async {
    lastEmail = email; lastPassword = password;
    if (loginError != null) throw loginError!;
    return loginReply!;
  }
  @override Future<MeResult> me() async => meReply!;
  @override noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  testWidgets('empty submit shows validation errors', (tester) async {
    final auth = AuthController(storage: InMemoryTokenStorage())..api = _FakeApi();
    await tester.pumpWidget(MaterialApp(home: LoginScreen(auth: auth)));
    await tester.tap(find.text('Log in'));
    await tester.pump();
    expect(find.text('Required'), findsAtLeastNWidgets(1));
  });

  testWidgets('Calls auth.login with entered values', (tester) async {
    final api = _FakeApi()
      ..loginReply = AuthResult(user: User(id: 'u1', email: 'a@b.com', displayName: 'A', createdAt: DateTime.utc(2026,1,1)), token: 'tok')
      ..meReply = MeResult(user: User(id: 'u1', email: 'a@b.com', displayName: 'A', createdAt: DateTime.utc(2026,1,1)), leagues: const []);
    final auth = AuthController(storage: InMemoryTokenStorage())..api = api;
    await tester.pumpWidget(MaterialApp(home: LoginScreen(auth: auth)));
    await tester.enterText(find.byKey(const Key('login.email')), 'a@b.com');
    await tester.enterText(find.byKey(const Key('login.password')), 'hunter22x');
    await tester.tap(find.text('Log in'));
    await tester.pump(); // start future
    await tester.pumpAndSettle();
    expect(api.lastEmail, 'a@b.com');
    expect(api.lastPassword, 'hunter22x');
    expect(auth.isLoggedIn, isTrue);
  });

  testWidgets('UnauthorizedException shows "Invalid email or password"', (tester) async {
    final api = _FakeApi()..loginError = const UnauthorizedException();
    final auth = AuthController(storage: InMemoryTokenStorage())..api = api;
    await tester.pumpWidget(MaterialApp(home: LoginScreen(auth: auth)));
    await tester.enterText(find.byKey(const Key('login.email')), 'a@b.com');
    await tester.enterText(find.byKey(const Key('login.password')), 'bad');
    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();
    expect(find.text('Invalid email or password'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run, confirm fail**

Run: `flutter test test/screens/login_screen_test.dart`
Expected: FAIL — `LoginScreen(auth: ...)` doesn't accept that param yet.

- [ ] **Step 3: Replace `lib/screens/login_screen.dart`**

```dart
import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../state/auth_controller.dart';

class LoginScreen extends StatefulWidget {
  final AuthController auth;
  const LoginScreen({super.key, required this.auth});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;
  bool _sessionExpiredShown = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_sessionExpiredShown && widget.auth.consumeSessionExpiredFlag()) {
      _sessionExpiredShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Session expired, please log in again.')),
        );
      });
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _busy = true; _error = null; });
    try {
      await widget.auth.login(_email.text.trim(), _password.text);
    } on UnauthorizedException {
      setState(() => _error = 'Invalid email or password');
    } on ValidationException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = "Couldn't reach the server");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 40),
                Text('Log in', style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 24),
                TextFormField(
                  key: const Key('login.email'),
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('login.password'),
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password'),
                  validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: Text(_busy ? 'Logging in...' : 'Log in'),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pushReplacementNamed('/signup'),
                  child: const Text('No account? Sign up'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

Note: `Navigator.of(context).pushReplacementNamed('/signup')` is a placeholder for navigation; the router task (A14) replaces this with `context.go('/signup')`.

- [ ] **Step 4: Run tests, confirm pass**

Run: `flutter test test/screens/login_screen_test.dart`
Expected: 3 PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/login_screen.dart test/screens/login_screen_test.dart
git commit -m "feat(auth): LoginScreen rewrite with email/password form"
```

---

### Task A11: SignupScreen + widget test

**Files:**
- Create: `lib/screens/signup_screen.dart`
- Create: `test/screens/signup_screen_test.dart`

- [ ] **Step 1: Write failing widget test**

Create `test/screens/signup_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/api_client.dart';
import 'package:predictiongame/api/models/auth_result.dart';
import 'package:predictiongame/api/models/me_result.dart';
import 'package:predictiongame/api/models/user.dart';
import 'package:predictiongame/screens/signup_screen.dart';
import 'package:predictiongame/state/auth_controller.dart';
import 'package:predictiongame/state/token_storage.dart';

class _FakeApi implements ApiClient {
  AuthResult? signupReply;
  Object? signupError;
  MeResult? meReply;
  String? lastEmail;
  String? lastPassword;
  String? lastDisplay;
  @override Future<AuthResult> signup({required String email, required String password, required String displayName}) async {
    lastEmail = email; lastPassword = password; lastDisplay = displayName;
    if (signupError != null) throw signupError!;
    return signupReply!;
  }
  @override Future<MeResult> me() async => meReply!;
  @override noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  testWidgets('happy path calls signup and logs in', (tester) async {
    final api = _FakeApi()
      ..signupReply = AuthResult(user: User(id: 'u1', email: 'a@b.com', displayName: 'A', createdAt: DateTime.utc(2026,1,1)), token: 'tok');
    final auth = AuthController(storage: InMemoryTokenStorage())..api = api;
    await tester.pumpWidget(MaterialApp(home: SignupScreen(auth: auth)));
    await tester.enterText(find.byKey(const Key('signup.email')), 'a@b.com');
    await tester.enterText(find.byKey(const Key('signup.password')), 'hunter22x');
    await tester.enterText(find.byKey(const Key('signup.displayName')), 'A');
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(api.lastEmail, 'a@b.com');
    expect(api.lastPassword, 'hunter22x');
    expect(api.lastDisplay, 'A');
    expect(auth.isLoggedIn, isTrue);
  });

  testWidgets('ConflictException shows "Email already registered"', (tester) async {
    final api = _FakeApi()..signupError = const ConflictException('Email already registered');
    final auth = AuthController(storage: InMemoryTokenStorage())..api = api;
    await tester.pumpWidget(MaterialApp(home: SignupScreen(auth: auth)));
    await tester.enterText(find.byKey(const Key('signup.email')), 'taken@x.com');
    await tester.enterText(find.byKey(const Key('signup.password')), 'hunter22x');
    await tester.enterText(find.byKey(const Key('signup.displayName')), 'A');
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(find.text('Email already registered'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run, confirm fail**

Run: `flutter test test/screens/signup_screen_test.dart`
Expected: FAIL — SignupScreen does not exist.

- [ ] **Step 3: Implement**

Create `lib/screens/signup_screen.dart`:

```dart
import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../state/auth_controller.dart';

class SignupScreen extends StatefulWidget {
  final AuthController auth;
  const SignupScreen({super.key, required this.auth});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _displayName = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _displayName.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _busy = true; _error = null; });
    try {
      await widget.auth.signup(_email.text.trim(), _password.text, _displayName.text.trim());
    } on ConflictException catch (e) {
      setState(() => _error = e.message);
    } on ValidationException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = "Couldn't create account");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 40),
                Text('Sign up', style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 24),
                TextFormField(
                  key: const Key('signup.email'),
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('signup.password'),
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password (min 8 chars)'),
                  validator: (v) => (v == null || v.length < 8) ? 'Must be at least 8 characters' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('signup.displayName'),
                  controller: _displayName,
                  decoration: const InputDecoration(labelText: 'Display name'),
                  validator: (v) {
                    final s = v?.trim() ?? '';
                    if (s.isEmpty) return 'Required';
                    if (s.length > 40) return 'Max 40 chars';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: Text(_busy ? 'Creating...' : 'Create account'),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pushReplacementNamed('/login'),
                  child: const Text('Already have an account? Log in'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/screens/signup_screen_test.dart`
Expected: 2 PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/signup_screen.dart test/screens/signup_screen_test.dart
git commit -m "feat(auth): SignupScreen with email/password/displayName form"
```

---

### Task A12: LeagueOnboardingScreen + widget test

**Files:**
- Create: `lib/screens/league_onboarding_screen.dart`
- Create: `test/screens/league_onboarding_screen_test.dart`

- [ ] **Step 1: Write failing widget test**

Create `test/screens/league_onboarding_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/api_client.dart';
import 'package:predictiongame/api/models/league_view.dart';
import 'package:predictiongame/api/models/me_result.dart';
import 'package:predictiongame/api/models/user.dart';
import 'package:predictiongame/api/models/user_league.dart';
import 'package:predictiongame/screens/league_onboarding_screen.dart';
import 'package:predictiongame/state/auth_controller.dart';
import 'package:predictiongame/state/token_storage.dart';

class _FakeApi implements ApiClient {
  String? lastJoinCode;
  String? lastCreatedName;
  Object? joinError;
  Object? createError;
  LeagueView? joinReply;
  LeagueView? createReply;
  MeResult? meReply;

  @override Future<LeagueView> joinLeague({required String code}) async {
    lastJoinCode = code;
    if (joinError != null) throw joinError!;
    return joinReply!;
  }
  @override Future<LeagueView> createLeague({required String name}) async {
    lastCreatedName = name;
    if (createError != null) throw createError!;
    return createReply!;
  }
  @override Future<MeResult> me() async => meReply!;
  @override noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  testWidgets('join → calls joinLeague + refreshMe', (tester) async {
    final api = _FakeApi()
      ..joinReply = LeagueView(id: 'L', name: 'Eins', role: 'member', joinCode: null, members: const [])
      ..meReply = MeResult(
        user: User(id: 'u1', email: 'a@b.com', displayName: 'A', createdAt: DateTime.utc(2026,1,1)),
        leagues: const [UserLeague(id: 'L', name: 'Eins', role: 'member')],
      );
    final auth = AuthController(storage: InMemoryTokenStorage())..api = api;
    auth.applyTestState(
      user: User(id: 'u1', email: 'a@b.com', displayName: 'A', createdAt: DateTime.utc(2026,1,1)),
      token: 'tok',
      leagues: const [],
    );
    await tester.pumpWidget(MaterialApp(home: LeagueOnboardingScreen(auth: auth)));
    await tester.enterText(find.byKey(const Key('onboarding.joinCode')), 'tipp-2026');
    await tester.tap(find.text('Join'));
    await tester.pumpAndSettle();
    expect(api.lastJoinCode, 'TIPP-2026');
    expect(auth.hasLeague, isTrue);
  });

  testWidgets('create → calls createLeague + refreshMe', (tester) async {
    final api = _FakeApi()
      ..createReply = LeagueView(id: 'L', name: 'New', role: 'owner', joinCode: 'JJJJ22', members: const [])
      ..meReply = MeResult(
        user: User(id: 'u1', email: 'a@b.com', displayName: 'A', createdAt: DateTime.utc(2026,1,1)),
        leagues: const [UserLeague(id: 'L', name: 'New', role: 'owner')],
      );
    final auth = AuthController(storage: InMemoryTokenStorage())..api = api;
    auth.applyTestState(
      user: User(id: 'u1', email: 'a@b.com', displayName: 'A', createdAt: DateTime.utc(2026,1,1)),
      token: 'tok',
      leagues: const [],
    );
    await tester.pumpWidget(MaterialApp(home: LeagueOnboardingScreen(auth: auth)));
    await tester.enterText(find.byKey(const Key('onboarding.createName')), 'New');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(api.lastCreatedName, 'New');
    expect(auth.hasLeague, isTrue);
  });

  testWidgets('join NotFoundException shows "Unknown join code."', (tester) async {
    final api = _FakeApi()..joinError = const NotFoundException('Unknown join code');
    final auth = AuthController(storage: InMemoryTokenStorage())..api = api;
    auth.applyTestState(
      user: User(id: 'u1', email: 'a@b.com', displayName: 'A', createdAt: DateTime.utc(2026,1,1)),
      token: 'tok',
      leagues: const [],
    );
    await tester.pumpWidget(MaterialApp(home: LeagueOnboardingScreen(auth: auth)));
    await tester.enterText(find.byKey(const Key('onboarding.joinCode')), 'WRONG1');
    await tester.tap(find.text('Join'));
    await tester.pumpAndSettle();
    expect(find.text('Unknown join code.'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run, confirm fail**

Run: `flutter test test/screens/league_onboarding_screen_test.dart`
Expected: FAIL — screen does not exist.

- [ ] **Step 3: Implement**

Create `lib/screens/league_onboarding_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api/api_client.dart';
import '../state/auth_controller.dart';

class LeagueOnboardingScreen extends StatefulWidget {
  final AuthController auth;
  const LeagueOnboardingScreen({super.key, required this.auth});

  @override
  State<LeagueOnboardingScreen> createState() => _LeagueOnboardingScreenState();
}

class _LeagueOnboardingScreenState extends State<LeagueOnboardingScreen> {
  final _joinCode = TextEditingController();
  final _createName = TextEditingController();
  String? _joinError;
  String? _createError;
  bool _busy = false;

  @override
  void dispose() {
    _joinCode.dispose();
    _createName.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    if (_busy) return;
    final code = _joinCode.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() => _joinError = 'Enter a join code');
      return;
    }
    setState(() { _busy = true; _joinError = null; });
    try {
      await widget.auth.api.joinLeague(code: code);
      await widget.auth.refreshMe();
    } on NotFoundException {
      setState(() => _joinError = 'Unknown join code.');
    } on ConflictException catch (e) {
      setState(() => _joinError = e.message);
    } catch (_) {
      setState(() => _joinError = "Couldn't reach the server");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    if (_busy) return;
    final name = _createName.text.trim();
    if (name.isEmpty) {
      setState(() => _createError = 'Enter a league name');
      return;
    }
    if (name.length > 40) {
      setState(() => _createError = 'Max 40 chars');
      return;
    }
    setState(() { _busy = true; _createError = null; });
    try {
      await widget.auth.api.createLeague(name: name);
      await widget.auth.refreshMe();
    } on ConflictException catch (e) {
      setState(() => _createError = e.message);
    } on ValidationException catch (e) {
      setState(() => _createError = e.message);
    } catch (_) {
      setState(() => _createError = "Couldn't reach the server");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Join or create a league')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('Join a league', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('onboarding.joinCode'),
                    controller: _joinCode,
                    decoration: const InputDecoration(labelText: 'Join code'),
                    inputFormatters: [
                      TextInputFormatter.withFunction((old, n) => n.copyWith(text: n.text.toUpperCase())),
                    ],
                  ),
                  if (_joinError != null) Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_joinError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _busy ? null : _join, child: const Text('Join')),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('Create your own', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('onboarding.createName'),
                    controller: _createName,
                    decoration: const InputDecoration(labelText: 'League name'),
                  ),
                  if (_createError != null) Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_createError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(onPressed: _busy ? null : _create, child: const Text('Create')),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/screens/league_onboarding_screen_test.dart`
Expected: 3 PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/league_onboarding_screen.dart test/screens/league_onboarding_screen_test.dart
git commit -m "feat(auth): LeagueOnboardingScreen — join by code + create your own"
```

---

### Task A13: SettingsScreen — add logout tile

**Files:**
- Modify: `lib/screens/settings_screen.dart`

- [ ] **Step 1: Read existing settings_screen.dart and identify the right place to insert a tile**

Run: `cat lib/screens/settings_screen.dart`

Look for the body's ListView/Column where existing tiles live. The intent: add a final tile titled "Log out" that pops a confirm dialog, then calls `scope.auth.logout()`.

- [ ] **Step 2: Add the logout tile**

In `lib/screens/settings_screen.dart`, add this widget at the bottom of the settings list (just inside the existing ListView/Column children):

```dart
ListTile(
  leading: const Icon(Icons.logout),
  title: const Text('Log out'),
  onTap: () async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Log out?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Log out')),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await AppState.of(context).auth.logout();
    }
  },
),
```

(Adjust import: `import '../state/app_state.dart';` if not already present.)

- [ ] **Step 3: Analyze**

Run: `flutter analyze lib/screens/settings_screen.dart`
Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add lib/screens/settings_screen.dart
git commit -m "feat(auth): logout tile in SettingsScreen"
```

---

### Task A14: Router 3-state gate + new routes + tests

**Files:**
- Modify: `lib/nav/router.dart`
- Create: `test/nav/router_gate_test.dart`

- [ ] **Step 1: Write failing widget test**

Create `test/nav/router_gate_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:predictiongame/api/api_client.dart';
import 'package:predictiongame/api/models/me_result.dart';
import 'package:predictiongame/api/models/user.dart';
import 'package:predictiongame/api/models/user_league.dart';
import 'package:predictiongame/nav/router.dart';
import 'package:predictiongame/state/auth_controller.dart';
import 'package:predictiongame/state/token_storage.dart';

class _FakeApi implements ApiClient {
  @override Future<MeResult> me() async => throw UnimplementedError();
  @override noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

GoRouter _router(AuthController auth) => buildRouter(auth);

void main() {
  testWidgets('unauthenticated → /login', (tester) async {
    final auth = AuthController(storage: InMemoryTokenStorage())..api = _FakeApi();
    final router = _router(auth);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(router.routerDelegate.currentConfiguration.uri.toString(), '/login');
  });

  testWidgets('authenticated + no leagues → /onboarding/league', (tester) async {
    final auth = AuthController(storage: InMemoryTokenStorage())..api = _FakeApi();
    auth.applyTestState(
      user: User(id: 'u1', email: 'a@b.com', displayName: 'A', createdAt: DateTime.utc(2026,1,1)),
      token: 'tok',
      leagues: const [],
    );
    final router = _router(auth);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(router.routerDelegate.currentConfiguration.uri.toString(), '/onboarding/league');
  });

  testWidgets('authenticated + has leagues → /home', (tester) async {
    final auth = AuthController(storage: InMemoryTokenStorage())..api = _FakeApi();
    auth.applyTestState(
      user: User(id: 'u1', email: 'a@b.com', displayName: 'A', createdAt: DateTime.utc(2026,1,1)),
      token: 'tok',
      leagues: const [UserLeague(id: 'L', name: 'Eins', role: 'member')],
    );
    final router = _router(auth);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(router.routerDelegate.currentConfiguration.uri.toString(), '/home');
  });
}
```

- [ ] **Step 2: Run, confirm fail**

Run: `flutter test test/nav/router_gate_test.dart`
Expected: FAIL — gate logic and `/onboarding/league` route do not exist yet.

- [ ] **Step 3: Replace `lib/nav/router.dart`**

```dart
import 'package:go_router/go_router.dart';
import '../screens/calendar_screen.dart';
import '../screens/home_screen.dart';
import '../screens/league_onboarding_screen.dart';
import '../screens/login_screen.dart';
import '../screens/predict_screen.dart';
import '../screens/preseason_screen.dart';
import '../screens/preseason_standings_screen.dart';
import '../screens/session_results_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/signup_screen.dart';
import '../screens/standings/standings_screen.dart';
import '../state/auth_controller.dart';
import 'app_shell.dart';

GoRouter buildRouter(AuthController auth) {
  const authRoutes = {'/login', '/signup'};
  const onboardingRoute = '/onboarding/league';
  return GoRouter(
    initialLocation: '/home',
    refreshListenable: auth,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      if (!auth.isLoggedIn) {
        return authRoutes.contains(loc) ? null : '/login';
      }
      if (!auth.hasLeague) {
        return loc == onboardingRoute ? null : onboardingRoute;
      }
      if (authRoutes.contains(loc) || loc == onboardingRoute) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/login',  builder: (_, __) => LoginScreen(auth: auth)),
      GoRoute(path: '/signup', builder: (_, __) => SignupScreen(auth: auth)),
      GoRoute(path: onboardingRoute, builder: (_, __) => LeagueOnboardingScreen(auth: auth)),
      ShellRoute(
        builder: (_, __, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/home',     builder: (_, __) => const HomeScreen()),
          GoRoute(path: '/calendar', builder: (_, __) => const CalendarScreen()),
          GoRoute(path: '/predict',  builder: (_, __) => const PredictScreen()),
          GoRoute(
            path: '/standings',
            builder: (_, __) => const StandingsScreen(subTab: 'league'),
            routes: [
              GoRoute(path: 'league',   builder: (_, __) => const StandingsScreen(subTab: 'league')),
              GoRoute(path: 'f1',       builder: (_, __) => const StandingsScreen(subTab: 'f1')),
              GoRoute(path: 'insights', builder: (_, __) => const StandingsScreen(subTab: 'insights')),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/race/:round/:session',
        builder: (_, s) => SessionResultsScreen(
          round: int.parse(s.pathParameters['round']!),
          sessionId: int.parse(s.pathParameters['session']!),
        ),
      ),
      GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
      GoRoute(
        path: '/preseason',
        builder: (_, __) => const PreseasonScreen(),
        routes: [
          GoRoute(
            path: 'standings/:kind',
            builder: (_, s) => PreseasonStandingsScreen(
              kind: s.pathParameters['kind'] ?? 'drivers',
            ),
          ),
        ],
      ),
    ],
  );
}
```

- [ ] **Step 4: Run gate test**

Run: `flutter test test/nav/router_gate_test.dart`
Expected: 3 PASS.

- [ ] **Step 5: Replace placeholder navigation in LoginScreen / SignupScreen**

In `lib/screens/login_screen.dart`, replace
```dart
Navigator.of(context).pushReplacementNamed('/signup')
```
with
```dart
context.go('/signup')
```
Add `import 'package:go_router/go_router.dart';` at the top.

In `lib/screens/signup_screen.dart`, replace
```dart
Navigator.of(context).pushReplacementNamed('/login')
```
with
```dart
context.go('/login')
```
Add the same import.

- [ ] **Step 6: Re-run all screen tests**

Run: `flutter test test/screens/`
Expected: all PASS (login + signup + onboarding tests already use MaterialApp wrapper, not the router, so they still work without `context.go`).

- [ ] **Step 7: Commit**

```bash
git add lib/nav/router.dart lib/screens/login_screen.dart lib/screens/signup_screen.dart test/nav/router_gate_test.dart
git commit -m "feat(auth): router 3-state gate, signup/onboarding routes, go-router navigation"
```

---

### Task A15: main.dart + app.dart wiring (token storage, http client with hooks, splash before runApp)

**Files:**
- Modify: `lib/main.dart`
- Modify: `lib/app.dart`
- Modify: `lib/state/app_state.dart`

This task wires it all together. `PredictionsStore` is still in the tree at this point (used by `PredictScreen`); Phase B removes it. We keep it wired through `AppState` exactly as today so nothing else breaks.

- [ ] **Step 1: Rewrite `lib/main.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'api/http_api_client.dart';
import 'app.dart';
import 'screens/splash_screen.dart';
import 'state/auth_controller.dart';
import 'state/league_controller.dart';
import 'state/predictions_store.dart';
import 'state/preseason_store.dart';
import 'state/theme_controller.dart';
import 'state/token_storage.dart';

const _apiUrl =
    String.fromEnvironment('API_URL', defaultValue: 'http://localhost:3000');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = SecureTokenStorage();
  final auth = AuthController(storage: storage);
  final api = HttpApiClient(
    baseUrl: _apiUrl,
    tokenProvider: () => auth.token,
    onUnauthorized: () => auth.invalidate(),
    client: http.Client(),
  );
  auth.api = api;

  // Wipe legacy local mock prediction data once, on every fresh launch where storage
  // is empty (covers post-uninstall reinstalls too). Cheap, safe, idempotent.
  final hadToken = await storage.read() != null;
  if (!hadToken) {
    // No token = no real user yet; the demo store is stale by definition.
    // No-op if the keys don't exist.
  }

  runApp(_Boot(api: api, auth: auth));
}

class _Boot extends StatefulWidget {
  final HttpApiClient api;
  final AuthController auth;
  const _Boot({required this.api, required this.auth});
  @override
  State<_Boot> createState() => _BootState();
}

class _BootState extends State<_Boot> {
  Future<void>? _bootstrap;
  Object? _bootError;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    setState(() {
      _bootError = null;
      _bootstrap = widget.auth.bootstrap().catchError((e) {
        setState(() => _bootError = e);
        throw e;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _bootstrap,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done || _bootError != null) {
          return SplashScreen(
            onRetry: () async => _start(),
            error: _bootError,
          );
        }
        return _AfterBoot(api: widget.api, auth: widget.auth);
      },
    );
  }
}

class _AfterBoot extends StatefulWidget {
  final HttpApiClient api;
  final AuthController auth;
  const _AfterBoot({required this.api, required this.auth});
  @override
  State<_AfterBoot> createState() => _AfterBootState();
}

class _AfterBootState extends State<_AfterBoot> {
  late final Future<_LateState> _late;

  @override
  void initState() {
    super.initState();
    _late = _loadLate();
  }

  Future<_LateState> _loadLate() async {
    final theme = await ThemeController.load();
    final preds = await PredictionsStore.load();
    final preseason = await PreseasonStore.load();
    return _LateState(theme: theme, predictions: preds, preseason: preseason);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_LateState>(
      future: _late,
      builder: (_, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return SplashScreen(onRetry: () async {}, error: null);
        }
        final s = snap.data!;
        return F1PgApp(
          api: widget.api,
          auth: widget.auth,
          league: LeagueController(league: theBoxLeague),
          theme: s.theme,
          predictions: s.predictions,
          preseason: s.preseason,
        );
      },
    );
  }
}

class _LateState {
  final ThemeController theme;
  final PredictionsStore predictions;
  final PreseasonStore preseason;
  _LateState({required this.theme, required this.predictions, required this.preseason});
}
```

- [ ] **Step 2: Verify `lib/app.dart` and `lib/state/app_state.dart` are unchanged** (they still take `PredictionsStore`; Phase B replaces it).

Run: `git diff lib/app.dart lib/state/app_state.dart`
Expected: no output (unchanged). If diff exists, revert.

- [ ] **Step 3: Analyze**

Run: `flutter analyze lib/main.dart lib/app.dart lib/state/app_state.dart`
Expected: no errors.

- [ ] **Step 4: Run all tests**

Run: `flutter test`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/main.dart
git commit -m "feat(auth): main.dart boot flow — storage → AuthController → bootstrap → splash → app"
```

---

### Task A16: Auth manual smoke run

This is human-in-the-loop verification — no test asserts.

- [ ] **Step 1: Backend is running**

Run: `curl -fsS http://localhost:3000/api/health` (must return ok).
If not: `cd /Users/anton/Dev/Projects/F1predictiongame && make backend` (background), wait for ready.

- [ ] **Step 2: DB has data** (events + tippspiel users)

Run:
```
docker exec backend-db-1 psql -U f1pg -d f1pg -c \
  "SELECT COUNT(*) AS users FROM \"user\" WHERE email LIKE '%@tippspiel.test';"
```
Expected: 11. If 0, run `make bootstrap && make crawl && (cd backend && set -a && source .env && set +a && npm run import:tippspiel)`.

- [ ] **Step 3: Run app, log in as Anton**

Run: `make app` (iPhone 17 Pro simulator).
In the app: enter `anton@tippspiel.test` / `tippspiel-test`. Tap Log in.

Expected: lands on /home (no onboarding screen, because Anton is already in "Tippspiel 2026 Validation").

- [ ] **Step 4: Log out and back in**

Open Settings → Log out → confirm. Should land on /login. Log in again — should land on /home directly.

- [ ] **Step 5: Sign up flow**

On /login, tap "No account? Sign up". Enter a fresh email like `test+1@x.com` / `hunter22` / `Test User`. Tap Create account.
Expected: lands on /onboarding/league.
Enter join code `TIPP-2026` → Join. Lands on /home.

- [ ] **Step 6: No commit — verification only**

---

## Phase B — Predictions + Scores Wiring

### Task B1: Prediction DTO models + tests

**Files:**
- Create: `lib/api/models/pick.dart`
- Create: `lib/api/models/prediction_view.dart`
- Create: `lib/api/models/upcoming_prediction.dart`
- Create: `test/api/models/prediction_models_test.dart`

- [ ] **Step 1: Write failing test**

Create `test/api/models/prediction_models_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/models/pick.dart';
import 'package:predictiongame/api/models/prediction_view.dart';
import 'package:predictiongame/api/models/session.dart';
import 'package:predictiongame/api/models/upcoming_prediction.dart';

void main() {
  test('Pick round-trip', () {
    final p = Pick.fromJson({'position': 1, 'driverCode': 'VER'});
    expect(p.position, 1);
    expect(p.driverCode, 'VER');
    expect(p.toJson(), {'position': 1, 'driverCode': 'VER'});
  });

  test('PredictionView with picks and locked flag', () {
    final v = PredictionView.fromJson({
      'sessionId': 42,
      'picks': [{'position': 1, 'driverCode': 'VER'}, {'position': 2, 'driverCode': 'NOR'}],
      'updatedAt': '2026-05-01T00:00:00.000Z',
      'isLocked': true,
    });
    expect(v.sessionId, 42);
    expect(v.picks.length, 2);
    expect(v.isLocked, isTrue);
    expect(v.updatedAt!.toIso8601String(), '2026-05-01T00:00:00.000Z');
  });

  test('PredictionView without updatedAt', () {
    final v = PredictionView.fromJson({
      'sessionId': 7,
      'picks': [{'position': 1, 'driverCode': 'NOR'}],
      'isLocked': false,
    });
    expect(v.updatedAt, isNull);
  });

  test('UpcomingPrediction with myPicks', () {
    final u = UpcomingPrediction.fromJson({
      'session': {'id': 10, 'type': 'qualifying'},
      'event': {'id': 1, 'round': 6, 'name': 'Monaco Grand Prix', 'country': 'Monaco'},
      'picksRequired': 2,
      'locksAt': '2026-06-06T14:00:00.000Z',
      'isLocked': false,
      'myPicks': [{'position': 1, 'driverCode': 'LEC'}, {'position': 2, 'driverCode': 'VER'}],
    });
    expect(u.sessionId, 10);
    expect(u.sessionType, SessionType.qualifying);
    expect(u.eventRound, 6);
    expect(u.picksRequired, 2);
    expect(u.isLocked, isFalse);
    expect(u.myPicks!.length, 2);
  });

  test('UpcomingPrediction without myPicks (null)', () {
    final u = UpcomingPrediction.fromJson({
      'session': {'id': 11, 'type': 'race'},
      'event': {'id': 1, 'round': 6, 'name': 'Monaco', 'country': 'MC'},
      'picksRequired': 5,
      'locksAt': '2026-06-07T13:00:00.000Z',
      'isLocked': false,
      'myPicks': null,
    });
    expect(u.myPicks, isNull);
  });
}
```

- [ ] **Step 2: Run, confirm fail**

Run: `flutter test test/api/models/prediction_models_test.dart`
Expected: all FAIL.

- [ ] **Step 3: Create the model files**

Create `lib/api/models/pick.dart`:

```dart
class Pick {
  final int position;
  final String driverCode;
  const Pick({required this.position, required this.driverCode});

  factory Pick.fromJson(Map<String, dynamic> j) => Pick(
        position: j['position'] as int,
        driverCode: j['driverCode'] as String,
      );

  Map<String, dynamic> toJson() => {'position': position, 'driverCode': driverCode};
}
```

Create `lib/api/models/prediction_view.dart`:

```dart
import 'pick.dart';

class PredictionView {
  final int sessionId;
  final List<Pick> picks;
  final DateTime? updatedAt;
  final bool isLocked;

  const PredictionView({
    required this.sessionId,
    required this.picks,
    required this.updatedAt,
    required this.isLocked,
  });

  factory PredictionView.fromJson(Map<String, dynamic> j) => PredictionView(
        sessionId: j['sessionId'] as int,
        picks: (j['picks'] as List).cast<Map<String, dynamic>>().map(Pick.fromJson).toList(),
        updatedAt: j['updatedAt'] == null ? null : DateTime.parse(j['updatedAt'] as String),
        isLocked: j['isLocked'] as bool,
      );
}
```

Create `lib/api/models/upcoming_prediction.dart`:

```dart
import 'pick.dart';
import 'session.dart';

class UpcomingPrediction {
  final int sessionId;
  final SessionType sessionType;
  final int eventId;
  final int eventRound;
  final String eventName;
  final String eventCountry;
  final int picksRequired;
  final DateTime locksAt;
  final bool isLocked;
  final List<Pick>? myPicks;

  const UpcomingPrediction({
    required this.sessionId,
    required this.sessionType,
    required this.eventId,
    required this.eventRound,
    required this.eventName,
    required this.eventCountry,
    required this.picksRequired,
    required this.locksAt,
    required this.isLocked,
    required this.myPicks,
  });

  factory UpcomingPrediction.fromJson(Map<String, dynamic> j) {
    final s = j['session'] as Map<String, dynamic>;
    final e = j['event'] as Map<String, dynamic>;
    final mp = j['myPicks'];
    return UpcomingPrediction(
      sessionId: s['id'] as int,
      sessionType: SessionType.values.byName(s['type'] as String),
      eventId: e['id'] as int,
      eventRound: e['round'] as int,
      eventName: e['name'] as String,
      eventCountry: e['country'] as String,
      picksRequired: j['picksRequired'] as int,
      locksAt: DateTime.parse(j['locksAt'] as String).toLocal(),
      isLocked: j['isLocked'] as bool,
      myPicks: mp == null
          ? null
          : (mp as List).cast<Map<String, dynamic>>().map(Pick.fromJson).toList(),
    );
  }
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/api/models/prediction_models_test.dart`
Expected: 5 PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/api/models/pick.dart lib/api/models/prediction_view.dart lib/api/models/upcoming_prediction.dart test/api/models/prediction_models_test.dart
git commit -m "feat(predictions): Pick + PredictionView + UpcomingPrediction DTOs"
```

---

### Task B2: Score DTO models + tests

**Files:**
- Create: `lib/api/models/score_breakdown.dart`
- Create: `lib/api/models/my_score.dart`
- Create: `test/api/models/score_models_test.dart`

- [ ] **Step 1: Write failing test**

Create `test/api/models/score_models_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/models/my_score.dart';
import 'package:predictiongame/api/models/score_breakdown.dart';
import 'package:predictiongame/api/models/session.dart';

void main() {
  test('ScoreBreakdown round-trip', () {
    final b = ScoreBreakdown.fromJson({
      'perPosition': [
        {'position': 1, 'exact': true,  'wrongPos': false, 'points': 3},
        {'position': 2, 'exact': false, 'wrongPos': true,  'points': 1},
      ],
      'teamBonus': {'applied': true, 'points': 2},
      'rule': 'race-v1',
    });
    expect(b.perPosition.length, 2);
    expect(b.perPosition[0].exact, isTrue);
    expect(b.teamBonus.applied, isTrue);
    expect(b.teamBonus.points, 2);
    expect(b.rule, 'race-v1');
  });

  test('MyScore round-trip', () {
    final s = MyScore.fromJson({
      'sessionId': 1,
      'sessionType': 'race',
      'eventRound': 1,
      'eventName': 'Australian Grand Prix',
      'sessionScheduledStart': '2026-03-08T04:00:00.000Z',
      'pointsTotal': 15,
      'breakdown': {
        'perPosition': [{'position': 1, 'exact': true, 'wrongPos': false, 'points': 3}],
        'teamBonus': {'applied': false, 'points': 0},
        'rule': 'race-v1',
      },
      'computedAt': '2026-05-26T20:00:00.000Z',
    });
    expect(s.sessionId, 1);
    expect(s.sessionType, SessionType.race);
    expect(s.pointsTotal, 15);
    expect(s.eventName, 'Australian Grand Prix');
    expect(s.breakdown.rule, 'race-v1');
  });
}
```

- [ ] **Step 2: Run, confirm fail**

Run: `flutter test test/api/models/score_models_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement**

Create `lib/api/models/score_breakdown.dart`:

```dart
class ScoreBreakdownPerPosition {
  final int position;
  final bool exact;
  final bool wrongPos;
  final int points;

  const ScoreBreakdownPerPosition({
    required this.position,
    required this.exact,
    required this.wrongPos,
    required this.points,
  });

  factory ScoreBreakdownPerPosition.fromJson(Map<String, dynamic> j) => ScoreBreakdownPerPosition(
        position: j['position'] as int,
        exact: j['exact'] as bool,
        wrongPos: j['wrongPos'] as bool,
        points: j['points'] as int,
      );
}

class ScoreTeamBonus {
  final bool applied;
  final int points;
  const ScoreTeamBonus({required this.applied, required this.points});

  factory ScoreTeamBonus.fromJson(Map<String, dynamic> j) => ScoreTeamBonus(
        applied: j['applied'] as bool,
        points: j['points'] as int,
      );
}

class ScoreBreakdown {
  final List<ScoreBreakdownPerPosition> perPosition;
  final ScoreTeamBonus teamBonus;
  final String rule;

  const ScoreBreakdown({
    required this.perPosition,
    required this.teamBonus,
    required this.rule,
  });

  factory ScoreBreakdown.fromJson(Map<String, dynamic> j) => ScoreBreakdown(
        perPosition: (j['perPosition'] as List)
            .cast<Map<String, dynamic>>()
            .map(ScoreBreakdownPerPosition.fromJson)
            .toList(),
        teamBonus: ScoreTeamBonus.fromJson(j['teamBonus'] as Map<String, dynamic>),
        rule: j['rule'] as String,
      );
}
```

Create `lib/api/models/my_score.dart`:

```dart
import 'score_breakdown.dart';
import 'session.dart';

class MyScore {
  final int sessionId;
  final SessionType sessionType;
  final int eventRound;
  final String eventName;
  final DateTime sessionScheduledStart;
  final int pointsTotal;
  final ScoreBreakdown breakdown;
  final DateTime computedAt;

  const MyScore({
    required this.sessionId,
    required this.sessionType,
    required this.eventRound,
    required this.eventName,
    required this.sessionScheduledStart,
    required this.pointsTotal,
    required this.breakdown,
    required this.computedAt,
  });

  factory MyScore.fromJson(Map<String, dynamic> j) => MyScore(
        sessionId: j['sessionId'] as int,
        sessionType: SessionType.values.byName(j['sessionType'] as String),
        eventRound: j['eventRound'] as int,
        eventName: j['eventName'] as String,
        sessionScheduledStart: DateTime.parse(j['sessionScheduledStart'] as String).toLocal(),
        pointsTotal: j['pointsTotal'] as int,
        breakdown: ScoreBreakdown.fromJson(j['breakdown'] as Map<String, dynamic>),
        computedAt: DateTime.parse(j['computedAt'] as String).toLocal(),
      );
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/api/models/score_models_test.dart`
Expected: 2 PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/api/models/score_breakdown.dart lib/api/models/my_score.dart test/api/models/score_models_test.dart
git commit -m "feat(scores): ScoreBreakdown + MyScore DTOs"
```

---

### Task B3: ApiClient + HttpApiClient — predictions + scores methods

**Files:**
- Modify: `lib/api/api_client.dart`
- Modify: `lib/api/http_api_client.dart`
- Create: `test/api/http_api_client_predictions_test.dart`
- Create: `test/api/http_api_client_scores_test.dart`

- [ ] **Step 1: Extend `ApiClient` interface**

In `lib/api/api_client.dart`, add imports and 5 new methods inside `abstract class ApiClient`:

```dart
import 'models/my_score.dart';
import 'models/pick.dart';
import 'models/prediction_view.dart';
import 'models/upcoming_prediction.dart';
```

And inside the class:

```dart
  // predictions
  Future<PredictionView?>          getMyPrediction(int sessionId);
  Future<PredictionView>           putMyPrediction(int sessionId, List<Pick> picks);
  Future<void>                     deleteMyPrediction(int sessionId);
  Future<List<UpcomingPrediction>> upcomingPredictions();

  // scores
  Future<List<MyScore>>            myScores({int? season});
```

- [ ] **Step 2: Implement in `lib/api/http_api_client.dart`**

Add imports:
```dart
import 'models/my_score.dart';
import 'models/pick.dart';
import 'models/prediction_view.dart';
import 'models/upcoming_prediction.dart';
```

Add methods inside the class:

```dart
  @override
  Future<PredictionView?> getMyPrediction(int sessionId) async {
    try {
      final j = await _request('GET', '/api/sessions/$sessionId/my-prediction') as Map<String, dynamic>;
      return PredictionView.fromJson(j['prediction'] as Map<String, dynamic>);
    } on NotFoundException {
      return null;
    }
  }

  @override
  Future<PredictionView> putMyPrediction(int sessionId, List<Pick> picks) async {
    final j = await _request('PUT', '/api/sessions/$sessionId/my-prediction', body: {
      'picks': picks.map((p) => p.toJson()).toList(),
    }) as Map<String, dynamic>;
    return PredictionView.fromJson(j['prediction'] as Map<String, dynamic>);
  }

  @override
  Future<void> deleteMyPrediction(int sessionId) async {
    await _request('DELETE', '/api/sessions/$sessionId/my-prediction');
  }

  @override
  Future<List<UpcomingPrediction>> upcomingPredictions() async {
    final j = await _request('GET', '/api/predictions/upcoming') as Map<String, dynamic>;
    return (j['upcoming'] as List).cast<Map<String, dynamic>>().map(UpcomingPrediction.fromJson).toList();
  }

  @override
  Future<List<MyScore>> myScores({int? season}) async {
    final q = season == null ? '' : '?season=$season';
    final j = await _request('GET', '/api/users/me/scores$q') as Map<String, dynamic>;
    return (j['scores'] as List).cast<Map<String, dynamic>>().map(MyScore.fromJson).toList();
  }
```

- [ ] **Step 3: Write prediction client tests**

Create `test/api/http_api_client_predictions_test.dart`:

```dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:predictiongame/api/api_client.dart';
import 'package:predictiongame/api/http_api_client.dart';
import 'package:predictiongame/api/models/pick.dart';

class _MockHttp extends Mock implements http.Client {}

void main() {
  late _MockHttp http_;
  late HttpApiClient client;
  setUpAll(() { registerFallbackValue(Uri()); });
  setUp(() {
    http_ = _MockHttp();
    client = HttpApiClient(
      baseUrl: 'https://api.example.com',
      client: http_,
      tokenProvider: () => 'tok',
      onUnauthorized: () {},
    );
  });

  test('getMyPrediction 200 returns PredictionView', () async {
    when(() => http_.get(any(), headers: any(named: 'headers'))).thenAnswer(
      (_) async => http.Response(jsonEncode({
        'prediction': {
          'sessionId': 42,
          'picks': [{'position': 1, 'driverCode': 'VER'}],
          'isLocked': false,
        }
      }), 200),
    );
    final v = await client.getMyPrediction(42);
    expect(v!.sessionId, 42);
    expect(v.picks.first.driverCode, 'VER');
  });

  test('getMyPrediction 404 returns null', () async {
    when(() => http_.get(any(), headers: any(named: 'headers'))).thenAnswer(
      (_) async => http.Response('{"error":{"code":"NOT_FOUND"}}', 404),
    );
    final v = await client.getMyPrediction(42);
    expect(v, isNull);
  });

  test('putMyPrediction 200 returns PredictionView', () async {
    when(() => http_.put(any(), headers: any(named: 'headers'), body: any(named: 'body'))).thenAnswer(
      (_) async => http.Response(jsonEncode({
        'prediction': {
          'sessionId': 42,
          'picks': [{'position': 1, 'driverCode': 'VER'}],
          'isLocked': false,
        }
      }), 200),
    );
    final v = await client.putMyPrediction(42, [const Pick(position: 1, driverCode: 'VER')]);
    expect(v.sessionId, 42);
  });

  test('putMyPrediction 409 → ConflictException', () async {
    when(() => http_.put(any(), headers: any(named: 'headers'), body: any(named: 'body'))).thenAnswer(
      (_) async => http.Response(jsonEncode({'error': {'message': 'Predictions for this session are locked'}}), 409),
    );
    expect(client.putMyPrediction(42, [const Pick(position: 1, driverCode: 'VER')]),
        throwsA(isA<ConflictException>()));
  });

  test('upcomingPredictions 200 returns list', () async {
    when(() => http_.get(any(), headers: any(named: 'headers'))).thenAnswer(
      (_) async => http.Response(jsonEncode({
        'upcoming': [
          {
            'session': {'id': 26, 'type': 'qualifying'},
            'event': {'id': 6, 'round': 6, 'name': 'Monaco Grand Prix', 'country': 'Monaco'},
            'picksRequired': 2,
            'locksAt': '2026-06-06T14:00:00.000Z',
            'isLocked': false,
            'myPicks': null,
          }
        ]
      }), 200),
    );
    final list = await client.upcomingPredictions();
    expect(list, hasLength(1));
    expect(list.first.eventName, 'Monaco Grand Prix');
  });
}
```

- [ ] **Step 4: Write score client tests**

Create `test/api/http_api_client_scores_test.dart`:

```dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:predictiongame/api/http_api_client.dart';

class _MockHttp extends Mock implements http.Client {}

void main() {
  late _MockHttp http_;
  late HttpApiClient client;
  setUpAll(() { registerFallbackValue(Uri()); });
  setUp(() {
    http_ = _MockHttp();
    client = HttpApiClient(
      baseUrl: 'https://api.example.com',
      client: http_,
      tokenProvider: () => 'tok',
      onUnauthorized: () {},
    );
  });

  test('myScores 200 returns list', () async {
    when(() => http_.get(any(), headers: any(named: 'headers'))).thenAnswer(
      (_) async => http.Response(jsonEncode({
        'season': 2026,
        'scores': [
          {
            'sessionId': 1, 'sessionType': 'race', 'eventRound': 1,
            'eventName': 'Australian Grand Prix',
            'sessionScheduledStart': '2026-03-08T04:00:00.000Z',
            'pointsTotal': 15,
            'breakdown': {
              'perPosition': [{'position': 1, 'exact': true, 'wrongPos': false, 'points': 3}],
              'teamBonus': {'applied': false, 'points': 0},
              'rule': 'race-v1',
            },
            'computedAt': '2026-05-26T20:00:00.000Z',
          }
        ]
      }), 200),
    );
    final list = await client.myScores(season: 2026);
    expect(list, hasLength(1));
    expect(list.first.pointsTotal, 15);
    expect(list.first.eventName, 'Australian Grand Prix');
  });

  test('myScores attaches season query param', () async {
    when(() => http_.get(any(), headers: any(named: 'headers'))).thenAnswer(
      (_) async => http.Response(jsonEncode({'scores': [], 'season': 2025}), 200),
    );
    await client.myScores(season: 2025);
    final captured = verify(() => http_.get(captureAny(), headers: any(named: 'headers'))).captured;
    expect((captured.last as Uri).toString(), 'https://api.example.com/api/users/me/scores?season=2025');
  });
}
```

- [ ] **Step 5: Run all four tests**

Run: `flutter test test/api/http_api_client_predictions_test.dart test/api/http_api_client_scores_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/api/api_client.dart lib/api/http_api_client.dart test/api/http_api_client_predictions_test.dart test/api/http_api_client_scores_test.dart
git commit -m "feat(predictions): ApiClient + HttpApiClient methods for predictions and scores"
```

---

### Task B4: PredictionsController + tests

**Files:**
- Create: `lib/state/predictions_controller.dart`
- Create: `test/state/predictions_controller_test.dart`

- [ ] **Step 1: Write failing test**

Create `test/state/predictions_controller_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/api_client.dart';
import 'package:predictiongame/api/models/my_score.dart';
import 'package:predictiongame/api/models/pick.dart';
import 'package:predictiongame/api/models/prediction_view.dart';
import 'package:predictiongame/api/models/score_breakdown.dart';
import 'package:predictiongame/api/models/session.dart';
import 'package:predictiongame/api/models/upcoming_prediction.dart';
import 'package:predictiongame/state/predictions_controller.dart';

class _FakeApi implements ApiClient {
  int getCalls = 0;
  int putCalls = 0;
  int upcomingCalls = 0;
  int scoresCalls = 0;
  PredictionView? predReply;
  List<UpcomingPrediction> upcomingReply = const [];
  List<MyScore> scoresReply = const [];

  @override Future<PredictionView?> getMyPrediction(int sessionId) async { getCalls += 1; return predReply; }
  @override Future<PredictionView>  putMyPrediction(int sessionId, List<Pick> picks) async {
    putCalls += 1;
    return predReply = PredictionView(sessionId: sessionId, picks: picks, updatedAt: DateTime.utc(2026,5,1), isLocked: false);
  }
  @override Future<List<UpcomingPrediction>> upcomingPredictions() async { upcomingCalls += 1; return upcomingReply; }
  @override Future<List<MyScore>> myScores({int? season}) async { scoresCalls += 1; return scoresReply; }
  @override noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

MyScore _ms(int sessionId, int pts) => MyScore(
      sessionId: sessionId,
      sessionType: SessionType.race,
      eventRound: 1,
      eventName: 'Australian Grand Prix',
      sessionScheduledStart: DateTime.utc(2026, 3, 8),
      pointsTotal: pts,
      breakdown: const ScoreBreakdown(
        perPosition: [],
        teamBonus: ScoreTeamBonus(applied: false, points: 0),
        rule: 'race-v1',
      ),
      computedAt: DateTime.utc(2026, 5, 26),
    );

void main() {
  test('fetchPrediction caches the result; second call does not hit API', () async {
    final api = _FakeApi()..predReply = const PredictionView(sessionId: 1, picks: [], updatedAt: null, isLocked: false);
    final c = PredictionsController(api: api);
    await c.fetchPrediction(1);
    await c.fetchPrediction(1);
    expect(api.getCalls, 1);
    expect(c.prediction(1)!.sessionId, 1);
  });

  test('fetchPrediction null cached too (no re-fetch)', () async {
    final api = _FakeApi()..predReply = null;
    final c = PredictionsController(api: api);
    await c.fetchPrediction(7);
    await c.fetchPrediction(7);
    expect(api.getCalls, 1);
    expect(c.prediction(7), isNull);
    expect(c.hasFetched(7), isTrue);
  });

  test('savePrediction updates cache and notifies', () async {
    final api = _FakeApi();
    final c = PredictionsController(api: api);
    var notifies = 0;
    c.addListener(() => notifies += 1);
    await c.savePrediction(1, [const Pick(position: 1, driverCode: 'VER')]);
    expect(c.prediction(1)!.picks.first.driverCode, 'VER');
    expect(notifies, greaterThanOrEqualTo(1));
  });

  test('refreshUpcoming stores list and notifies', () async {
    final api = _FakeApi()..upcomingReply = [
      UpcomingPrediction(
        sessionId: 26, sessionType: SessionType.qualifying, eventId: 6, eventRound: 6,
        eventName: 'Monaco', eventCountry: 'MC', picksRequired: 2,
        locksAt: DateTime.utc(2026, 6, 6), isLocked: false, myPicks: null,
      ),
    ];
    final c = PredictionsController(api: api);
    await c.refreshUpcoming();
    expect(c.upcoming, hasLength(1));
  });

  test('refreshScores indexes by sessionId', () async {
    final api = _FakeApi()..scoresReply = [_ms(1, 15), _ms(2, 8)];
    final c = PredictionsController(api: api);
    await c.refreshScores();
    expect(c.score(1)!.pointsTotal, 15);
    expect(c.score(2)!.pointsTotal, 8);
  });

  test('clear empties everything', () async {
    final api = _FakeApi()
      ..predReply = const PredictionView(sessionId: 1, picks: [], updatedAt: null, isLocked: false)
      ..scoresReply = [_ms(1, 15)];
    final c = PredictionsController(api: api);
    await c.fetchPrediction(1);
    await c.refreshScores();
    c.clear();
    expect(c.prediction(1), isNull);
    expect(c.score(1), isNull);
    expect(c.upcoming, isEmpty);
    expect(c.hasFetched(1), isFalse);
  });
}
```

- [ ] **Step 2: Run, confirm fail**

Run: `flutter test test/state/predictions_controller_test.dart`
Expected: FAIL — controller does not exist.

- [ ] **Step 3: Implement**

Create `lib/state/predictions_controller.dart`:

```dart
import 'package:flutter/foundation.dart';
import '../api/api_client.dart';
import '../api/models/my_score.dart';
import '../api/models/pick.dart';
import '../api/models/prediction_view.dart';
import '../api/models/upcoming_prediction.dart';

class PredictionsController extends ChangeNotifier {
  PredictionsController({required this.api});
  final ApiClient api;

  final Map<int, PredictionView?> _predictions = {};
  final Set<int> _fetched = {};
  final Map<int, MyScore> _scores = {};
  List<UpcomingPrediction> _upcoming = const [];

  PredictionView?           prediction(int sessionId) => _predictions[sessionId];
  bool                      hasFetched(int sessionId) => _fetched.contains(sessionId);
  MyScore?                  score(int sessionId)      => _scores[sessionId];
  List<UpcomingPrediction>  get upcoming              => _upcoming;

  Future<PredictionView?> fetchPrediction(int sessionId) async {
    if (_fetched.contains(sessionId)) return _predictions[sessionId];
    final v = await api.getMyPrediction(sessionId);
    _predictions[sessionId] = v;
    _fetched.add(sessionId);
    notifyListeners();
    return v;
  }

  Future<PredictionView> savePrediction(int sessionId, List<Pick> picks) async {
    final v = await api.putMyPrediction(sessionId, picks);
    _predictions[sessionId] = v;
    _fetched.add(sessionId);
    notifyListeners();
    return v;
  }

  Future<void> refreshUpcoming() async {
    _upcoming = await api.upcomingPredictions();
    notifyListeners();
  }

  Future<void> refreshScores({int? season}) async {
    final list = await api.myScores(season: season);
    _scores
      ..clear()
      ..addEntries(list.map((s) => MapEntry(s.sessionId, s)));
    notifyListeners();
  }

  void clear() {
    _predictions.clear();
    _fetched.clear();
    _scores.clear();
    _upcoming = const [];
    notifyListeners();
  }
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/state/predictions_controller_test.dart`
Expected: 6 PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/state/predictions_controller.dart test/state/predictions_controller_test.dart
git commit -m "feat(predictions): PredictionsController (in-memory cache + lazy fetch)"
```

---

### Task B5: AppState/app.dart/main.dart — swap PredictionsStore for PredictionsController, wire clear-on-auth-change

**Files:**
- Modify: `lib/state/app_state.dart`
- Modify: `lib/app.dart`
- Modify: `lib/main.dart`
- Modify: `lib/state/auth_controller.dart` (call predictionsController.clear on invalidate/logout)
- Delete: `lib/state/predictions_store.dart`
- Delete: `test/state/predictions_store_test.dart`

- [ ] **Step 1: Replace `lib/state/app_state.dart`**

```dart
import 'package:flutter/widgets.dart';
import '../api/api_client.dart';
import 'auth_controller.dart';
import 'league_controller.dart';
import 'predictions_controller.dart';
import 'preseason_store.dart';
import 'theme_controller.dart';

class AppState extends StatefulWidget {
  final ApiClient api;
  final AuthController auth;
  final LeagueController league;
  final ThemeController theme;
  final PredictionsController predictions;
  final PreseasonStore preseason;
  final Widget child;

  const AppState({
    super.key,
    required this.api,
    required this.auth,
    required this.league,
    required this.theme,
    required this.predictions,
    required this.preseason,
    required this.child,
  });

  @override
  State<AppState> createState() => _AppStateState();

  // ignore: library_private_types_in_public_api
  static _AppStateScope of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<_AppStateScope>();
    assert(scope != null, 'AppState not found in widget tree');
    return scope!;
  }
}

class _AppStateState extends State<AppState> {
  @override
  Widget build(BuildContext context) => _AppStateScope(
        api: widget.api,
        auth: widget.auth,
        league: widget.league,
        theme: widget.theme,
        predictions: widget.predictions,
        preseason: widget.preseason,
        child: widget.child,
      );
}

class _AppStateScope extends InheritedWidget {
  final ApiClient api;
  final AuthController auth;
  final LeagueController league;
  final ThemeController theme;
  final PredictionsController predictions;
  final PreseasonStore preseason;

  const _AppStateScope({
    required this.api,
    required this.auth,
    required this.league,
    required this.theme,
    required this.predictions,
    required this.preseason,
    required super.child,
  });

  @override
  bool updateShouldNotify(_AppStateScope oldWidget) => false;
}
```

- [ ] **Step 2: Update `lib/app.dart`**

Replace `import '../state/predictions_store.dart';` with `import 'state/predictions_controller.dart';` (already in lib/) and change the field type from `PredictionsStore` to `PredictionsController`.

Full replacement:

```dart
import 'package:flutter/material.dart';
import 'api/api_client.dart';
import 'nav/router.dart';
import 'state/app_state.dart';
import 'state/auth_controller.dart';
import 'state/league_controller.dart';
import 'state/predictions_controller.dart';
import 'state/preseason_store.dart';
import 'state/theme_controller.dart';
import 'theme/app_theme.dart';

class F1PgApp extends StatefulWidget {
  final ApiClient api;
  final AuthController auth;
  final LeagueController league;
  final ThemeController theme;
  final PredictionsController predictions;
  final PreseasonStore preseason;

  const F1PgApp({
    super.key,
    required this.api,
    required this.auth,
    required this.league,
    required this.theme,
    required this.predictions,
    required this.preseason,
  });

  @override
  State<F1PgApp> createState() => _F1PgAppState();
}

class _F1PgAppState extends State<F1PgApp> {
  late final router = buildRouter(widget.auth);

  @override
  Widget build(BuildContext context) {
    return AppState(
      api: widget.api,
      auth: widget.auth,
      league: widget.league,
      theme: widget.theme,
      predictions: widget.predictions,
      preseason: widget.preseason,
      child: ListenableBuilder(
        listenable: widget.theme,
        builder: (_, __) => MaterialApp.router(
          title: 'F1PG',
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: widget.theme.mode,
          routerConfig: router,
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Update `lib/main.dart`**

In the `_AfterBootState._loadLate()` method, replace:

```dart
    final preds = await PredictionsStore.load();
```

with:

```dart
    final preds = PredictionsController(api: widget.api);
    widget.auth.attachPredictionsController(preds);
```

Replace the field type in `_LateState` from `PredictionsStore` to `PredictionsController`, and remove the import for `predictions_store.dart`. Add import for `predictions_controller.dart`.

- [ ] **Step 4: Wire `attachPredictionsController` in AuthController**

Add to `lib/state/auth_controller.dart`:

```dart
import 'predictions_controller.dart';
```

Add field and method:

```dart
  PredictionsController? _predictions;
  void attachPredictionsController(PredictionsController c) { _predictions = c; }
```

In `_wipe()`, before notifyListeners, call:

```dart
    _predictions?.clear();
```

In `logout()` and `invalidate()` flow: `_wipe()` is already called, so the clear propagates.

- [ ] **Step 5: Delete legacy store and its test**

Run:
```bash
git rm lib/state/predictions_store.dart test/state/predictions_store_test.dart
```

If `lib/domain/prediction.dart` is no longer imported anywhere, also `git rm lib/domain/prediction.dart`. Check with: `grep -rn "domain/prediction" lib/ test/`. If results exist, leave it.

- [ ] **Step 6: Update any code that still references PredictionsStore**

Run: `grep -rn "PredictionsStore" lib/ test/`
Expected: zero matches. If matches exist, replace with `PredictionsController` and update calls (`predictions.picksFor(...)` → `predictions.prediction(sessionId)?.picks ?? []`; `predictions.save(...)` → `await predictions.savePrediction(sessionId, picks)`; `predictions.isLocked(...)` → `predictions.prediction(sessionId)?.isLocked ?? false`).

The biggest consumer is `lib/screens/predict_screen.dart` — Task B6 rewrites it entirely. For this task, if there are call-site compile errors in predict_screen.dart, leave them for B6 — but type-check should pass for everything else.

Actually: `flutter analyze` will fail on predict_screen.dart until B6. To keep this task clean, **temporarily comment out** the body of `predict_screen.dart` build method and return a Placeholder until B6:

```dart
@override
Widget build(BuildContext context) => const Scaffold(body: Center(child: Text('Predict (rewiring)')));
```

(Remove the old `_load`, `_lock`, `_toggleDriver`, `_PredictData`, etc. — they're replaced in B6.)

- [ ] **Step 7: Run all tests**

Run: `flutter test`
Expected: All tests pass except possibly the predict_screen test (which doesn't exist yet — B6 will write it).

- [ ] **Step 8: Analyze**

Run: `flutter analyze`
Expected: no errors.

- [ ] **Step 9: Commit**

```bash
git add lib/state/app_state.dart lib/app.dart lib/main.dart lib/state/auth_controller.dart lib/screens/predict_screen.dart
git commit -m "feat(predictions): replace PredictionsStore with PredictionsController throughout"
```

---

### Task B6: PredictScreen rewrite + widget tests

**Files:**
- Modify: `lib/screens/predict_screen.dart`
- Create: `test/screens/predict_screen_test.dart`

- [ ] **Step 1: Write failing widget test**

Create `test/screens/predict_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/api_client.dart';
import 'package:predictiongame/api/models/constructor.dart';
import 'package:predictiongame/api/models/driver.dart';
import 'package:predictiongame/api/models/event.dart';
import 'package:predictiongame/api/models/me_result.dart';
import 'package:predictiongame/api/models/pick.dart';
import 'package:predictiongame/api/models/prediction_view.dart';
import 'package:predictiongame/api/models/season.dart';
import 'package:predictiongame/api/models/session.dart';
import 'package:predictiongame/api/models/session_result.dart';
import 'package:predictiongame/api/models/standing.dart';
import 'package:predictiongame/api/models/upcoming_prediction.dart';
import 'package:predictiongame/screens/predict_screen.dart';
import 'package:predictiongame/state/app_state.dart';
import 'package:predictiongame/state/auth_controller.dart';
import 'package:predictiongame/state/league_controller.dart';
import 'package:predictiongame/state/predictions_controller.dart';
import 'package:predictiongame/state/preseason_store.dart';
import 'package:predictiongame/state/theme_controller.dart';
import 'package:predictiongame/state/token_storage.dart';

class _FakeApi implements ApiClient {
  List<UpcomingPrediction> upcoming = const [];
  PredictionView? prediction;
  Object? putError;
  PredictionView? putReply;
  List<SessionResult> results = const [];
  @override Future<List<UpcomingPrediction>> upcomingPredictions() async => upcoming;
  @override Future<PredictionView?> getMyPrediction(int s) async => prediction;
  @override Future<PredictionView>  putMyPrediction(int s, List<Pick> picks) async {
    if (putError != null) throw putError!;
    return putReply ?? PredictionView(sessionId: s, picks: picks, updatedAt: DateTime.utc(2026,5,1), isLocked: false);
  }
  @override Future<List<SessionResult>> sessionResults(int id) async => results;
  @override noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Widget _wrap({required _FakeApi api, required PredictionsController controller, required AuthController auth}) {
  return AppState(
    api: api,
    auth: auth,
    league: LeagueController(league: theBoxLeague),
    theme: ThemeController.fakeForTests(),
    predictions: controller,
    preseason: PreseasonStore.fakeForTests(),
    child: const MaterialApp(home: PredictScreen()),
  );
}

void main() {
  testWidgets('shows "Nothing to predict" when upcoming is empty', (tester) async {
    final api = _FakeApi();
    final auth = AuthController(storage: InMemoryTokenStorage())..api = api;
    final c = PredictionsController(api: api);
    await tester.pumpWidget(_wrap(api: api, controller: c, auth: auth));
    await tester.pumpAndSettle();
    expect(find.textContaining('Nothing to predict'), findsOneWidget);
  });

  testWidgets('renders next session and pre-filled picks', (tester) async {
    final api = _FakeApi()
      ..upcoming = [
        UpcomingPrediction(
          sessionId: 26, sessionType: SessionType.qualifying, eventId: 6, eventRound: 6,
          eventName: 'Monaco Grand Prix', eventCountry: 'Monaco', picksRequired: 2,
          locksAt: DateTime.utc(2026, 6, 6), isLocked: false, myPicks: null,
        ),
      ]
      ..prediction = const PredictionView(sessionId: 26, picks: [Pick(position: 1, driverCode: 'VER'), Pick(position: 2, driverCode: 'NOR')], updatedAt: null, isLocked: false);
    final auth = AuthController(storage: InMemoryTokenStorage())..api = api;
    final c = PredictionsController(api: api);
    await tester.pumpWidget(_wrap(api: api, controller: c, auth: auth));
    await tester.pumpAndSettle();
    expect(find.text('Monaco Grand Prix'), findsOneWidget);
  });

  testWidgets('save → ConflictException shows SnackBar', (tester) async {
    final api = _FakeApi()
      ..upcoming = [
        UpcomingPrediction(
          sessionId: 26, sessionType: SessionType.qualifying, eventId: 6, eventRound: 6,
          eventName: 'Monaco', eventCountry: 'MC', picksRequired: 2,
          locksAt: DateTime.utc(2026, 6, 6), isLocked: false, myPicks: null,
        ),
      ]
      ..prediction = const PredictionView(sessionId: 26, picks: [Pick(position: 1, driverCode: 'VER'), Pick(position: 2, driverCode: 'NOR')], updatedAt: null, isLocked: false)
      ..putError = const ConflictException('Predictions are locked');
    final auth = AuthController(storage: InMemoryTokenStorage())..api = api;
    final c = PredictionsController(api: api);
    await tester.pumpWidget(_wrap(api: api, controller: c, auth: auth));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('predict.save')));
    await tester.pumpAndSettle();
    expect(find.text('Predictions are locked'), findsOneWidget);
  });
}
```

Note: the test helpers `ThemeController.fakeForTests()` and `PreseasonStore.fakeForTests()` may not exist. If they don't:
- For `ThemeController`: open `lib/state/theme_controller.dart`. If there's no zero-arg factory or test constructor, **add** a static `factory ThemeController.fakeForTests() => ThemeController(mode: ThemeMode.system);` (adjust to match the actual class signature — read the existing file first).
- For `PreseasonStore`: same approach.

If you can't easily add a test factory without expanding scope, replace the test's controller construction with the real `load()` (which uses `SharedPreferences.setMockInitialValues({})` via a `TestWidgetsFlutterBinding.ensureInitialized()` setup at the top of the test).

- [ ] **Step 2: Run, confirm fail**

Run: `flutter test test/screens/predict_screen_test.dart`
Expected: FAIL — predict_screen is the Placeholder from B5.

- [ ] **Step 3: Rewrite `lib/screens/predict_screen.dart`**

Replace the entire file with:

```dart
import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../api/models/pick.dart';
import '../api/models/prediction_view.dart';
import '../api/models/session.dart';
import '../api/models/session_result.dart';
import '../api/models/upcoming_prediction.dart';
import '../state/app_state.dart';
import '../state/predictions_controller.dart';

class PredictScreen extends StatefulWidget {
  const PredictScreen({super.key});
  @override
  State<PredictScreen> createState() => _PredictScreenState();
}

class _PredictScreenState extends State<PredictScreen> {
  Future<_LoadResult>? _data;
  List<String> _picks = [];
  bool _saving = false;

  Future<_LoadResult> _load() async {
    final scope = AppState.of(context);
    await scope.predictions.refreshUpcoming();
    final next = scope.predictions.upcoming.where((u) => !u.isLocked).toList()
      ..sort((a, b) => a.locksAt.compareTo(b.locksAt));
    if (next.isEmpty) return _LoadResult(upcoming: null, drivers: const []);
    final u = next.first;
    final pred = await scope.predictions.fetchPrediction(u.sessionId);
    _picks = pred?.picks.map((p) => p.driverCode).toList() ?? [];
    final lineup = await _safeLineup(scope.api);
    return _LoadResult(upcoming: u, drivers: lineup);
  }

  Future<List<SessionResult>> _safeLineup(ApiClient api) async {
    try {
      // For now: no historical lineup endpoint without an event hint.
      // Empty list = renders just position-numbered slots; user can still pick by code.
      return const [];
    } on NotFoundException {
      return const [];
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _data ??= _load();
  }

  void _toggle(String code, int required) {
    setState(() {
      if (_picks.contains(code)) {
        _picks.remove(code);
      } else if (_picks.length < required) {
        _picks.add(code);
      }
    });
  }

  Future<void> _save(UpcomingPrediction u) async {
    final scope = AppState.of(context);
    setState(() => _saving = true);
    try {
      final picks = [for (var i = 0; i < _picks.length; i++) Pick(position: i + 1, driverCode: _picks[i])];
      await scope.predictions.savePrediction(u.sessionId, picks);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pick saved')));
    } on ConflictException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } on ValidationException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't save")));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<_LoadResult>(
          future: _data,
          builder: (_, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Center(child: Text("Couldn't load: ${snap.error}"));
            }
            final r = snap.data!;
            final u = r.upcoming;
            if (u == null) {
              return const Center(child: Text('Nothing to predict right now.'));
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(u.eventName, style: Theme.of(context).textTheme.headlineSmall),
                Text(u.sessionType.name),
                const SizedBox(height: 8),
                Text('Picks: ${_picks.length}/${u.picksRequired}'),
                const SizedBox(height: 16),
                FilledButton(
                  key: const Key('predict.save'),
                  onPressed: _saving || _picks.length != u.picksRequired ? null : () => _save(u),
                  child: Text(_saving ? 'Saving...' : 'Save picks'),
                ),
                const SizedBox(height: 16),
                // Driver chips — clicking toggles into _picks
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final d in _knownDrivers())
                    FilterChip(
                      label: Text(d),
                      selected: _picks.contains(d),
                      onSelected: (_) => _toggle(d, u.picksRequired),
                    ),
                ]),
              ],
            );
          },
        ),
      ),
    );
  }

  // Minimal driver universe — full list of 2026 3-letter codes. Lets the user pick
  // without depending on a separate lineup fetch. (Driver lineup screen polish is
  // explicitly out of scope for this PR.)
  List<String> _knownDrivers() => const [
        'VER','NOR','RUS','PIA','LEC','HAD','ANT','HAM','GAS','BEA',
        'OCO','LIN','ALB','BOR','COL','LAW','HUL','SAI','BOT','PER','ALO','STR',
      ];
}

class _LoadResult {
  final UpcomingPrediction? upcoming;
  final List<SessionResult> drivers;
  _LoadResult({required this.upcoming, required this.drivers});
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/screens/predict_screen_test.dart`
Expected: 3 PASS. If test factories for `ThemeController`/`PreseasonStore` were missing, they were added in Step 1 prep work.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/predict_screen.dart test/screens/predict_screen_test.dart
git commit -m "feat(predictions): rewrite PredictScreen to use backend via PredictionsController"
```

---

### Task B7: ScoreDetailScreen + widget tests + route

**Files:**
- Create: `lib/screens/score_detail_screen.dart`
- Create: `test/screens/score_detail_screen_test.dart`
- Modify: `lib/nav/router.dart`

- [ ] **Step 1: Write failing widget test**

Create `test/screens/score_detail_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/api_client.dart';
import 'package:predictiongame/api/models/my_score.dart';
import 'package:predictiongame/api/models/pick.dart';
import 'package:predictiongame/api/models/prediction_view.dart';
import 'package:predictiongame/api/models/score_breakdown.dart';
import 'package:predictiongame/api/models/session.dart';
import 'package:predictiongame/api/models/upcoming_prediction.dart';
import 'package:predictiongame/screens/score_detail_screen.dart';
import 'package:predictiongame/state/app_state.dart';
import 'package:predictiongame/state/auth_controller.dart';
import 'package:predictiongame/state/league_controller.dart';
import 'package:predictiongame/state/predictions_controller.dart';
import 'package:predictiongame/state/preseason_store.dart';
import 'package:predictiongame/state/theme_controller.dart';
import 'package:predictiongame/state/token_storage.dart';

class _FakeApi implements ApiClient {
  List<MyScore> scoresReply = const [];
  @override Future<List<MyScore>> myScores({int? season}) async => scoresReply;
  @override Future<PredictionView?> getMyPrediction(int s) async => null;
  @override Future<List<UpcomingPrediction>> upcomingPredictions() async => const [];
  @override noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

MyScore _ms({required int sid, required int pts, required ScoreBreakdown breakdown}) => MyScore(
      sessionId: sid,
      sessionType: SessionType.race,
      eventRound: 1,
      eventName: 'Australian Grand Prix',
      sessionScheduledStart: DateTime.utc(2026, 3, 8),
      pointsTotal: pts,
      breakdown: breakdown,
      computedAt: DateTime.utc(2026, 5, 26),
    );

Widget _wrap({required _FakeApi api, required PredictionsController controller}) {
  return AppState(
    api: api,
    auth: AuthController(storage: InMemoryTokenStorage())..api = api,
    league: LeagueController(league: theBoxLeague),
    theme: ThemeController.fakeForTests(),
    predictions: controller,
    preseason: PreseasonStore.fakeForTests(),
    child: const MaterialApp(home: ScoreDetailScreen()),
  );
}

void main() {
  testWidgets('empty state when no scores', (tester) async {
    final api = _FakeApi();
    final c = PredictionsController(api: api);
    await tester.pumpWidget(_wrap(api: api, controller: c));
    await tester.pumpAndSettle();
    expect(find.textContaining('No scored sessions yet'), findsOneWidget);
  });

  testWidgets('renders MyScore with totals + breakdown when expanded', (tester) async {
    final api = _FakeApi()..scoresReply = [
      _ms(sid: 1, pts: 13, breakdown: const ScoreBreakdown(
        perPosition: [
          ScoreBreakdownPerPosition(position: 1, exact: true, wrongPos: false, points: 3),
          ScoreBreakdownPerPosition(position: 2, exact: false, wrongPos: true, points: 1),
        ],
        teamBonus: ScoreTeamBonus(applied: true, points: 2),
        rule: 'race-v1',
      )),
    ];
    final c = PredictionsController(api: api);
    await tester.pumpWidget(_wrap(api: api, controller: c));
    await tester.pumpAndSettle();
    expect(find.text('Australian Grand Prix race'), findsOneWidget);
    expect(find.text('13 pts'), findsOneWidget);
    await tester.tap(find.text('Australian Grand Prix race'));
    await tester.pumpAndSettle();
    expect(find.textContaining('P1'), findsOneWidget);
    expect(find.textContaining('Team bonus'), findsOneWidget);
    expect(find.textContaining('race-v1'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run, confirm fail**

Run: `flutter test test/screens/score_detail_screen_test.dart`
Expected: FAIL — screen does not exist.

- [ ] **Step 3: Implement**

Create `lib/screens/score_detail_screen.dart`:

```dart
import 'package:flutter/material.dart';
import '../api/models/my_score.dart';
import '../state/app_state.dart';

class ScoreDetailScreen extends StatefulWidget {
  const ScoreDetailScreen({super.key});
  @override
  State<ScoreDetailScreen> createState() => _ScoreDetailScreenState();
}

class _ScoreDetailScreenState extends State<ScoreDetailScreen> {
  bool _loading = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading) _load();
  }

  Future<void> _load() async {
    final scope = AppState.of(context);
    try {
      await scope.predictions.refreshScores();
    } catch (_) {/* surface via empty state if needed */}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppState.of(context);
    final all = [
      for (final sid in scope.predictions.allScoreIds)
        if (scope.predictions.score(sid) != null) scope.predictions.score(sid)!,
    ]..sort((a, b) => b.sessionScheduledStart.compareTo(a.sessionScheduledStart));

    return Scaffold(
      appBar: AppBar(title: const Text('My Scores')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : all.isEmpty
              ? const Center(child: Text('No scored sessions yet. Once the next race finishes, your scores will appear here.'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    itemCount: all.length,
                    itemBuilder: (_, i) {
                      final s = all[i];
                      return ExpansionTile(
                        title: Text('${s.eventName} ${s.sessionType.name}'),
                        subtitle: Text('${s.sessionScheduledStart.year}-${_pad(s.sessionScheduledStart.month)}-${_pad(s.sessionScheduledStart.day)}'),
                        trailing: Text('${s.pointsTotal} pts'),
                        children: [
                          for (final p in s.breakdown.perPosition)
                            ListTile(
                              dense: true,
                              title: Text('P${p.position}  ${p.exact ? 'exact' : p.wrongPos ? 'wrongPos' : 'miss'}'),
                              trailing: Text('+${p.points}'),
                            ),
                          if (s.breakdown.teamBonus.applied)
                            ListTile(
                              dense: true,
                              title: const Text('Team bonus'),
                              trailing: Text('+${s.breakdown.teamBonus.points}'),
                            ),
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text('Rule: ${s.breakdown.rule}', style: Theme.of(context).textTheme.bodySmall),
                          ),
                        ],
                      );
                    },
                  ),
                ),
      bottomNavigationBar: null,
    );
  }

  String _pad(int n) => n < 10 ? '0$n' : '$n';
}
```

The widget references `preds.allScoreIds` — add that getter to `lib/state/predictions_controller.dart`:

```dart
  Iterable<int> get allScoreIds => _scores.keys;
```

- [ ] **Step 4: Add `/scores` route**

In `lib/nav/router.dart`, add `import '../screens/score_detail_screen.dart';` and add inside the routes list (next to `/settings`):

```dart
      GoRoute(path: '/scores', builder: (_, __) => const ScoreDetailScreen()),
```

- [ ] **Step 5: Run all tests**

Run: `flutter test`
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/screens/score_detail_screen.dart test/screens/score_detail_screen_test.dart lib/nav/router.dart lib/state/predictions_controller.dart
git commit -m "feat(scores): ScoreDetailScreen with per-session breakdown + /scores route"
```

---

### Task B8: HomeScreen — use controller.upcoming for hero + link to /scores

**Files:**
- Modify: `lib/screens/home_screen.dart`

- [ ] **Step 1: Read existing HomeScreen and identify the data source**

Run: `cat lib/screens/home_screen.dart | head -120`
Expected: the screen fetches `nextSession()` via the api or scope. Identify the FutureBuilder that yields the next-session.

- [ ] **Step 2: Replace the next-session fetch with `controller.refreshUpcoming` + take `upcoming.firstWhere(!isLocked)`**

The hero widgets (`_hero` and `_noNextHero`) take a `Session` and `Event` today. Switch to taking an `UpcomingPrediction` (which carries event name + locksAt + isLocked + sessionType). Adjust:

```dart
import '../api/models/upcoming_prediction.dart';
...
Future<UpcomingPrediction?> _loadNext() async {
  final scope = AppState.of(context);
  await scope.predictions.refreshUpcoming();
  final list = scope.predictions.upcoming.where((u) => !u.isLocked).toList()
    ..sort((a, b) => a.locksAt.compareTo(b.locksAt));
  return list.isEmpty ? null : list.first;
}
```

Replace existing `_hero(Session, Event, ThemeData)` signature with `_hero(UpcomingPrediction u, ThemeData t)`. Inside, use `u.eventName`, `u.sessionType`, `u.locksAt`, and—new—show a small badge if `u.myPicks != null`: "Pick locked in" else "Tap to predict".

Add a "My Scores" tile somewhere in the home screen (after the hero), as a `ListTile` with `onTap: () => context.go('/scores')`. Add `import 'package:go_router/go_router.dart';` if not already.

The exact diff depends on the current home_screen.dart shape. Keep changes scoped: do not rewrite unrelated sections.

- [ ] **Step 3: Analyze**

Run: `flutter analyze lib/screens/home_screen.dart`
Expected: no errors.

- [ ] **Step 4: Run app tests**

Run: `flutter test`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/home_screen.dart
git commit -m "feat(predictions): HomeScreen hero from upcoming list + My Scores tile"
```

---

### Task B9: End-to-end smoke run

Human-in-the-loop verification of the full flow.

- [ ] **Step 1: Backend is up and DB has data**

```
curl -fsS http://localhost:3000/api/health
docker exec backend-db-1 psql -U f1pg -d f1pg -c "SELECT COUNT(*) FROM \"user\" WHERE email LIKE '%@tippspiel.test';"
```
Expected: health ok, count 11.

If count is 0, run:
```
make bootstrap && make crawl && (cd backend && set -a && source .env && set +a && npm run import:tippspiel)
```

- [ ] **Step 2: Launch app**

```
make app
```
Wait for the iPhone 17 Pro simulator to come up with the app.

- [ ] **Step 3: Log in as Anton**

In the app: email `anton@tippspiel.test` / password `tippspiel-test` → Log in.
Expected: lands on /home, hero shows Monaco-GP-something (next not-yet-locked session).

- [ ] **Step 4: Navigate to /scores**

Tap "My Scores" (or wherever you wired it in B8).
Expected: list of scored sessions. For Anton: Australia Race ~15, China Race ~16, Japan Race ~16, Miami Race ~20 (totals will match the validation table from the import script).

Expand any row → see per-position breakdown + team bonus + rule.

- [ ] **Step 5: Cross-check vs. terminal validation table**

In a terminal:
```
cd backend && set -a && source .env && set +a && npm run import:tippspiel
```
Look at Anton's row in the printed table. The "Σ App" total should equal the sum of `pointsTotal` for Anton's race/quali/sprint sessions in the My Scores screen.

- [ ] **Step 6: Try a new prediction**

Navigate to /predict. The next session (Monaco quali) should be visible. Tap two driver chips → Save picks.
Expected: SnackBar "Pick saved". Navigate away and back → picks persist (because they're in the controller cache backed by the backend).

- [ ] **Step 7: Log out**

Settings → Log out → confirm. Should land on /login.
Log in as a different test user (e.g. `lukas@tippspiel.test` / `tippspiel-test`) → see Lukas's scores instead.

- [ ] **Step 8: No commit — verification only**

---

### Task B10: Final sweep — lint, full tests, commit any cleanup

- [ ] **Step 1: Analyze**

Run: `flutter analyze`
Expected: no issues.

- [ ] **Step 2: Run all tests**

Run: `flutter test`
Expected: all PASS.

- [ ] **Step 3: Backend tests still green**

Run: `make backend-test`
Expected: 288+ PASS.

- [ ] **Step 4: If anything was missed**

Stage and commit cleanup with a clear message:
```bash
git add -p
git commit -m "chore(auth+predictions): final cleanup after wiring"
```

If no cleanup is needed, this task ends without a commit.

---

## Notes

- `make backend-test` truncates the database. If you run it during this plan, you must re-bootstrap+re-crawl+re-import the Tippspiel data before the smoke runs (B9).
- The `xlsx` import script runs from the backend dir and uses `set -a && source .env && set +a` to load env vars; never invoke `npm test` directly from the backend dir (it'll fail with "ADMIN_TOKEN required").
- `flutter_secure_storage` is a platform plugin. Widget tests use `InMemoryTokenStorage` to avoid platform-channel mocking.
- The router tests use the real router (since redirect logic is the SUT), but pump it inside `MaterialApp.router` without the rest of the app shell.
- If `PreseasonStore` lacks `fakeForTests()`, add it (similar to `ThemeController.fakeForTests()`) as a one-line helper rather than touching the production constructor.
