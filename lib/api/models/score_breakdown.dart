class ScoreBreakdownPerPosition {
  final int position;
  final String? driverCode;
  final bool exact;
  final bool wrongPos;
  final int points;

  const ScoreBreakdownPerPosition({
    required this.position,
    required this.driverCode,
    required this.exact,
    required this.wrongPos,
    required this.points,
  });

  factory ScoreBreakdownPerPosition.fromJson(Map<String, dynamic> j) => ScoreBreakdownPerPosition(
        position: j['position'] as int,
        driverCode: j['driverCode'] as String?,
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
