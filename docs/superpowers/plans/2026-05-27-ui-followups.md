# UI Follow-ups Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the redundant "PICK VS RESULT" block, split preseason from in-season points across the API + UI, plot every league member on the trajectory chart, and add a new "PRESEASON" sub-tab on `StandingsScreen` that shows a live projection.

**Architecture:** Backend changes are confined to `backend/src/repo/scores.ts` (split aggregate), one new module `backend/src/preseason/projection.ts` (live truth + per-member aggregation), and one new route in `backend/src/api/routes/preseason.ts`. Flutter changes touch `LeaderboardRow` / `LeagueRow` / `LeagueTab` for the split, `InsightsTab` for the multi-member trajectory, a new `PreseasonTab` for the projection screen, and `StandingsScreen` for the fourth tab pill. The session-results screen loses one block of code.

**Tech Stack:** Backend — TypeScript, Fastify, Drizzle ORM, Vitest (integration tests against real Postgres via Docker). Frontend — Flutter (Dart 3.5.4), `flutter_test` widget tests, `FutureBuilder`-based screens, no state-management library.

**Reference spec:** `docs/superpowers/specs/2026-05-27-ui-followups-design.md`

**Backend tests are always run via `make backend-test`** (which sources `.env` before invoking vitest — running `npm test` directly from `backend/` will fail).

---

### Task 1: Remove "PICK VS RESULT" block

**Files:**
- Modify: `lib/screens/session_results_screen.dart` (delete lines ~328–394 — the `if (payload.picks.isNotEmpty && payload.result.isNotEmpty) { ... 'PICK VS RESULT' ... }` block)
- Test: `test/screens/session_results_no_pick_vs_result_test.dart` (new)

- [ ] **Step 1: Write the failing source-scan test**

Instantiating the full `SessionResultsScreen` in a widget test would require stubbing AppState + ApiClient + AppRouter, which is heavy for a guard against a heading-string regression. A source-scan test is the right fit: it's fast, deterministic, and unambiguously enforces the intent.

