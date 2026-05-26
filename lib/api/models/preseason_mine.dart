import '../../domain/preseason.dart';

class PreseasonSinglePick {
  final String? driverCode;
  final String? constructorId;
  const PreseasonSinglePick({this.driverCode, this.constructorId});
  bool get isEmpty => driverCode == null && constructorId == null;

  factory PreseasonSinglePick.fromJson(Map<String, dynamic> j) => PreseasonSinglePick(
        driverCode: j['driverCode'] as String?,
        constructorId: j['constructorId'] as String?,
      );
}

class PreseasonStandingsDriverPick {
  final int position;
  final String driverCode;
  const PreseasonStandingsDriverPick({required this.position, required this.driverCode});

  factory PreseasonStandingsDriverPick.fromJson(Map<String, dynamic> j) => PreseasonStandingsDriverPick(
        position: (j['position'] as num).toInt(),
        // Backend uses `entityId` in the picks list payload.
        driverCode: (j['driverCode'] ?? j['entityId']) as String,
      );

  Map<String, dynamic> toJson() => {'position': position, 'driverCode': driverCode};
}

class PreseasonStandingsConstructorPick {
  final int position;
  final String constructorId;
  const PreseasonStandingsConstructorPick({required this.position, required this.constructorId});

  factory PreseasonStandingsConstructorPick.fromJson(Map<String, dynamic> j) => PreseasonStandingsConstructorPick(
        position: (j['position'] as num).toInt(),
        constructorId: (j['constructorId'] ?? j['entityId']) as String,
      );

  Map<String, dynamic> toJson() => {'position': position, 'constructorId': constructorId};
}

/// Full /api/preseason/my response.
class PreseasonMine {
  final int seasonYear;
  final bool isLocked;
  final DateTime? locksAt;
  final Map<PreseasonCategory, PreseasonSinglePick> picks;
  final List<PreseasonStandingsDriverPick> driverStandings;
  final List<PreseasonStandingsConstructorPick> constructorStandings;

  const PreseasonMine({
    required this.seasonYear,
    required this.isLocked,
    required this.locksAt,
    required this.picks,
    required this.driverStandings,
    required this.constructorStandings,
  });

  factory PreseasonMine.fromJson(Map<String, dynamic> j) {
    final picks = <PreseasonCategory, PreseasonSinglePick>{};
    for (final cat in PreseasonCategory.values) {
      final raw = j[cat.name];
      if (raw is Map) {
        picks[cat] = PreseasonSinglePick.fromJson(raw.cast<String, dynamic>());
      }
    }
    final standings = (j['standings'] as Map?)?.cast<String, dynamic>() ?? const {};
    final drivers = ((standings['drivers'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(PreseasonStandingsDriverPick.fromJson)
        .toList();
    final constructors = ((standings['constructors'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(PreseasonStandingsConstructorPick.fromJson)
        .toList();
    return PreseasonMine(
      seasonYear: (j['seasonYear'] as num).toInt(),
      isLocked: j['isLocked'] as bool,
      locksAt: j['locksAt'] == null ? null : DateTime.parse(j['locksAt'] as String).toLocal(),
      picks: picks,
      driverStandings: drivers,
      constructorStandings: constructors,
    );
  }
}
