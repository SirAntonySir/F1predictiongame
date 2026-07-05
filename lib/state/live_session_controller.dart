import 'dart:async';
import 'package:flutter/widgets.dart';
import '../api/api_client.dart';
import '../api/models/event.dart';
import '../api/models/live_snapshot.dart';
import '../domain/live_session.dart';

/// Detects the single in-progress scorable session and polls `/live` for it
/// while the app is foregrounded. Home hero + results screen read this; neither
/// re-implements polling. Polling pauses on background and stops when no session
/// is live. [refreshOnce] is exposed for tests (no timer dependency); pass
/// `autoPoll: false` to [update] in tests to drive refreshes manually.
class LiveSessionController extends ChangeNotifier with WidgetsBindingObserver {
  LiveSessionController(
      {required this.api, this.pollInterval = const Duration(seconds: 20)}) {
    WidgetsBinding.instance.addObserver(this);
  }
  final ApiClient api;
  final Duration pollInterval;

  /// Fired once when a polled session's snapshot flips to `finalised` — the
  /// backend has scored it. Wired at boot to a home-cache refresh so the
  /// leaderboard/souvenir update by themselves instead of waiting for the
  /// next mount / pull-to-refresh.
  VoidCallback? onSessionFinalised;

  int? _liveSessionId;
  String? _leagueId;
  LiveSnapshot? _snapshot;
  Timer? _timer;
  bool _autoPoll = true;
  // Session id whose finalisation has already been announced — guards
  // [onSessionFinalised] against firing again on a manual refreshOnce().
  int? _finalisedNotifiedFor;

  int? get liveSessionId => _liveSessionId;
  LiveSnapshot? get snapshot => _snapshot;
  bool isLiveFor(int sessionId) => _liveSessionId == sessionId;

  /// Recompute the live session from [events]; (re)start or stop polling.
  /// Call when home data loads and on login/league changes. [leagueId] enables
  /// league projections in the snapshot. [autoPoll] = false for tests.
  void update(List<Event> events, DateTime now,
      {String? leagueId, bool autoPoll = true}) {
    _autoPoll = autoPoll;
    _leagueId = leagueId;
    final live = findLiveSession(events, now);
    final newId = live?.id;
    if (newId == _liveSessionId) {
      if (newId != null && autoPoll) _ensureTimer();
      return;
    }
    _liveSessionId = newId;
    _snapshot = null;
    _timer?.cancel();
    _timer = null;
    notifyListeners();
    if (newId != null && autoPoll) {
      // ignore: discarded_futures
      refreshOnce();
      _ensureTimer();
    }
  }

  Future<void> refreshOnce() async {
    final id = _liveSessionId;
    if (id == null) return;
    try {
      final snap = await api.sessionLive(id, leagueId: _leagueId);
      if (id != _liveSessionId) return; // changed mid-flight
      _snapshot = snap;
      notifyListeners();
      if (snap.state == LiveState.finalised) {
        // Session got scored — stop polling and announce it once, so the
        // home cache can refresh itself with the final scores immediately.
        _timer?.cancel();
        _timer = null;
        if (_finalisedNotifiedFor != id) {
          _finalisedNotifiedFor = id;
          onSessionFinalised?.call();
        }
      }
    } catch (_) {
      // Best-effort; keep the previous snapshot, try again next tick.
    }
  }

  void _ensureTimer() {
    _timer ??= Timer.periodic(pollInterval, (_) {
      // ignore: discarded_futures
      refreshOnce();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_autoPoll) return;
    if (state == AppLifecycleState.resumed) {
      if (_liveSessionId != null) {
        // ignore: discarded_futures
        refreshOnce();
        _ensureTimer();
      }
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }
}
