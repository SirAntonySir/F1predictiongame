// Composite payload for the player profile screen.

class PlayerProfile {
  final PlayerHeader player;
  final int seasonYear;
  final PlayerStanding standing;
  final List<RecentFormItem> recentForm;
  final PlayerInsights insights;
  final PlayerPreseason preseason;
  final List<PlayerPickLogItem> pickLog;
  const PlayerProfile({
    required this.player,
    required this.seasonYear,
    required this.standing,
    required this.recentForm,
    required this.insights,
    required this.preseason,
    required this.pickLog,
  });

  factory PlayerProfile.fromJson(Map<String, dynamic> j) => PlayerProfile(
        player: PlayerHeader.fromJson(j['player'] as Map<String, dynamic>),
        seasonYear: (j['season']['year'] as num).toInt(),
        standing: PlayerStanding.fromJson(j['standing'] as Map<String, dynamic>),
        recentForm: (j['recentForm'] as List)
            .cast<Map<String, dynamic>>()
            .map(RecentFormItem.fromJson)
            .toList(),
        insights: PlayerInsights.fromJson(j['insights'] as Map<String, dynamic>),
        preseason: PlayerPreseason.fromJson(j['preseason'] as Map<String, dynamic>),
        pickLog: (j['pickLog'] as List)
            .cast<Map<String, dynamic>>()
            .map(PlayerPickLogItem.fromJson)
            .toList(),
      );
}

class PlayerHeader {
  final String userId;
  final String displayName;
  final DateTime joinedAt;
  final bool isSelf;
  const PlayerHeader({
    required this.userId,
    required this.displayName,
    required this.joinedAt,
    required this.isSelf,
  });
  factory PlayerHeader.fromJson(Map<String, dynamic> j) => PlayerHeader(
        userId: j['userId'] as String,
        displayName: j['displayName'] as String,
        joinedAt: DateTime.parse(j['joinedAt'] as String),
        isSelf: j['isSelf'] as bool,
      );
}

class PlayerStanding {
  /// 1-indexed rank inside the league. null when the player has zero score
  /// rows and isn't in the leaderboard.
  final int? leagueRank;
  final int leagueSize;
  final int pointsTotal;
  final int inSeasonPoints;
  final int preseasonPoints;
  final int sessionsScored;
  const PlayerStanding({
    required this.leagueRank,
    required this.leagueSize,
    required this.pointsTotal,
    required this.inSeasonPoints,
    required this.preseasonPoints,
    required this.sessionsScored,
  });
  factory PlayerStanding.fromJson(Map<String, dynamic> j) => PlayerStanding(
        leagueRank: (j['leagueRank'] as num?)?.toInt(),
        leagueSize: (j['leagueSize'] as num).toInt(),
        pointsTotal: (j['pointsTotal'] as num).toInt(),
        inSeasonPoints: (j['inSeasonPoints'] as num).toInt(),
        preseasonPoints: (j['preseasonPoints'] as num).toInt(),
        sessionsScored: (j['sessionsScored'] as num).toInt(),
      );
}

enum FormGlyph { exact, wrongPos, miss, teamBonus }

FormGlyph _glyphFrom(String s) => switch (s) {
      'exact' => FormGlyph.exact,
      'wrongPos' => FormGlyph.wrongPos,
      'teamBonus' => FormGlyph.teamBonus,
      _ => FormGlyph.miss,
    };

class RecentFormItem {
  final int sessionId;
  final int round;
  final String eventName;
  final String sessionType;
  final int points;
  final List<FormGlyph> glyphs;
  const RecentFormItem({
    required this.sessionId,
    required this.round,
    required this.eventName,
    required this.sessionType,
    required this.points,
    required this.glyphs,
  });
  factory RecentFormItem.fromJson(Map<String, dynamic> j) => RecentFormItem(
        sessionId: (j['sessionId'] as num).toInt(),
        round: (j['round'] as num).toInt(),
        eventName: j['eventName'] as String,
        sessionType: j['sessionType'] as String,
        points: (j['points'] as num).toInt(),
        glyphs: (j['glyphs'] as List).cast<String>().map(_glyphFrom).toList(),
      );
}

class MostPickedP1 {
  final String driverCode;
  final int count;
  const MostPickedP1({required this.driverCode, required this.count});
  factory MostPickedP1.fromJson(Map<String, dynamic> j) => MostPickedP1(
        driverCode: j['driverCode'] as String,
        count: (j['count'] as num).toInt(),
      );
}

class BestWeekend {
  final int round;
  final String eventName;
  /// Total points across every scored session in this weekend (race + sprint
  /// + sprint quali + qualifying). Sum, not max.
  final int points;
  final int sessions;
  const BestWeekend({
    required this.round,
    required this.eventName,
    required this.points,
    required this.sessions,
  });
  factory BestWeekend.fromJson(Map<String, dynamic> j) => BestWeekend(
        round: (j['round'] as num).toInt(),
        eventName: j['eventName'] as String,
        points: (j['points'] as num).toInt(),
        sessions: (j['sessions'] as num).toInt(),
      );
}

class PlayerInsights {
  final MostPickedP1? mostPickedP1;
  final BestWeekend? bestWeekend;
  final double? exactHitRate;
  final double? teamBonusRate;
  final int sessionsScored;
  final int totalSlots;
  final int exactSlots;
  const PlayerInsights({
    required this.mostPickedP1,
    required this.bestWeekend,
    required this.exactHitRate,
    required this.teamBonusRate,
    required this.sessionsScored,
    required this.totalSlots,
    required this.exactSlots,
  });
  factory PlayerInsights.fromJson(Map<String, dynamic> j) => PlayerInsights(
        mostPickedP1: j['mostPickedP1'] == null
            ? null
            : MostPickedP1.fromJson(j['mostPickedP1'] as Map<String, dynamic>),
        bestWeekend: j['bestWeekend'] == null
            ? null
            : BestWeekend.fromJson(j['bestWeekend'] as Map<String, dynamic>),
        exactHitRate: (j['exactHitRate'] as num?)?.toDouble(),
        teamBonusRate: (j['teamBonusRate'] as num?)?.toDouble(),
        sessionsScored: (j['sessionsScored'] as num).toInt(),
        totalSlots: (j['totalSlots'] as num).toInt(),
        exactSlots: (j['exactSlots'] as num).toInt(),
      );
}

