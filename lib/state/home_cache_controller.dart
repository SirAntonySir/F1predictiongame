import 'package:flutter/foundation.dart';
import '../api/api_client.dart';
import '../api/models/event.dart';
import '../api/models/leaderboard_row.dart';
import '../api/models/session.dart';
import '../api/models/session_result.dart';
import 'auth_controller.dart';
import 'predictions_controller.dart';

/// Snapshot of everything the home screen renders. Held by [HomeCacheController]
/// so a screen rebuild (tab switch, hot reload, navigate-and-back) starts from
/// the last known value instead of an empty spinner.
class HomeData {
  final List<Event> events;
  final Session? next;
  final Session? nextPickable;
  final Event? nextEvent;
  final Event? pickEvent;
  final Event? lastEvent;
  final Session? lastRaceSession;
  final List<SessionResult> lastResult;
  final List<LeaderboardRow> leaderboard;
  const HomeData({
    required this.events,
    required this.next,
    required this.nextPickable,
    required this.nextEvent,
    required this.pickEvent,
    required this.lastEvent,
    required this.lastRaceSession,
    required this.lastResult,
    required this.leaderboard,
  });

  /// Realistic-shape dummy data used as the layout target while we render a
  /// Skeletonizer-grayed first-load placeholder. Has every field non-null so
  /// the home screen's `if (d.next != null) …` branches render their boxes
  /// (which then get grayed out).
  factory HomeData.placeholder() {
    final start = DateTime.now().add(const Duration(days: 7));
    final session = Session(
      id: 0,
      type: SessionType.race,
      scheduledStart: start,
      scheduledEnd: start.add(const Duration(hours: 2)),
      status: SessionStatus.scheduled,
    );
    final event = Event(
      round: 0,
      name: 'Loading Grand Prix',
      country: 'XX',
      circuitName: 'Loading Circuit',
      hasSprint: false,
      sessions: [session],
    );
    return HomeData(
      events: [event],
      next: session,
      nextPickable: session,
      nextEvent: event,
      pickEvent: event,
      lastEvent: event,
      lastRaceSession: session,
      lastResult: const [
        SessionResult(position: 1, driverCode: 'AAA', driverName: 'Loading Driver', constructorId: 'loading', constructorName: 'Loading'),
        SessionResult(position: 2, driverCode: 'BBB', driverName: 'Loading Driver', constructorId: 'loading', constructorName: 'Loading'),
        SessionResult(position: 3, driverCode: 'CCC', driverName: 'Loading Driver', constructorId: 'loading', constructorName: 'Loading'),
        SessionResult(position: 4, driverCode: 'DDD', driverName: 'Loading Driver', constructorId: 'loading', constructorName: 'Loading'),
        SessionResult(position: 5, driverCode: 'EEE', driverName: 'Loading Driver', constructorId: 'loading', constructorName: 'Loading'),
      ],
      leaderboard: const [
        LeaderboardRow(userId: 'p1', displayName: 'Player one',   inSeasonPoints: 0, preseasonPoints: 0, pointsTotal: 0, sessionsScored: 0),
        LeaderboardRow(userId: 'p2', displayName: 'Player two',   inSeasonPoints: 0, preseasonPoints: 0, pointsTotal: 0, sessionsScored: 0),
        LeaderboardRow(userId: 'p3', displayName: 'Player three', inSeasonPoints: 0, preseasonPoints: 0, pointsTotal: 0, sessionsScored: 0),
        LeaderboardRow(userId: 'p4', displayName: 'Player four',  inSeasonPoints: 0, preseasonPoints: 0, pointsTotal: 0, sessionsScored: 0),
      ],
    );
  }
}

/// Stale-while-revalidate cache for the home screen.
///
/// API: caller invokes [refresh] whenever it would have called the network
/// (mount, pull-to-refresh, foreground resume). The controller dedupes
/// concurrent refreshes, keeps the previous [data] visible while a refresh
/// is in flight (so the UI never reverts to a spinner once it's seen real
/// content), and notifies listeners on every state change.
///
/// State combinations a screen needs to handle:
///   - data == null && refreshing → first-load skeleton
///   - data == null && error != null → first-load error
///   - data != null && refreshing → stale value + thin top progress bar
///   - data != null → fully fresh content
///
/// [clear] wipes everything (use on logout).
class HomeCacheController extends ChangeNotifier {
  HomeCacheController({
    required this.api,
    required this.auth,
    required this.predictions,
  });

  final ApiClient api;
  final AuthController auth;
  final PredictionsController predictions;

  HomeData? _data;
  Object? _error;
  StackTrace? _stack;
  bool _refreshing = false;
  Future<void>? _inflight;