Create `test/screens/session_results_no_pick_vs_result_test.dart`:

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('session results screen no longer contains a PICK VS RESULT heading', () {
    final src = File('lib/screens/session_results_screen.dart').readAsStringSync();
    expect(src.contains('PICK VS RESULT'), isFalse,
        reason: 'PICK VS RESULT was intentionally removed; FULL CLASSIFICATION shows the same info inline.');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/screens/session_results_no_pick_vs_result_test.dart`
Expected: FAIL (the source still contains "PICK VS RESULT").

- [ ] **Step 3: Delete the PICK VS RESULT block**

In `lib/screens/session_results_screen.dart`, locate the block starting with the comment-free line:

```dart
        if (payload.picks.isNotEmpty && payload.result.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Spacing.lg, Spacing.lg, Spacing.lg, Spacing.xs),
            child: Text('PICK VS RESULT',
```

and ending with the closing `),` + `],` of that whole conditional (the next sibling is `if (payload.result.isNotEmpty) ...[` for FULL CLASSIFICATION). Delete the entire `if (...) ...[ Padding(...), Padding(...) ]` block — both the heading `Padding` and the `AppCard` `Padding` it brackets together.

After the edit the `Column` children list should go directly from the `ScoreBanner` / empty-state block to `if (payload.result.isNotEmpty) ...[ ... FULL CLASSIFICATION ... ]`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/screens/session_results_no_pick_vs_result_test.dart`
Expected: PASS.

- [ ] **Step 5: Run the full Flutter suite to catch regressions**

Run: `flutter test`
Expected: all green. If `flutter analyze` is in the project's standard loop, also run `flutter analyze` and expect no new warnings.

- [ ] **Step 6: Commit**

```bash
git add lib/screens/session_results_screen.dart test/screens/session_results_no_pick_vs_result_test.dart
git commit -m "ui: drop PICK VS RESULT card — info already inline in FULL CLASSIFICATION"
```

---

### Task 2: Backend — split `leagueLeaderboard` into in-season + preseason columns

**Files:**
- Modify: `backend/src/repo/scores.ts` (rewrite `LeaderboardRow` type + `leagueLeaderboard` body)
- Modify: `backend/test/integration/api_leaderboard_with_preseason.test.ts` (existing assertions stay; add field-level assertions)
- Modify: `backend/test/integration/repo_scores.test.ts` (only if it references `pointsTotal` in ways that conflict — verify in step 2)

- [ ] **Step 1: Write the failing test additions**

Append to `backend/test/integration/api_leaderboard_with_preseason.test.ts` inside the existing `describe(...)` block:

```ts
  it('exposes inSeasonPoints and preseasonPoints separately', async () => {
    const ses = await seedSession()
    const owner = await users.insertUser({ email: 'sp@x.com', passwordHash: 'h', displayName: 'SP' })
    const l = await leagues.createLeagueWithOwner({ name: 'LS', ownerUserId: owner.id, joinCode: 'CMB005' })

    await scores.upsertScore(owner.id, ses.id, 10, bd(10))
    await scores.upsertPreseasonScore(owner.id, 2026, 'surprise', 4, bdp(4))
    await scores.upsertPreseasonScore(owner.id, 2026, 'dnf',      8, bdp(8))

    const lb = await scores.leagueLeaderboard(l.id, 2026)
    const me = lb.find((r) => r.userId === owner.id)!
    expect(me.inSeasonPoints).toBe(10)
    expect(me.preseasonPoints).toBe(12)
    expect(me.pointsTotal).toBe(22)
    expect(me.sessionsScored).toBe(1)
  })

  it('preseason-only user has zero inSeasonPoints', async () => {
    await seedSession()
    const owner = await users.insertUser({ email: 'po@x.com', passwordHash: 'h', displayName: 'PO' })
    const l = await leagues.createLeagueWithOwner({ name: 'LPO', ownerUserId: owner.id, joinCode: 'CMB006' })
    await scores.upsertPreseasonScore(owner.id, 2026, 'wdc_wcc', 8, bdp(8))
    const lb = await scores.leagueLeaderboard(l.id, 2026)
    const me = lb.find((r) => r.userId === owner.id)!
    expect(me.inSeasonPoints).toBe(0)
    expect(me.preseasonPoints).toBe(8)
    expect(me.pointsTotal).toBe(8)
  })
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `make backend-test`
Expected: the two new tests FAIL with TypeScript errors (`Property 'inSeasonPoints' does not exist on type 'LeaderboardRow'`). The existing tests still pass.

- [ ] **Step 3: Update `LeaderboardRow` type + rewrite the query**

In `backend/src/repo/scores.ts`, replace the existing `LeaderboardRow` type (around line 6) and the existing `leagueLeaderboard` function body (around lines 72–98) with:

```ts
export type LeaderboardRow = {
  userId: string
  displayName: string
  inSeasonPoints: number
  preseasonPoints: number
  pointsTotal: number
  sessionsScored: number
}

export async function leagueLeaderboard(leagueId: string, seasonYear: number): Promise<LeaderboardRow[]> {
  const db = getDb()
  const rows = await db.execute(sql`
    SELECT
      lm.user_id::text AS "userId",
      u.display_name   AS "displayName",
      COALESCE(SUM(s.points_total) FILTER (WHERE s.kind = 'session'),   0)::int AS "inSeasonPoints",
      COALESCE(SUM(s.points_total) FILTER (WHERE s.kind = 'preseason'), 0)::int AS "preseasonPoints",
      COALESCE(SUM(s.points_total), 0)::int                                     AS "pointsTotal",
      COUNT(*) FILTER (WHERE s.kind = 'session')::int                           AS "sessionsScored"
    FROM ${leagueMember} lm
    JOIN ${user} u ON u.id = lm.user_id
    LEFT JOIN (
      SELECT s.user_id, s.kind, s.points_total
      FROM ${score} s
      JOIN ${session} ses ON ses.id = s.session_id
      JOIN ${event}   ev  ON ev.id  = ses.event_id
      WHERE s.kind = 'session' AND ev.season_year = ${seasonYear}
      UNION ALL
      SELECT s.user_id, s.kind, s.points_total
      FROM ${score} s
      WHERE s.kind = 'preseason' AND s.season_year = ${seasonYear}
    ) s ON s.user_id = lm.user_id
    WHERE lm.league_id = ${leagueId}
    GROUP BY lm.user_id, u.display_name
    ORDER BY "pointsTotal" DESC, "displayName" ASC
  `)
  return (rows as unknown as { rows: LeaderboardRow[] }).rows
}
```

The `FILTER (WHERE ...)` clauses give per-kind sums in a single pass. `sessionsScored` is counted only over rows where `kind = 'session'`, preserving the old semantic.

- [ ] **Step 4: Run tests to verify they pass**

Run: `make backend-test`
Expected: all leaderboard tests pass (including the two new ones and the four existing combined-total tests).

- [ ] **Step 5: Commit**

```bash
git add backend/src/repo/scores.ts backend/test/integration/api_leaderboard_with_preseason.test.ts
git commit -m "backend: split leagueLeaderboard into inSeasonPoints + preseasonPoints"
```

---

### Task 3: Flutter — `LeaderboardRow` model + `LeagueRow` widget + `LeagueTab` use the split

**Files:**
- Modify: `lib/api/models/leaderboard_row.dart`
- Modify: `lib/components/league_row.dart`
- Modify: `lib/screens/standings/league_tab.dart`
- Modify: `test/components/standings_insights_test.dart` (existing `LeagueRow` test needs updating — it currently asserts on `points: 148`)

- [ ] **Step 1: Update the existing LeagueRow widget test to fail against the new API**

In `test/components/standings_insights_test.dart`, replace the existing `LeagueRow` test (lines ~16–24) with:

```dart
  testWidgets('LeagueRow shows rank, name, and split points', (tester) async {
    await tester.pumpWidget(_frame(const LeagueRow(
      rank: 3, name: 'Anton',
      inSeasonPoints: 100, preseasonPoints: 48, pointsTotal: 148,
      trend: TrendDirection.equal, isMe: true,
    )));
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Anton'), findsOneWidget);
    expect(find.text('148'), findsOneWidget);  // total
    expect(find.text('100'), findsOneWidget);  // in-season
    expect(find.text('48'),  findsOneWidget);  // preseason
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/components/standings_insights_test.dart`
Expected: FAIL (compile error — `points`/missing parameters on `LeagueRow`).

- [ ] **Step 3: Update `LeaderboardRow` model**

Replace the contents of `lib/api/models/leaderboard_row.dart` with:

```dart
class LeaderboardRow {
  final String userId;
  final String displayName;
  final int inSeasonPoints;
  final int preseasonPoints;
  final int pointsTotal;
  final int sessionsScored;

  const LeaderboardRow({
    required this.userId,
    required this.displayName,
    required this.inSeasonPoints,
    required this.preseasonPoints,
    required this.pointsTotal,
    required this.sessionsScored,
  });

  factory LeaderboardRow.fromJson(Map<String, dynamic> j) => LeaderboardRow(
        userId: j['userId'] as String,
        displayName: j['displayName'] as String,
        inSeasonPoints: (j['inSeasonPoints'] as num).toInt(),
        preseasonPoints: (j['preseasonPoints'] as num).toInt(),
        pointsTotal: (j['pointsTotal'] as num).toInt(),
        sessionsScored: (j['sessionsScored'] as num).toInt(),
      );
}
```

- [ ] **Step 4: Update `LeagueRow` widget**

In `lib/components/league_row.dart`, replace the `points` field with three fields and adjust the right-hand column to render three numbers:

```dart
class LeagueRow extends StatelessWidget {
  final int rank;
  final String name;
  final String? subtitle;
  final int inSeasonPoints;
  final int preseasonPoints;
  final int pointsTotal;
  final TrendDirection trend;
  final bool isMe;
  final Color? accentStripe;

  const LeagueRow({
    super.key,
    required this.rank,
    required this.name,
    this.subtitle,
    required this.inSeasonPoints,
    required this.preseasonPoints,
    required this.pointsTotal,
    required this.trend,
    this.isMe = false,
    this.accentStripe,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: Spacing.md),
      color: isMe ? t.rowHighlight : null,
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text('$rank',
                style: AppText.display(18,
                    color: isMe ? BrandColors.accent : t.colorScheme.onSurface)),
          ),
          if (accentStripe != null) ...[
            const SizedBox(width: 10),
            Container(width: 4, height: 22, color: accentStripe),
          ],
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name,
                    style: AppText.body(13,
                        weight: isMe ? FontWeight.w800 : FontWeight.w700)),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!,
                        style: AppText.body(10,
                            color: t.colorScheme.onSurface.withOpacity(0.5))),
                  ),
              ],
            ),
          ),
          if (trend != TrendDirection.equal) ...[
            TrendBadge(direction: trend, label: '1'),
            const SizedBox(width: Spacing.sm),
          ],
          _pointsCell(t, '$inSeasonPoints', 'season'),
          const SizedBox(width: 8),
          _pointsCell(t, '$preseasonPoints', 'pre'),
          const SizedBox(width: 8),
          _pointsCell(t, '$pointsTotal', 'pts', emphasis: true),
        ],
      ),
    );
  }

  Widget _pointsCell(ThemeData t, String value, String label, {bool emphasis = false}) {
    return SizedBox(
      width: 42,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(value,
              style: AppText.display(emphasis ? 18 : 14,
                  color: emphasis
                      ? t.colorScheme.onSurface
                      : t.colorScheme.onSurface.withOpacity(0.65))),
          Text(label,
              style: AppText.label(8,
                  color: t.colorScheme.onSurface.withOpacity(0.6))),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: Update `LeagueTab` to pass the new fields**

In `lib/screens/standings/league_tab.dart`, replace the `LeagueRow(...)` construction inside `List.generate` (around lines 75–86):

```dart
return LeagueRow(
  rank: i + 1,
  name: isMe ? '${r.displayName} (you)' : r.displayName,
  inSeasonPoints: r.inSeasonPoints,
  preseasonPoints: r.preseasonPoints,
  pointsTotal: r.pointsTotal,
  trend: TrendDirection.equal,
  isMe: isMe,
);
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `flutter test test/components/standings_insights_test.dart && flutter analyze`
Expected: all green.

- [ ] **Step 7: Commit**

```bash
git add lib/api/models/leaderboard_row.dart lib/components/league_row.dart lib/screens/standings/league_tab.dart test/components/standings_insights_test.dart
git commit -m "flutter: surface split in-season + preseason totals on league tab"
```

---

### Task 4: Flutter — `SessionLeaderboardRow` model + `ApiClient.leagueSessionBreakdown`

The backend endpoint `GET /api/leagues/:id/leaderboard/sessions` already exists; only the Flutter side is missing.

**Files:**
- Create: `lib/api/models/session_leaderboard_row.dart`
- Modify: `lib/api/api_client.dart` (add abstract method)
- Modify: `lib/api/http_api_client.dart` (add implementation)
- Test: `test/api/models/session_leaderboard_row_test.dart` (new)

- [ ] **Step 1: Write the failing fromJson test**

Create `test/api/models/session_leaderboard_row_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/models/session_leaderboard_row.dart';

void main() {
  test('SessionLeaderboardRow.fromJson parses a typical payload', () {
    final row = SessionLeaderboardRow.fromJson({
      'sessionId': 17,
      'sessionType': 'race',
      'eventRound': 3,
      'eventName': 'Australian GP',
      'scheduledStart': '2026-03-08T15:00:00Z',
      'members': [
        {'userId': 'u1', 'displayName': 'Anton', 'pointsTotal': 12},
        {'userId': 'u2', 'displayName': 'Lukas', 'pointsTotal': 4},
      ],
    });
    expect(row.sessionId, 17);
    expect(row.sessionType, 'race');
    expect(row.eventRound, 3);
    expect(row.eventName, 'Australian GP');
    expect(row.scheduledStart, DateTime.parse('2026-03-08T15:00:00Z'));
    expect(row.members.length, 2);
    expect(row.members.first.userId, 'u1');
    expect(row.members.first.displayName, 'Anton');
    expect(row.members.first.pointsTotal, 12);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/api/models/session_leaderboard_row_test.dart`
Expected: FAIL (compile error — model not defined).

- [ ] **Step 3: Create the model**

Create `lib/api/models/session_leaderboard_row.dart`:

```dart
class SessionLeaderboardMember {
  final String userId;
  final String displayName;
  final int pointsTotal;
  const SessionLeaderboardMember({
    required this.userId,
    required this.displayName,
    required this.pointsTotal,
  });
  factory SessionLeaderboardMember.fromJson(Map<String, dynamic> j) =>
      SessionLeaderboardMember(
        userId: j['userId'] as String,
        displayName: j['displayName'] as String,
        pointsTotal: (j['pointsTotal'] as num).toInt(),
      );
}

class SessionLeaderboardRow {
  final int sessionId;
  final String sessionType;
  final int eventRound;
  final String eventName;
  final DateTime scheduledStart;
  final List<SessionLeaderboardMember> members;
  const SessionLeaderboardRow({
    required this.sessionId,
    required this.sessionType,
    required this.eventRound,
    required this.eventName,
    required this.scheduledStart,
    required this.members,
  });
  factory SessionLeaderboardRow.fromJson(Map<String, dynamic> j) => SessionLeaderboardRow(
        sessionId: (j['sessionId'] as num).toInt(),
        sessionType: j['sessionType'] as String,
        eventRound: (j['eventRound'] as num).toInt(),
        eventName: j['eventName'] as String,
        scheduledStart: DateTime.parse(j['scheduledStart'] as String),
        members: ((j['members'] as List).cast<Map<String, dynamic>>())
            .map(SessionLeaderboardMember.fromJson)
            .toList(),
      );
}
```

- [ ] **Step 4: Add `leagueSessionBreakdown` to `ApiClient`**

In `lib/api/api_client.dart`, near the existing `leagueLeaderboard` declaration, add the import and the abstract method:

```dart
import 'models/session_leaderboard_row.dart';

// ... inside abstract class ApiClient, in the scores section ...
  Future<List<SessionLeaderboardRow>> leagueSessionBreakdown(String leagueId, {int? season});
```

- [ ] **Step 5: Add the HTTP implementation**

In `lib/api/http_api_client.dart`, near the existing `leagueLeaderboard` impl, add (mirror the existing one's structure — handle `season` query param, decode the wrapping `{ sessions, season }` envelope):

```dart
@override
Future<List<SessionLeaderboardRow>> leagueSessionBreakdown(String leagueId, {int? season}) async {
  final qs = season == null ? '' : '?season=$season';
  final r = await _get('/api/leagues/$leagueId/leaderboard/sessions$qs');
  final list = (r['sessions'] as List).cast<Map<String, dynamic>>();
  return list.map(SessionLeaderboardRow.fromJson).toList();
}
```

(Adjust `_get` to whatever the existing private helper is named — confirm by reading the `leagueLeaderboard` impl in the same file. If it uses `_authedGet` or similar, match that.)

- [ ] **Step 6: Run tests to verify they pass**

Run: `flutter test test/api/models/session_leaderboard_row_test.dart && flutter analyze`
Expected: all green.

- [ ] **Step 7: Commit**

```bash
git add lib/api/models/session_leaderboard_row.dart lib/api/api_client.dart lib/api/http_api_client.dart test/api/models/session_leaderboard_row_test.dart
git commit -m "flutter: add SessionLeaderboardRow model + leagueSessionBreakdown client"
```

---

### Task 5: Flutter — trajectory chart shows every league member

**Files:**
- Modify: `lib/screens/standings/insights_tab.dart` (replace `_buildTrajectory` + extend `_InsightsData` with `sessions`)
- Test: `test/components/standings_insights_test.dart` (extend the trajectory test to assert multi-series)

- [ ] **Step 1: Write the failing test**

In `test/components/standings_insights_test.dart`, add a new test below the existing `TrajectoryChart paints without throwing`:

```dart
  testWidgets('TrajectoryChart renders multiple series with distinct legend labels', (tester) async {
    await tester.pumpWidget(_frame(const TrajectoryChart(
      series: [
        ChartSeries(label: 'You',   color: Color(0xFFE10600), points: [4, 9, 18]),
        ChartSeries(label: 'Lukas', color: Color(0xFF6B6F76), points: [2, 5, 11]),
        ChartSeries(label: 'Simon', color: Color(0xFFB58A3A), points: [1, 8, 14]),
      ],
      xLabels: ['R1', 'R2', 'R3'],
    )));
    expect(find.text('You'),   findsOneWidget);
    expect(find.text('Lukas'), findsOneWidget);
    expect(find.text('Simon'), findsOneWidget);
  });
```

- [ ] **Step 2: Run test to verify it passes against existing chart**

Run: `flutter test test/components/standings_insights_test.dart`
Expected: PASS. The chart widget already supports multiple series — this test guards the legend rendering. (No code change needed yet.)

- [ ] **Step 3: Extend `_InsightsData` and `_load` to fetch the session breakdown**

In `lib/screens/standings/insights_tab.dart`:

```dart
import '../../api/models/session_leaderboard_row.dart';
// ... near existing imports ...

class _InsightsData {
  final String? myUserId;
  final List<MyScore> scores;
  final List<LeaderboardRow> leaderboard;
  final List<SessionLeaderboardRow> sessions;   // NEW
  _InsightsData({
    required this.myUserId,
    required this.scores,
    required this.leaderboard,
    required this.sessions,                     // NEW
  });
}
```

Update `_load`:

```dart
Future<_InsightsData> _load() async {
  final scope = AppState.of(context);
  final myUserId = scope.auth.currentUserId;
  final leagues = scope.auth.leagues;
  final scores = await scope.api.myScores();
  final leagueId = leagues.isEmpty ? null : leagues.first.id;
  final leaderboard = leagueId == null
      ? const <LeaderboardRow>[]
      : await scope.api.leagueLeaderboard(leagueId);
  final sessions = leagueId == null
      ? const <SessionLeaderboardRow>[]
      : await scope.api.leagueSessionBreakdown(leagueId);
  return _InsightsData(
      myUserId: myUserId, scores: scores, leaderboard: leaderboard, sessions: sessions);
}
```

- [ ] **Step 4: Replace `_buildTrajectory` with a multi-series builder**

Remove the existing `_buildTrajectory(_InsightsData d) → _Trajectory?` method and the `_Trajectory` class. Add:

```dart
List<ChartSeries> _buildTrajectorySeries(_InsightsData d) {
  // Backend returns desc by scheduledStart; flip to ascending for chronological plotting.
  final sessions = [...d.sessions]..sort((a, b) => a.scheduledStart.compareTo(b.scheduledStart));
  if (sessions.isEmpty) return const [];

  final pointsByMemberPerSession = <Map<String, int>>[
    for (final s in sessions) { for (final m in s.members) m.userId: m.pointsTotal },
  ];
  final names = <String, String>{};
  for (final s in sessions) {
    for (final m in s.members) names.putIfAbsent(m.userId, () => m.displayName);
  }
  final allIds = names.keys.toList();
  final ordered = [
    if (d.myUserId != null && names.containsKey(d.myUserId)) d.myUserId!,
    ...(allIds.where((id) => id != d.myUserId).toList()
      ..sort((a, b) => names[a]!.compareTo(names[b]!))),
  ];
  const palette = [
    BrandColors.accent,
    Color(0xFF6B6F76),
    Color(0xFFB58A3A),
    Color(0xFF4A7B8C),
    Color(0xFF8E5A7B),
    Color(0xFF5C8C4A),
    Color(0xFF8C5A4A),
  ];
  return [
    for (var i = 0; i < ordered.length; i++)
      ChartSeries(
        label: ordered[i] == d.myUserId ? 'You' : names[ordered[i]]!,
        color: palette[i % palette.length],
        points: _cumulativePoints(pointsByMemberPerSession, ordered[i]),
      ),
  ];
}

List<double> _cumulativePoints(List<Map<String, int>> perSession, String userId) {
  var cum = 0.0;
  return [
    for (final m in perSession) cum += (m[userId] ?? 0).toDouble(),
  ];
}

List<String> _trajectoryXLabels(_InsightsData d) {
  final sessions = [...d.sessions]..sort((a, b) => a.scheduledStart.compareTo(b.scheduledStart));
  return [
    for (final s in sessions) 'R${s.eventRound}·${_typeAbbrev(s.sessionType)}',
  ];
}

String _typeAbbrev(String t) {
  switch (t) {
    case 'race':         return 'R';
    case 'qualifying':   return 'Q';
    case 'sprint':       return 'S';
    case 'sprint_quali': return 'SQ';
    default:             return t.toUpperCase().substring(0, t.length < 2 ? 1 : 2);
  }
}
```

- [ ] **Step 5: Update the `build` method to use the new builder**

Replace the `final trajectory = _buildTrajectory(d);` line and the conditional rendering block (around the `TRAJECTORY` section, ~lines 89–112) with:

```dart
final trajectorySeries = _buildTrajectorySeries(d);
final trajectoryLabels = _trajectoryXLabels(d);
// ... in the children list ...
_h('TRAJECTORY'),
Padding(
  padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
  child: AppCard(
    child: trajectorySeries.isEmpty
        ? Padding(
            padding: const EdgeInsets.all(Spacing.lg),
            child: Text(
              'No scored rounds yet.',
              style: AppText.body(12, color: t.colorScheme.onSurface.withOpacity(0.6)),
            ),
          )
        : TrajectoryChart(series: trajectorySeries, xLabels: trajectoryLabels),
  ),
),
```

- [ ] **Step 6: Run tests and analyzer**

Run: `flutter test && flutter analyze`
Expected: all green.

- [ ] **Step 7: Commit**

```bash
git add lib/screens/standings/insights_tab.dart test/components/standings_insights_test.dart
git commit -m "flutter: trajectory chart overlays every league member"
```

---

### Task 6: Backend — preseason projection module

**Files:**
- Create: `backend/src/preseason/projection.ts`
- Test: `backend/test/unit/preseason/projection.test.ts` (new)

- [ ] **Step 1: Inspect existing scoring helpers**

Skim `backend/src/preseason/singlePick.ts` and `backend/src/preseason/standings.ts` to confirm the exported function names (`scorePreseasonCategory`, `scoreStandings`) and parameter shapes. Also confirm the export of `derive*` helpers from `backend/src/preseason/derive.ts`. These are the building blocks; no need to read them deeply — just verify the signatures the projection module will call.

- [ ] **Step 2: Write the failing unit test**

Create `backend/test/unit/preseason/projection.test.ts`:

```ts
import { describe, it, expect } from 'vitest'
import { projectTruthsFromSnapshot, projectCategoryScore } from '../../../src/preseason/projection.js'
import type { SessionResultRow, DriverStanding, ConstructorStanding } from '../../../src/domain/types.js'

const sess = (id: number, type: 'race' | 'qualifying' | 'sprint') => ({
  id, type, eventId: 1, scheduledStart: new Date(2026, 2, 8), scheduledEnd: new Date(2026, 2, 8, 2),
  status: 'finished' as const, openf1SessionKey: null,
})

const result = (sessionId: number, driverCode: string, constructorId: string, position: number,
                status: string | null = null, fastestLap: string | null = null): SessionResultRow => ({
  sessionId, driverCode, driverName: driverCode, constructorId,
  position, time: null, status, points: null, fastestLap, gridPosition: null,
})

describe('projectTruthsFromSnapshot', () => {
  it('returns observed truth for derivable categories and null for subjective ones', () => {
    const sessions = [sess(1, 'race'), sess(2, 'qualifying'), sess(3, 'race')]
    const results = [
      // R1 race: VER wins, HAM DNF
      result(1, 'VER', 'red_bull', 1, 'Finished', '1'),
      result(1, 'HAM', 'mercedes', null as any, 'Retired'),
      // Q2: VER pole
      result(2, 'VER', 'red_bull', 1),
      // R3 race: HAM DNF again, VER fastest lap
      result(3, 'VER', 'red_bull', 1, 'Finished', '1'),
      result(3, 'HAM', 'mercedes', null as any, 'Engine'),
    ]
    const drivers: DriverStanding[] = [
      { seasonYear: 2026, driverCode: 'VER', position: 1, points: 50, wins: 2, constructorId: 'red_bull' },
      { seasonYear: 2026, driverCode: 'HAM', position: 2, points: 0,  wins: 0, constructorId: 'mercedes' },
    ]
    const constructors: ConstructorStanding[] = [
      { seasonYear: 2026, constructorId: 'red_bull', position: 1, points: 50, wins: 2 },
      { seasonYear: 2026, constructorId: 'mercedes', position: 2, points: 0,  wins: 0 },
    ]

    const truths = projectTruthsFromSnapshot(results, sessions, drivers, constructors)
    expect(truths.dnf.driverCode).toBe('HAM')
    expect(truths.poles.driverCode).toBe('VER')
    expect(truths.fastest_lap.driverCode).toBe('VER')
    expect(truths.wdc_wcc.driverCode).toBe('VER')
    expect(truths.wdc_wcc.constructorId).toBe('red_bull')
    expect(truths.surprise).toBeNull()
    expect(truths.disappointment).toBeNull()
    expect(truths.standings.drivers[0]).toBe('VER')
    expect(truths.standings.constructors[0]).toBe('red_bull')
  })
})

describe('projectCategoryScore', () => {
  it('returns 0 for subjective categories regardless of pick', () => {
    const r = projectCategoryScore('surprise', { driverCode: 'VER', constructorId: null }, null)
    expect(r.projectedPoints).toBe(0)
  })

  it('mirrors scorePreseasonCategory when a projected truth exists', () => {
    const truth = { driverCode: 'VER', constructorId: 'red_bull' }
    const r = projectCategoryScore('dnf', { driverCode: 'VER', constructorId: 'red_bull' }, truth)
    // dnf category awards 4 for driver + 4 for team = 8 (verify against scorePreseasonCategory)
    expect(r.projectedPoints).toBeGreaterThan(0)
  })
})
```

- [ ] **Step 3: Run test to verify it fails**

Run: `make backend-test -- backend/test/unit/preseason/projection.test.ts` (or just `make backend-test` and observe the new file fail).
Expected: FAIL — module not found.

- [ ] **Step 4: Implement the projection module**

Create `backend/src/preseason/projection.ts`:

```ts
import * as eventsRepo from '../repo/events.js'
import * as sessionsRepo from '../repo/sessions.js'
import * as resultsRepo from '../repo/results.js'
import * as standingsRepo from '../repo/standings.js'
import * as picksRepo from '../repo/preseasonPicks.js'
import * as preseasonStandingsRepo from '../repo/preseasonStandings.js'
import * as leagueMembersRepo from '../repo/leagueMembers.js'
import * as usersRepo from '../repo/users.js'
import {
  deriveMostDnfs, derivePolesitter, deriveMostFastestLaps,
  deriveWdcWcc, deriveFinalStandings,
} from './derive.js'
import { scorePreseasonCategory } from './singlePick.js'
import { scoreStandings } from './standings.js'
import type { PreseasonCategory, SessionResultRow, DriverStanding, ConstructorStanding } from '../domain/types.js'
import type { StoredSession } from '../repo/sessions.js'

export type PickPair = { driverCode: string | null; constructorId: string | null }

export type ProjectedTruths = {
  surprise: PickPair | null
  disappointment: PickPair | null
  dnf: PickPair
  poles: PickPair
  fastest_lap: PickPair
  wdc_wcc: PickPair
  standings: { drivers: string[]; constructors: string[] }
}

export type CategoryProjection = {
  category: PreseasonCategory
  myPick: PickPair
  projectedTruth: PickPair | null
  projectedPoints: number
  max: number
}

export type StandingsProjection = {
  myDriverPicks: { position: number; driverCode: string }[]
  myConstructorPicks: { position: number; constructorId: string }[]
  projectedDriverOrder: string[]
  projectedConstructorOrder: string[]
  projectedPoints: number
  max: number
}

export type LeaguePreseasonView = {
  seasonYear: number
  isLocked: boolean
  me: {
    categories: CategoryProjection[]
    standings: StandingsProjection
    projectedPointsTotal: number
  }
  leaderboard: { userId: string; displayName: string; preseasonPointsProjected: number }[]
}

const ALL_CATEGORIES: PreseasonCategory[] = [
  'surprise', 'disappointment', 'dnf', 'poles', 'fastest_lap', 'wdc_wcc',
]

const CATEGORY_MAX: Record<PreseasonCategory, number> = {
  // Mirror the values in singlePick.ts / preseason metadata.
  surprise: 8,
  disappointment: 8,
  dnf: 8,
  poles: 8,
  fastest_lap: 8,
  wdc_wcc: 8,
}

export function projectTruthsFromSnapshot(
  results: SessionResultRow[],
  sessions: StoredSession[],
  drivers: DriverStanding[],
  constructors: ConstructorStanding[],
): ProjectedTruths {
  return {
    surprise: null,
    disappointment: null,
    dnf:         deriveMostDnfs(results, sessions),
    poles:       derivePolesitter(results, sessions),
    fastest_lap: deriveMostFastestLaps(results, sessions),
    wdc_wcc:     deriveWdcWcc(drivers, constructors),
    standings: {
      drivers: deriveFinalStandings(drivers, constructors).drivers.map((d) => d.driverCode),
      constructors: deriveFinalStandings(drivers, constructors).constructors.map((c) => c.constructorId),
    },
  }
}

export function projectCategoryScore(
  category: PreseasonCategory,
  pick: PickPair,
  truth: PickPair | null,
): { projectedPoints: number } {
  if (truth === null) return { projectedPoints: 0 }
  const breakdown = scorePreseasonCategory(category, pick, truth)
  return { projectedPoints: breakdown.pointsTotal }
}

async function loadSeasonSnapshot(seasonYear: number) {
  const events = await eventsRepo.listForSeason(seasonYear)
  const allSessions: StoredSession[] = []
  const allResults: SessionResultRow[] = []
  for (const ev of events) {
    const sessions = await sessionsRepo.listForEvent(ev.id)
    allSessions.push(...sessions)
    for (const s of sessions) {
      const rows = await resultsRepo.listForSession(s.id)
      allResults.push(...rows)
    }
  }
  const drivers = await standingsRepo.listDriverStandings(seasonYear)
  const constructors = await standingsRepo.listConstructorStandings(seasonYear)
  return { allResults, allSessions, drivers, constructors }
}

async function getPreseasonLockTime(seasonYear: number): Promise<Date | null> {
  const ev = await eventsRepo.getByRound(seasonYear, 1)
  if (!ev) return null
  const sessions = await sessionsRepo.listForEvent(ev.id)
  if (sessions.length === 0) return null
  return sessions.sort((a, b) => a.scheduledStart.getTime() - b.scheduledStart.getTime())[0]!.scheduledStart
}

export async function buildLeaguePreseasonView(
  leagueId: string,
  userId: string,
  seasonYear: number,
): Promise<LeaguePreseasonView> {
  const lockAt = await getPreseasonLockTime(seasonYear)
  const isLocked = lockAt !== null && lockAt.getTime() <= Date.now()
  const snap = await loadSeasonSnapshot(seasonYear)
  const truths = projectTruthsFromSnapshot(
    snap.allResults, snap.allSessions, snap.drivers, snap.constructors,
  )

  // ---- me.categories
  const myCategories: CategoryProjection[] = []
  for (const cat of ALL_CATEGORIES) {
    const pick = await picksRepo.getPick(userId, seasonYear, cat)
    const myPick: PickPair = {
      driverCode: pick?.driverCode ?? null,
      constructorId: pick?.constructorId ?? null,
    }
    const truth = truths[cat]
    const proj = projectCategoryScore(cat, myPick, truth)
    myCategories.push({
      category: cat,
      myPick,
      projectedTruth: truth,
      projectedPoints: proj.projectedPoints,
      max: CATEGORY_MAX[cat],
    })
  }

  // ---- me.standings
  const myDriverPicks = await preseasonStandingsRepo.listDriverPicks(userId, seasonYear)
  const myConstructorPicks = await preseasonStandingsRepo.listConstructorPicks(userId, seasonYear)
  const finalStandings = deriveFinalStandings(snap.drivers, snap.constructors)
  const standingsBreakdown = scoreStandings(
    myDriverPicks, myConstructorPicks, finalStandings.drivers, finalStandings.constructors,
  )
  const standingsMax =
    snap.drivers.length * 3 +     // POINTS_PER_DRIVER_SLOT (verify constant name in standings.ts)
    snap.constructors.length * 4  // POINTS_PER_CONSTRUCTOR_SLOT
  const meStandings: StandingsProjection = {
    myDriverPicks: myDriverPicks.map((p) => ({ position: p.position, driverCode: p.driverCode })),
    myConstructorPicks: myConstructorPicks.map((p) => ({ position: p.position, constructorId: p.constructorId })),
    projectedDriverOrder: truths.standings.drivers,
    projectedConstructorOrder: truths.standings.constructors,
    projectedPoints: standingsBreakdown.pointsTotal,
    max: standingsMax,
  }

  const projectedPointsTotal =
    myCategories.reduce((s, c) => s + c.projectedPoints, 0) + meStandings.projectedPoints

  // ---- leaderboard (aggregate only — picks not exposed)
  const memberIds = await leagueMembersRepo.listUserIds(leagueId)
  const leaderboard: LeaguePreseasonView['leaderboard'] = []
  for (const mid of memberIds) {
    const u = await usersRepo.getById(mid)
    if (!u) continue
    let total = 0
    for (const cat of ALL_CATEGORIES) {
      const pick = await picksRepo.getPick(mid, seasonYear, cat)
      const proj = projectCategoryScore(
        cat,
        { driverCode: pick?.driverCode ?? null, constructorId: pick?.constructorId ?? null },
        truths[cat],
      )
      total += proj.projectedPoints
    }
    const dps = await preseasonStandingsRepo.listDriverPicks(mid, seasonYear)
    const cps = await preseasonStandingsRepo.listConstructorPicks(mid, seasonYear)
    total += scoreStandings(dps, cps, finalStandings.drivers, finalStandings.constructors).pointsTotal
    leaderboard.push({
      userId: mid,
      displayName: u.displayName,
      preseasonPointsProjected: total,
    })
  }
  leaderboard.sort((a, b) =>
    b.preseasonPointsProjected - a.preseasonPointsProjected || a.displayName.localeCompare(b.displayName))

  return {
    seasonYear,
    isLocked,
    me: {
      categories: myCategories,
      standings: meStandings,
      projectedPointsTotal,
    },
    leaderboard,
  }
}
```

**Before running tests, verify two assumptions:**
- `leagueMembersRepo.listUserIds(leagueId): Promise<string[]>` — open `backend/src/repo/leagueMembers.js` and confirm it exists with that signature. If the actual export name differs (e.g., `listMembers` returning richer rows), adapt the call.
- `usersRepo.getById(id): Promise<User | null>` — open `backend/src/repo/users.js` and confirm. If the exported function is `getUserById` or similar, adapt.
- The `CATEGORY_MAX` constant: confirm by reading `backend/src/preseason/singlePick.ts` (or wherever the metadata lives) that each category caps at 8. If different (e.g., 4+4 split with bonuses), update the table here to match.
- `POINTS_PER_DRIVER_SLOT` / `POINTS_PER_CONSTRUCTOR_SLOT` constants: read `backend/src/preseason/standings.ts` to confirm 3 / 4 values match.

If any of those don't match, fix the implementation file before re-running tests.

- [ ] **Step 5: Run unit test to verify it passes**

Run: `make backend-test`
Expected: the unit tests in `backend/test/unit/preseason/projection.test.ts` pass; no existing tests regress.

- [ ] **Step 6: Commit**

```bash
git add backend/src/preseason/projection.ts backend/test/unit/preseason/projection.test.ts
git commit -m "backend: preseason projection module (live truth + per-member aggregate)"
```

---

### Task 7: Backend — `GET /api/leagues/:id/preseason` route

**Files:**
- Modify: `backend/src/api/routes/preseason.ts` (add one route)
- Test: `backend/test/integration/api_league_preseason.test.ts` (new)

- [ ] **Step 1: Write the failing integration test**

Create `backend/test/integration/api_league_preseason.test.ts`:

```ts
import { describe, it, expect } from 'vitest'
import { buildApp } from '../../src/index.js'
import * as users from '../../src/repo/users.js'
import * as seasons from '../../src/repo/seasons.js'
import * as events from '../../src/repo/events.js'
import * as sessions from '../../src/repo/sessions.js'
import * as drivers from '../../src/repo/drivers.js'
import * as constructors from '../../src/repo/constructors.js'
import * as standings from '../../src/repo/standings.js'
import * as leagues from '../../src/repo/leagues.js'
import * as members from '../../src/repo/leagueMembers.js'
import * as picks from '../../src/repo/preseasonPicks.js'

async function seed() {
  await seasons.upsertSeason({ year: 2026, isCurrent: true })
  for (const c of ['red_bull', 'mercedes']) {
    await constructors.upsertConstructor({ id: c, name: c, nationality: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, teamColour: null })
  }
  for (const code of ['VER', 'HAM']) {
    await drivers.upsertDriver({ code, givenName: code, familyName: 'X', nationality: null, permanentNumber: null, wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, headshotUrl: null })
  }
  await standings.replaceDriverStandings(2026, [
    { seasonYear: 2026, driverCode: 'VER', position: 1, points: 50, wins: 2, constructorId: 'red_bull' },
    { seasonYear: 2026, driverCode: 'HAM', position: 2, points: 10, wins: 0, constructorId: 'mercedes' },
  ])
  await standings.replaceConstructorStandings(2026, [
    { seasonYear: 2026, constructorId: 'red_bull', position: 1, points: 60, wins: 2 },
    { seasonYear: 2026, constructorId: 'mercedes', position: 2, points: 10, wins: 0 },
  ])
  const ev = await events.upsertEvent({ seasonYear: 2026, round: 1, name: 'B', circuitName: 'C', country: 'X', hasSprint: false })
  await sessions.upsertSession({
    eventId: ev.id, type: 'race',
    scheduledStart: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
    scheduledEnd: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000 + 7200000),
    status: 'scheduled', openf1SessionKey: null,
  })
  return ev
}

describe('GET /api/leagues/:id/preseason', () => {
  it('returns my categories + standings + aggregated leaderboard', async () => {
    await seed()
    const me = await users.insertUser({ email: 'me@x.com', passwordHash: 'h', displayName: 'Me' })
    const other = await users.insertUser({ email: 'o@x.com', passwordHash: 'h', displayName: 'Other' })
    const l = await leagues.createLeagueWithOwner({ name: 'L', ownerUserId: me.id, joinCode: 'PR0001' })
    await members.addMember(l.id, other.id)

    await picks.upsertPick(me.id,    2026, 'wdc_wcc', { driverCode: 'VER', constructorId: 'red_bull' })
    await picks.upsertPick(other.id, 2026, 'wdc_wcc', { driverCode: 'HAM', constructorId: 'mercedes' })

    const app = await buildApp()
    const res = await app.inject({
      method: 'GET',
      url: `/api/leagues/${l.id}/preseason`,
      headers: { authorization: `Bearer ${await users.issueTestToken(me.id)}` },
    })
    expect(res.statusCode).toBe(200)
    const body = res.json() as any
    expect(body.seasonYear).toBe(2026)
    expect(body.me.categories).toHaveLength(6)
    const wdc = body.me.categories.find((c: any) => c.category === 'wdc_wcc')
    expect(wdc.myPick.driverCode).toBe('VER')
    expect(wdc.projectedTruth.driverCode).toBe('VER')
    expect(wdc.projectedPoints).toBeGreaterThan(0)
    // surprise & disappointment have null projectedTruth
    const surprise = body.me.categories.find((c: any) => c.category === 'surprise')
    expect(surprise.projectedTruth).toBeNull()
    expect(surprise.projectedPoints).toBe(0)
    // leaderboard contains both members; aggregate score only, no picks
    expect(body.leaderboard).toHaveLength(2)
    expect(body.leaderboard[0]).toHaveProperty('preseasonPointsProjected')
    expect(body.leaderboard[0]).not.toHaveProperty('picks')
    expect(body.leaderboard[0]).not.toHaveProperty('myPick')
    await app.close()
  })

  it('rejects non-members', async () => {
    await seed()
    const owner = await users.insertUser({ email: 'own@x.com', passwordHash: 'h', displayName: 'Own' })
    const outsider = await users.insertUser({ email: 'out@x.com', passwordHash: 'h', displayName: 'Out' })
    const l = await leagues.createLeagueWithOwner({ name: 'L2', ownerUserId: owner.id, joinCode: 'PR0002' })

    const app = await buildApp()
    const res = await app.inject({
      method: 'GET',
      url: `/api/leagues/${l.id}/preseason`,
      headers: { authorization: `Bearer ${await users.issueTestToken(outsider.id)}` },
    })
    expect(res.statusCode).toBe(403)
    await app.close()
  })
})
```

**Before running, verify:**
- `users.issueTestToken(userId)` — confirm this helper exists in `backend/src/repo/users.ts` (or in `backend/test/helpers/factories.ts`). Several existing integration tests must use it; find one that does (e.g., `api_preseason.test.ts`) and copy its auth approach exactly.
- `members.addMember(leagueId, userId)` — confirm signature.

Match the existing test conventions for auth and seeding rather than the names above if they don't exist verbatim.

- [ ] **Step 2: Run test to verify it fails**

Run: `make backend-test`
Expected: FAIL — route returns 404.

- [ ] **Step 3: Add the route**

In `backend/src/api/routes/preseason.ts`, after the existing imports, add:

```ts
import { requireLeagueMember } from '../auth-context.js'
import { buildLeaguePreseasonView } from '../../preseason/projection.js'
```

Inside `registerPreseasonRoutes`, after the last existing route (`/api/users/me/preseason-scores`), append:

```ts
  app.get<{ Params: { id: string } }>('/api/leagues/:id/preseason', async (req) => {
    const u = getCurrentUser(req)
    await requireLeagueMember(req, req.params.id)
    const year = await getCurrentSeasonYear()
    return await buildLeaguePreseasonView(req.params.id, u.id, year)
  })
```

- [ ] **Step 4: Run test to verify it passes**

Run: `make backend-test`
Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add backend/src/api/routes/preseason.ts backend/test/integration/api_league_preseason.test.ts
git commit -m "backend: route GET /api/leagues/:id/preseason (live projection + member aggregate)"
```

---

### Task 8: Flutter — `LeaguePreseasonView` model + `ApiClient.leaguePreseason`

**Files:**
- Create: `lib/api/models/league_preseason_view.dart`
- Modify: `lib/api/api_client.dart` (add abstract method)
- Modify: `lib/api/http_api_client.dart` (add HTTP impl)
- Test: `test/api/models/league_preseason_view_test.dart` (new)

- [ ] **Step 1: Write the failing fromJson test**

Create `test/api/models/league_preseason_view_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/models/league_preseason_view.dart';
import 'package:predictiongame/domain/preseason.dart';

void main() {
  test('LeaguePreseasonView.fromJson parses categories, standings, leaderboard', () {
    final v = LeaguePreseasonView.fromJson({
      'seasonYear': 2026,
      'isLocked': false,
      'me': {
        'categories': [
          {
            'category': 'wdc_wcc',
            'myPick': {'driverCode': 'VER', 'constructorId': 'red_bull'},
            'projectedTruth': {'driverCode': 'VER', 'constructorId': 'red_bull'},
            'projectedPoints': 8,
            'max': 8,
          },
          {
            'category': 'surprise',
            'myPick': {'driverCode': null, 'constructorId': null},
            'projectedTruth': null,
            'projectedPoints': 0,
            'max': 8,
          },
        ],
        'standings': {
          'myDriverPicks': [{'position': 1, 'driverCode': 'VER'}],
          'myConstructorPicks': [{'position': 1, 'constructorId': 'red_bull'}],
          'projectedDriverOrder': ['VER', 'HAM'],
          'projectedConstructorOrder': ['red_bull', 'mercedes'],
          'projectedPoints': 3,
          'max': 60,
        },
        'projectedPointsTotal': 11,
      },
      'leaderboard': [
        {'userId': 'u1', 'displayName': 'Me',    'preseasonPointsProjected': 11},
        {'userId': 'u2', 'displayName': 'Other', 'preseasonPointsProjected': 0},
      ],
    });
    expect(v.seasonYear, 2026);
    expect(v.isLocked, false);
    expect(v.me.categories.length, 2);
    expect(v.me.categories.first.category, PreseasonCategory.wdc_wcc);
    expect(v.me.categories.first.projectedTruth?.driverCode, 'VER');
    expect(v.me.categories[1].projectedTruth, isNull);
    expect(v.me.standings.projectedDriverOrder.first, 'VER');
    expect(v.me.projectedPointsTotal, 11);
    expect(v.leaderboard.first.displayName, 'Me');
    expect(v.leaderboard.first.preseasonPointsProjected, 11);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/api/models/league_preseason_view_test.dart`
Expected: FAIL — model not defined.

- [ ] **Step 3: Create the model**

Create `lib/api/models/league_preseason_view.dart`:

```dart
import '../../domain/preseason.dart';

class PickPairView {
  final String? driverCode;
  final String? constructorId;
  const PickPairView({this.driverCode, this.constructorId});
  factory PickPairView.fromJson(Map<String, dynamic> j) => PickPairView(
        driverCode: j['driverCode'] as String?,
        constructorId: j['constructorId'] as String?,
      );
}

class CategoryProjectionView {
  final PreseasonCategory category;
  final PickPairView myPick;
  final PickPairView? projectedTruth;
  final int projectedPoints;
  final int max;
  const CategoryProjectionView({
    required this.category,
    required this.myPick,
    required this.projectedTruth,
    required this.projectedPoints,
    required this.max,
  });
  factory CategoryProjectionView.fromJson(Map<String, dynamic> j) => CategoryProjectionView(
        category: PreseasonCategory.values.byName(j['category'] as String),
        myPick: PickPairView.fromJson(j['myPick'] as Map<String, dynamic>),
        projectedTruth: j['projectedTruth'] == null
            ? null
            : PickPairView.fromJson(j['projectedTruth'] as Map<String, dynamic>),
        projectedPoints: (j['projectedPoints'] as num).toInt(),
        max: (j['max'] as num).toInt(),
      );
}

class StandingsProjectionView {
  final List<({int position, String driverCode})> myDriverPicks;
  final List<({int position, String constructorId})> myConstructorPicks;
  final List<String> projectedDriverOrder;
  final List<String> projectedConstructorOrder;
  final int projectedPoints;
  final int max;
  const StandingsProjectionView({
    required this.myDriverPicks,
    required this.myConstructorPicks,
    required this.projectedDriverOrder,
    required this.projectedConstructorOrder,
    required this.projectedPoints,
    required this.max,
  });
  factory StandingsProjectionView.fromJson(Map<String, dynamic> j) => StandingsProjectionView(
        myDriverPicks: ((j['myDriverPicks'] as List).cast<Map<String, dynamic>>())
            .map((p) => (position: (p['position'] as num).toInt(), driverCode: p['driverCode'] as String))
            .toList(),
        myConstructorPicks: ((j['myConstructorPicks'] as List).cast<Map<String, dynamic>>())
            .map((p) => (position: (p['position'] as num).toInt(), constructorId: p['constructorId'] as String))
            .toList(),
        projectedDriverOrder: (j['projectedDriverOrder'] as List).cast<String>(),
        projectedConstructorOrder: (j['projectedConstructorOrder'] as List).cast<String>(),
        projectedPoints: (j['projectedPoints'] as num).toInt(),
        max: (j['max'] as num).toInt(),
      );
}

class MyPreseasonView {
  final List<CategoryProjectionView> categories;
  final StandingsProjectionView standings;
  final int projectedPointsTotal;
  const MyPreseasonView({
    required this.categories,
    required this.standings,
    required this.projectedPointsTotal,
  });
  factory MyPreseasonView.fromJson(Map<String, dynamic> j) => MyPreseasonView(
        categories: ((j['categories'] as List).cast<Map<String, dynamic>>())
            .map(CategoryProjectionView.fromJson)
            .toList(),
        standings: StandingsProjectionView.fromJson(j['standings'] as Map<String, dynamic>),
        projectedPointsTotal: (j['projectedPointsTotal'] as num).toInt(),
      );
}

class LeaguePreseasonLeaderboardRow {
  final String userId;
  final String displayName;
  final int preseasonPointsProjected;
  const LeaguePreseasonLeaderboardRow({
    required this.userId,
    required this.displayName,
    required this.preseasonPointsProjected,
  });
  factory LeaguePreseasonLeaderboardRow.fromJson(Map<String, dynamic> j) =>
      LeaguePreseasonLeaderboardRow(
        userId: j['userId'] as String,
        displayName: j['displayName'] as String,
        preseasonPointsProjected: (j['preseasonPointsProjected'] as num).toInt(),
      );
}

class LeaguePreseasonView {
  final int seasonYear;
  final bool isLocked;
  final MyPreseasonView me;
  final List<LeaguePreseasonLeaderboardRow> leaderboard;
  const LeaguePreseasonView({
    required this.seasonYear,
    required this.isLocked,
    required this.me,
    required this.leaderboard,
  });
  factory LeaguePreseasonView.fromJson(Map<String, dynamic> j) => LeaguePreseasonView(
        seasonYear: (j['seasonYear'] as num).toInt(),
        isLocked: j['isLocked'] as bool,
        me: MyPreseasonView.fromJson(j['me'] as Map<String, dynamic>),
        leaderboard: ((j['leaderboard'] as List).cast<Map<String, dynamic>>())
            .map(LeaguePreseasonLeaderboardRow.fromJson)
            .toList(),
      );
}
```

- [ ] **Step 4: Add `leaguePreseason` to `ApiClient`**

In `lib/api/api_client.dart`, add import and abstract method:

```dart
import 'models/league_preseason_view.dart';

// In the preseason section of abstract class ApiClient:
  Future<LeaguePreseasonView> leaguePreseason(String leagueId);
```

- [ ] **Step 5: Add HTTP impl**

In `lib/api/http_api_client.dart`, near other preseason calls:

```dart
@override
Future<LeaguePreseasonView> leaguePreseason(String leagueId) async {
  final r = await _get('/api/leagues/$leagueId/preseason');
  return LeaguePreseasonView.fromJson(r);
}
```

(Match whichever private helper name `getPreseasonMine` uses.)

- [ ] **Step 6: Run tests + analyzer**

Run: `flutter test test/api/models/league_preseason_view_test.dart && flutter analyze`
Expected: all green.

- [ ] **Step 7: Commit**

```bash
git add lib/api/models/league_preseason_view.dart lib/api/api_client.dart lib/api/http_api_client.dart test/api/models/league_preseason_view_test.dart
git commit -m "flutter: LeaguePreseasonView model + leaguePreseason client"
```

---

### Task 9: Flutter — `PreseasonTab` screen

**Files:**
- Create: `lib/screens/standings/preseason_tab.dart`
- Test: `test/screens/preseason_tab_test.dart` (new)

- [ ] **Step 1: Write the failing widget test**

Create `test/screens/preseason_tab_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/models/league_preseason_view.dart';
import 'package:predictiongame/domain/preseason.dart';
import 'package:predictiongame/screens/standings/preseason_tab.dart';
import 'package:predictiongame/theme/app_theme.dart';

Widget _frame(Widget c) => MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: c),
    );

void main() {
  testWidgets('PreseasonTab renders 6 category cards + standings + leaderboard', (tester) async {
    final view = LeaguePreseasonView(
      seasonYear: 2026,
      isLocked: false,
      me: MyPreseasonView(
        categories: [
          for (final cat in PreseasonCategory.values)
            CategoryProjectionView(
              category: cat,
              myPick: const PickPairView(driverCode: 'VER', constructorId: 'red_bull'),
              projectedTruth: cat == PreseasonCategory.surprise || cat == PreseasonCategory.disappointment
                  ? null
                  : const PickPairView(driverCode: 'VER', constructorId: 'red_bull'),
              projectedPoints: cat == PreseasonCategory.surprise ? 0 : 8,
              max: 8,
            ),
        ],
        standings: const StandingsProjectionView(
          myDriverPicks: [(position: 1, driverCode: 'VER')],
          myConstructorPicks: [(position: 1, constructorId: 'red_bull')],
          projectedDriverOrder: ['VER'],
          projectedConstructorOrder: ['red_bull'],
          projectedPoints: 7,
          max: 60,
        ),
        projectedPointsTotal: 47,
      ),
      leaderboard: const [
        LeaguePreseasonLeaderboardRow(userId: 'u1', displayName: 'Me', preseasonPointsProjected: 47),
        LeaguePreseasonLeaderboardRow(userId: 'u2', displayName: 'Other', preseasonPointsProjected: 16),
      ],
    );
    await tester.pumpWidget(_frame(PreseasonTab.withView(view, myUserId: 'u1')));
    // Each category label appears.
    expect(find.textContaining('SURPRISE'), findsOneWidget);
    expect(find.textContaining('DISAPPOINTMENT'), findsOneWidget);
    // Subjective categories show the "Set at season end" copy.
    expect(find.text('Set at season end'), findsNWidgets(2));
    // Member leaderboard shows both names.
    expect(find.text('Me'), findsOneWidget);
    expect(find.text('Other'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/screens/preseason_tab_test.dart`
Expected: FAIL — screen not defined.

- [ ] **Step 3: Implement the screen**

Create `lib/screens/standings/preseason_tab.dart`:

```dart
// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import '../../api/models/league_preseason_view.dart';
import '../../components/app_card.dart';
import '../../components/error_view.dart';
import '../../domain/preseason.dart';
import '../../state/app_state.dart';
import '../../theme/colors.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';

class PreseasonTab extends StatefulWidget {
  const PreseasonTab({super.key}) : _injected = null, _injectedMyUserId = null;
  const PreseasonTab.withView(LeaguePreseasonView view, {super.key, String? myUserId})
      : _injected = view, _injectedMyUserId = myUserId;

  final LeaguePreseasonView? _injected;
  final String? _injectedMyUserId;

  @override
  State<PreseasonTab> createState() => _PreseasonTabState();
}

class _PreseasonTabState extends State<PreseasonTab> {
  Future<LeaguePreseasonView>? _data;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget._injected != null) {
      _data ??= Future.value(widget._injected);
    } else {
      _data ??= _load();
    }
  }

  Future<LeaguePreseasonView> _load() async {
    final scope = AppState.of(context);
    final leagues = scope.auth.leagues;
    if (leagues.isEmpty) {
      throw StateError('No league joined');
    }
    return scope.api.leaguePreseason(leagues.first.id);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<LeaguePreseasonView>(
      future: _data,
      builder: (_, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return ErrorView(
            error: snap.error!,
            stack: snap.stackTrace,
            where: 'Preseason tab',
            onRetry: () => setState(() => _data = _load()),
          );
        }
        return _Body(view: snap.data!, myUserId: widget._injectedMyUserId ?? AppState.of(context).auth.currentUserId);
      },
    );
  }
}

class _Body extends StatelessWidget {
  final LeaguePreseasonView view;
  final String? myUserId;
  const _Body({required this.view, required this.myUserId});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.only(bottom: Spacing.xxl),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.lg, Spacing.lg, Spacing.xs),
          child: Row(
            children: [
              Expanded(child: Text('PROJECTED · LIVE', style: AppText.label(11))),
              Text('${view.me.projectedPointsTotal} pts',
                  style: AppText.display(18, color: BrandColors.accent)),
            ],
          ),
        ),
        _h('LEAGUE PRESEASON LEADERBOARD'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
          child: AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < view.leaderboard.length; i++)
                  _LeaderRow(rank: i + 1, row: view.leaderboard[i], isMe: view.leaderboard[i].userId == myUserId),
              ],
            ),
          ),
        ),
        _h('YOUR PROJECTIONS'),
        for (final c in view.me.categories) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: 3),
            child: _CategoryCard(card: c),
          ),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: 3),
          child: _StandingsCard(standings: view.me.standings),
        ),
      ],
    );
  }

  Widget _h(String s) => Padding(
        padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.lg, Spacing.lg, Spacing.xs),
        child: Text(s, style: AppText.label(11)),
      );
}

class _LeaderRow extends StatelessWidget {
  final int rank;
  final LeaguePreseasonLeaderboardRow row;
  final bool isMe;
  const _LeaderRow({required this.rank, required this.row, required this.isMe});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: 10),
      color: isMe ? t.colorScheme.surface.withOpacity(0.04) : null,
      child: Row(
        children: [
          SizedBox(width: 22, child: Text('$rank', style: AppText.display(15))),
          const SizedBox(width: 8),
          Expanded(
            child: Text(row.displayName,
                style: AppText.body(13, weight: isMe ? FontWeight.w800 : FontWeight.w700)),
          ),
          Text('+${row.preseasonPointsProjected}',
              style: AppText.display(15, color: isMe ? BrandColors.accent : null)),
        ],
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final CategoryProjectionView card;
  const _CategoryCard({required this.card});

  String _categoryLabel() {
    switch (card.category) {
      case PreseasonCategory.surprise:       return 'SURPRISE';
      case PreseasonCategory.disappointment: return 'DISAPPOINTMENT';
      case PreseasonCategory.dnf:            return 'MOST DNFs';
      case PreseasonCategory.poles:          return 'MOST POLES';
      case PreseasonCategory.fastest_lap:    return 'MOST FASTEST LAPS';
      case PreseasonCategory.wdc_wcc:        return 'WDC + WCC';
    }
  }

  String _renderPair(PickPairView? p) {
    if (p == null) return '—';
    final parts = <String>[];
    if (p.driverCode != null) parts.add(p.driverCode!);
    if (p.constructorId != null) parts.add(p.constructorId!);
    return parts.isEmpty ? '—' : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final subjective = card.projectedTruth == null;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.md, Spacing.lg, Spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: Text(_categoryLabel(), style: AppText.display(15))),
              Text(subjective ? '— / ${card.max}' : '+${card.projectedPoints} / ${card.max}',
                  style: AppText.label(11, color: t.colorScheme.onSurface.withOpacity(0.6))),
            ],
          ),
          const SizedBox(height: 6),
          _kv('Your pick', _renderPair(card.myPick), t),
          const SizedBox(height: 2),
          _kv('On track',
              subjective ? 'Set at season end' : _renderPair(card.projectedTruth),
              t),
        ],
      ),
    );
  }

  Widget _kv(String k, String v, ThemeData t) => Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(k.toUpperCase(),
                style: AppText.label(10, color: t.colorScheme.onSurface.withOpacity(0.55))),
          ),
          Expanded(child: Text(v, style: AppText.body(13, weight: FontWeight.w700))),
        ],
      );
}

class _StandingsCard extends StatelessWidget {
  final StandingsProjectionView standings;
  const _StandingsCard({required this.standings});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final driverHits = _countMatches(standings.myDriverPicks.map((p) => (p.position, p.driverCode)).toList(),
        standings.projectedDriverOrder);
    final teamHits = _countMatches(
        standings.myConstructorPicks.map((p) => (p.position, p.constructorId)).toList(),
        standings.projectedConstructorOrder);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.md, Spacing.lg, Spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: Text('COMPLETE CHAMPIONSHIP', style: AppText.display(15))),
              Text('+${standings.projectedPoints} / ${standings.max}',
                  style: AppText.label(11, color: t.colorScheme.onSurface.withOpacity(0.6))),
            ],
          ),
          const SizedBox(height: 6),
          Text('${driverHits} / ${standings.projectedDriverOrder.length} driver slots · '
               '${teamHits} / ${standings.projectedConstructorOrder.length} team slots',
              style: AppText.body(12, weight: FontWeight.w700)),
        ],
      ),
    );
  }

  int _countMatches(List<(int, String)> myPicks, List<String> order) {
    var hits = 0;
    for (final (pos, id) in myPicks) {
      if (pos - 1 < order.length && order[pos - 1] == id) hits++;
    }
    return hits;
  }
}
```

- [ ] **Step 4: Run tests + analyzer**

Run: `flutter test test/screens/preseason_tab_test.dart && flutter analyze`
Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/standings/preseason_tab.dart test/screens/preseason_tab_test.dart
git commit -m "flutter: PreseasonTab — live projection + per-member leaderboard"
```

---

### Task 10: Wire PRESEASON sub-tab into `StandingsScreen`

**Files:**
- Modify: `lib/screens/standings/standings_screen.dart`

- [ ] **Step 1: Add the new sub-tab**

In `lib/screens/standings/standings_screen.dart`:

1. Add the import:

```dart
import 'preseason_tab.dart';
```

2. In the four-pill row inside `build` (around lines 67–74), update the children to make room for a fourth pill. Reduce font size on labels to 9pt since the row becomes tighter, and shrink spacing between pills:

```dart
Padding(
  padding: const EdgeInsets.fromLTRB(Spacing.xl, Spacing.md, Spacing.xl, Spacing.xs),
  child: Row(children: [
    Expanded(child: _tab('league',    'LEAGUE')),
    const SizedBox(width: 4),
    Expanded(child: _tab('f1',        'F1')),
    const SizedBox(width: 4),
    Expanded(child: _tab('insights',  'INSIGHTS')),
    const SizedBox(width: 4),
    Expanded(child: _tab('preseason', 'PRESEASON')),
  ]),
),
```

3. Extend the body switch:

```dart
Expanded(child: switch (_subTab) {
  'f1'        => const F1Tab(),
  'insights'  => const InsightsTab(),
  'preseason' => const PreseasonTab(),
  _           => const LeagueTab(),
}),
```

4. Adjust `_tab` so it still reads cleanly with the 4-pill density. Reduce the label font to 9pt if it visibly clips on iPhone-SE-sized screens; otherwise leave as-is. Confirm by running:

```bash
flutter run -d "iPhone 17 Pro"   # or whatever simulator is default; verify visually that all four labels render without truncation
```

- [ ] **Step 2: Run the full Flutter test suite**

Run: `flutter test && flutter analyze`
Expected: all green.

- [ ] **Step 3: Commit**

```bash
git add lib/screens/standings/standings_screen.dart
git commit -m "ui: add PRESEASON sub-tab on StandingsScreen"
```

---

### Final verification

- [ ] **Run everything**

```bash
make backend-test && flutter test && flutter analyze
```

Expected: all green.

- [ ] **Manual smoke test**

```bash
make up           # start the backend
make app          # run the iOS app
```

Verify:
1. **Race scores screen:** open a finished session — only the FULL CLASSIFICATION card appears beneath the score banner; no "PICK VS RESULT" duplicate above it.
2. **League tab:** each row shows three numbers (season / pre / total) with the total emphasized.
3. **Insights tab → Trajectory:** all league members appear as separate lines; "You" is the red accent.
4. **Standings header:** four pills visible — LEAGUE / F1 / INSIGHTS / PRESEASON. Tapping PRESEASON loads the new screen with category cards + member leaderboard. Surprise + Disappointment show "Set at season end".

- [ ] **Final commit / housekeeping**

If anything needed an emergency fix during smoke testing, commit it now with a short message describing the fix. Otherwise the branch is ready to push.