class PreseasonCategoryPick {
  final String category;
  final String? driverCode;
  final String? constructorId;
  /// Total points (driver side + team side) currently scored on this pick.
  final int points;
  /// Driver-side correctness — picked driver matches the truth driver for
  /// the category.
  final bool driverExact;
  final int driverPoints;
  /// Team-side correctness — picked constructor matches the truth team.
  final bool teamExact;
  final int teamPoints;
  const PreseasonCategoryPick({
    required this.category,
    required this.driverCode,
    required this.constructorId,
    required this.points,
    required this.driverExact,
    required this.driverPoints,
    required this.teamExact,
    required this.teamPoints,
  });
  factory PreseasonCategoryPick.fromJson(Map<String, dynamic> j) => PreseasonCategoryPick(
        category: j['category'] as String,
        driverCode: j['driverCode'] as String?,
        constructorId: j['constructorId'] as String?,
        points: (j['points'] as num?)?.toInt() ?? 0,
        driverExact: j['driverExact'] as bool? ?? false,
        driverPoints: (j['driverPoints'] as num?)?.toInt() ?? 0,
        teamExact: j['teamExact'] as bool? ?? false,
        teamPoints: (j['teamPoints'] as num?)?.toInt() ?? 0,
      );
}

class PreseasonRankedPick {
  final int position;
  final String code;
  const PreseasonRankedPick({required this.position, required this.code});
}

class PlayerPreseason {
  final List<PreseasonCategoryPick> picks;
  final List<PreseasonRankedPick> driverStandings;
  final List<PreseasonRankedPick> constructorStandings;
  final int? projectedTotal;
  const PlayerPreseason({
    required this.picks,
    required this.driverStandings,
    required this.constructorStandings,
    required this.projectedTotal,
  });
  factory PlayerPreseason.fromJson(Map<String, dynamic> j) => PlayerPreseason(
        picks: (j['picks'] as List)
            .cast<Map<String, dynamic>>()
            .map(PreseasonCategoryPick.fromJson)
            .toList(),
        driverStandings: (j['driverStandings'] as List)
            .cast<Map<String, dynamic>>()
            .map((m) => PreseasonRankedPick(
                position: (m['position'] as num).toInt(),
                code: m['driverCode'] as String))
            .toList(),
        constructorStandings: (j['constructorStandings'] as List)
            .cast<Map<String, dynamic>>()
            .map((m) => PreseasonRankedPick(
                position: (m['position'] as num).toInt(),
                code: m['constructorId'] as String))
            .toList(),
        projectedTotal: (j['projectedTotal'] as num?)?.toInt(),
      );
}

class PickLogPick {
  final int position;
  final String driverCode;
  final String? constructorId;
  const PickLogPick({
    required this.position,
    required this.driverCode,
    this.constructorId,
  });
}

class PickLogResult {
  final int position;
  final String driverCode;
  final String constructorId;
  const PickLogResult({
    required this.position,
    required this.driverCode,
    required this.constructorId,
  });
}

class PickLogScore {
  final int points;
  /// Raw breakdown — perPosition list + teamBonus block. Left as dynamic to
  /// keep the model permissive; the UI just needs the points + the glyphs.
  final Map<String, dynamic> breakdown;
  const PickLogScore({required this.points, required this.breakdown});
}

class PlayerPickLogItem {
  final int sessionId;
  final int round;
  final String eventName;
  final String sessionType;
  final DateTime scheduledStart;
  /// 'app' = entered via the predict screen. 'import' = bulk-imported by the
  /// owner. UI surfaces a tiny "imported" tag for the latter.
  final String source;
  final List<PickLogPick> picks;
  final List<PickLogResult> topResults;
  final PickLogScore? score;
  const PlayerPickLogItem({
    required this.sessionId,
    required this.round,
    required this.eventName,
    required this.sessionType,
    required this.scheduledStart,
    required this.source,
    required this.picks,
    required this.topResults,
    required this.score,
  });
  factory PlayerPickLogItem.fromJson(Map<String, dynamic> j) => PlayerPickLogItem(
        sessionId: (j['sessionId'] as num).toInt(),
        round: (j['round'] as num).toInt(),
        eventName: j['eventName'] as String,
        sessionType: j['sessionType'] as String,
        scheduledStart: DateTime.parse(j['scheduledStart'] as String),
        source: j['source'] as String,
        picks: (j['picks'] as List)
            .cast<Map<String, dynamic>>()
            .map((m) => PickLogPick(
                position: (m['position'] as num).toInt(),
                driverCode: m['driverCode'] as String,
                constructorId: m['constructorId'] as String?))
            .toList(),
        topResults: (j['topResults'] as List)
            .cast<Map<String, dynamic>>()
            .map((m) => PickLogResult(
                position: (m['position'] as num).toInt(),
                driverCode: m['driverCode'] as String,
                constructorId: m['constructorId'] as String))
            .toList(),
        score: j['score'] == null
            ? null
            : PickLogScore(
                points: ((j['score'] as Map)['points'] as num).toInt(),
                breakdown: ((j['score'] as Map)['breakdown'] as Map<String, dynamic>),
              ),
      );
}