  HomeData? get data => _data;
  Object? get error => _error;
  StackTrace? get stack => _stack;
  bool get refreshing => _refreshing;

  /// Trigger a fresh fetch. Returns the same in-flight future if a refresh
  /// is already running — never starts two concurrent loads.
  Future<void> refresh() {
    return _inflight ??= _doRefresh();
  }

  Future<void> _doRefresh() async {
    _refreshing = true;
    notifyListeners();
    try {
      _data = await _fetch();
      _error = null;
      _stack = null;
    } catch (e, st) {
      _error = e;
      _stack = st;
      // Keep the previous _data so a network blip doesn't blank the screen.
    } finally {
      _refreshing = false;
      _inflight = null;
      notifyListeners();
    }
  }

  void clear() {
    _data = null;
    _error = null;
    _stack = null;
    _refreshing = false;
    _inflight = null;
    notifyListeners();
  }

  // Same shape and behaviour as the old _HomeState._load — moved here so the
  // cache controls the lifecycle. Best-effort: a failure on any sub-call
  // either falls back to a sensible default or propagates only when the call
  // is critical for rendering (events).
  Future<HomeData> _fetch() async {
    final events = await api.events();
    // Re-arm pick reminders for unpicked sessions whenever the home screen
    // loads. Idempotent — the service cancels-then-reschedules.
    // ignore: discarded_futures
    predictions.refreshUpcoming().catchError((_) {});
    final leagues = auth.leagues;
    List<LeaderboardRow> leaderboard = const [];
    if (leagues.isNotEmpty) {
      try {
        leaderboard = await api.leagueLeaderboard(leagues.first.id);
      } catch (_) {
        leaderboard = const [];
      }
    }
    Session? next;
    try {
      next = await api.nextSession();
    } on NotFoundException {
      next = null;
    }
    next ??= _computeNextSession(events, pickableOnly: false);
    final nextPickable = _computeNextSession(events, pickableOnly: true);
    Event? nextEvent;
    if (next != null) {
      final resolvedNext = next;
      nextEvent = events.firstWhere(
        (e) => e.sessions.any((s) => s.id == resolvedNext.id),
        orElse: () => events.first,
      );
    }
    Event? pickEvent;
    if (nextPickable != null) {
      final resolvedPick = nextPickable;
      try {
        pickEvent = events.firstWhere(
          (e) => e.sessions.any((s) => s.id == resolvedPick.id),
        );
      } catch (_) {
        pickEvent = nextEvent;
      }
    }
    if (nextPickable != null) {
      try {
        await predictions.fetchPrediction(nextPickable.id);
      } catch (_) {
        // Non-fatal — pick card falls back to "no picks yet"
      }
    }
    final finishedRace = events.lastWhere(
      (e) => e.sessions.any((s) =>
          s.type == SessionType.race && s.status == SessionStatus.finished),
      orElse: () => const Event(
        round: 0,
        name: '',
        country: '',
        circuitName: '',
        hasSprint: false,
        sessions: [],
      ),
    );
    Event? lastEvent;
    Session? lastRaceSession;
    List<SessionResult> lastResult = const [];
    if (finishedRace.sessions.isNotEmpty) {
      lastEvent = finishedRace;
      lastRaceSession = finishedRace.sessions.firstWhere(
        (s) => s.type == SessionType.race,
        orElse: () => finishedRace.sessions.first,
      );
      try {
        lastResult = await api.sessionResults(lastRaceSession.id);
      } on NotFoundException {
        lastResult = const [];
      }
    }
    return HomeData(
      events: events,
      next: next,
      nextPickable: nextPickable,
      nextEvent: nextEvent,
      pickEvent: pickEvent,
      lastEvent: lastEvent,
      lastRaceSession: lastRaceSession,
      lastResult: lastResult,
      leaderboard: leaderboard,
    );
  }

  Session? _computeNextSession(List<Event> events, {required bool pickableOnly}) {
    bool isPickable(SessionType t) =>
        t == SessionType.qualifying ||
        t == SessionType.sprint_quali ||
        t == SessionType.sprint ||
        t == SessionType.race;
    final now = DateTime.now();
    Session? best;
    for (final e in events) {
      for (final s in e.sessions) {
        if (s.status != SessionStatus.scheduled) continue;
        if (!s.scheduledStart.isAfter(now)) continue;
        if (pickableOnly && !isPickable(s.type)) continue;
        if (best == null || s.scheduledStart.isBefore(best.scheduledStart)) {
          best = s;
        }
      }
    }
    return best;
  }
}
