/// Light-weight reference to a player in a gossip line.
class GossipPlayer {
  final String userId;
  final String displayName;
  final int? points;
  const GossipPlayer({
    required this.userId,
    required this.displayName,
    this.points,
  });

  factory GossipPlayer.fromJson(Map<String, dynamic> j) => GossipPlayer(
        userId: j['userId'] as String,
        displayName: j['displayName'] as String,
        points: j['points'] == null ? null : (j['points'] as num).toInt(),
      );
}

class GossipLastRace {
  final int sessionId;
  final int round;
  final String name;
  const GossipLastRace({
    required this.sessionId,
    required this.round,
    required this.name,
  });

  factory GossipLastRace.fromJson(Map<String, dynamic> j) => GossipLastRace(
        sessionId: (j['sessionId'] as num).toInt(),
        round: (j['round'] as num).toInt(),
        name: j['name'] as String,
      );
}

class GossipDriverPoints {
  final String driverCode;
  final int points;
  const GossipDriverPoints({required this.driverCode, required this.points});
  factory GossipDriverPoints.fromJson(Map<String, dynamic> j) =>
      GossipDriverPoints(
        driverCode: j['driverCode'] as String,
        points: (j['points'] as num).toInt(),
      );
}

class GossipDriverMisses {
  final String driverCode;
  final int count;
  const GossipDriverMisses({required this.driverCode, required this.count});
  factory GossipDriverMisses.fromJson(Map<String, dynamic> j) =>
      GossipDriverMisses(
        driverCode: j['driverCode'] as String,
        count: (j['count'] as num).toInt(),
      );
}

/// Caller's preseason projection snapshots used to surface the
/// "projection delta since last weekend" tile in YOUR SEASON.
/// `previous` and `delta` are null when fewer than two race-keyed snapshots
/// exist (typically right after launch or before the season's second race).
class GossipMyProjection {
  final int now;
  final int? previous;
  final int? delta;
  const GossipMyProjection({
    required this.now,
    required this.previous,
    required this.delta,
  });

  factory GossipMyProjection.fromJson(Map<String, dynamic> j) =>
      GossipMyProjection(
        now: (j['now'] as num).toInt(),
        previous: j['previous'] == null ? null : (j['previous'] as num).toInt(),
        delta: j['delta'] == null ? null : (j['delta'] as num).toInt(),
      );
}

/// Snapshot of gossip-worthy facts from the most recent finished race.
/// Returned by `GET /api/leagues/:id/gossip`. `lastRace == null` when no
/// race has finished in the current season yet.
class LeagueGossip {
  final GossipLastRace? lastRace;
  final GossipPlayer? bestPlayer;
  final List<GossipPlayer> worstPlayers;
  final List<GossipPlayer> noShowPlayers;
  final GossipDriverPoints? driverGained;
  final GossipDriverMisses? driverCost;
  final GossipMyProjection? myProjection;

  const LeagueGossip({
    required this.lastRace,
    required this.bestPlayer,
    required this.worstPlayers,
    required this.noShowPlayers,
    required this.driverGained,
    required this.driverCost,
    required this.myProjection,
  });

  factory LeagueGossip.fromJson(Map<String, dynamic> j) => LeagueGossip(
        lastRace: j['lastRace'] == null
            ? null
            : GossipLastRace.fromJson(j['lastRace'] as Map<String, dynamic>),
        bestPlayer: j['bestPlayer'] == null
            ? null
            : GossipPlayer.fromJson(j['bestPlayer'] as Map<String, dynamic>),
        worstPlayers: ((j['worstPlayers'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(GossipPlayer.fromJson)
            .toList(),
        noShowPlayers: ((j['noShowPlayers'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(GossipPlayer.fromJson)
            .toList(),
        driverGained: j['driverGained'] == null
            ? null
            : GossipDriverPoints.fromJson(
                j['driverGained'] as Map<String, dynamic>),
        driverCost: j['driverCost'] == null
            ? null
            : GossipDriverMisses.fromJson(
                j['driverCost'] as Map<String, dynamic>),
        myProjection: j['myProjection'] == null
            ? null
            : GossipMyProjection.fromJson(
                j['myProjection'] as Map<String, dynamic>),
      );
}
