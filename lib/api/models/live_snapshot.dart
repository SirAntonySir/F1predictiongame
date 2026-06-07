import 'member_prediction.dart';
import 'session_result.dart';

enum LiveState { pre, live, provisional, finalised, unavailable }

LiveState _stateFrom(String s) {
  switch (s) {
    case 'pre':
      return LiveState.pre;
    case 'live':
      return LiveState.live;
    case 'provisional':
      return LiveState.provisional;
    case 'final':
      return LiveState.finalised;
    default:
      return LiveState.unavailable;
  }
}

/// One poll of the live endpoint. `order` reuses [SessionResult] so the existing
/// colored-row rendering works unchanged. `league` reuses [MemberPrediction]
/// (userId/displayName/picks/pointsTotal) with pointsTotal = backend-projected.
class LiveSnapshot {
  final int sessionId;
  final LiveState state;

  /// When the backend computed this snapshot. Optional (tests construct without
  /// it); the UI doesn't depend on it.
  final DateTime? asOf;
  final List<SessionResult> order;

  /// Caller's projected total; null when picks are incomplete/absent.
  final int? myPointsTotal;

  /// Each league member's picks + projected total, excluding the caller, sorted desc.
  final List<MemberPrediction> league;

  const LiveSnapshot({
    required this.sessionId,
    required this.state,
    this.asOf,
    required this.order,
    required this.myPointsTotal,
    required this.league,
  });

  factory LiveSnapshot.fromJson(Map<String, dynamic> j) => LiveSnapshot(
        sessionId: j['sessionId'] as int,
        state: _stateFrom(j['state'] as String),
        asOf: j['asOf'] == null
            ? null
            : DateTime.parse(j['asOf'] as String).toLocal(),
        order: ((j['order'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(SessionResult.fromJson)
            .toList(),
        myPointsTotal:
            (j['myProjected'] as Map<String, dynamic>?)?['pointsTotal'] as int?,
        league: ((j['leagueProjected'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(MemberPrediction.fromJson)
            .toList(),
      );
}
