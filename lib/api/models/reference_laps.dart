import 'session.dart' show SessionType;

enum SectorTier { sessionBest, personalBest, neutral }

SectorTier _tierFrom(String? s) => switch (s) {
      'sessionBest' => SectorTier.sessionBest,
      'personalBest' => SectorTier.personalBest,
      _ => SectorTier.neutral,
    };

class ReferenceLap {
  final String driverCode;
  final int lapMs;
  final SectorTier lapTier;
  final int? s1Ms;
  final SectorTier s1Tier;
  final int? s2Ms;
  final SectorTier s2Tier;
  final int? s3Ms;
  final SectorTier s3Tier;
  final int? lapNumber;

  const ReferenceLap({
    required this.driverCode,
    required this.lapMs,
    required this.lapTier,
    required this.s1Ms,
    required this.s1Tier,
    required this.s2Ms,
    required this.s2Tier,
    required this.s3Ms,
    required this.s3Tier,
    required this.lapNumber,
  });

  factory ReferenceLap.fromJson(Map<String, dynamic> j) => ReferenceLap(
        driverCode: j['driverCode'] as String,
        lapMs: (j['lapMs'] as num).toInt(),
        lapTier: _tierFrom(j['lapTier'] as String?),
        s1Ms: (j['s1Ms'] as num?)?.toInt(),
        s1Tier: _tierFrom(j['s1Tier'] as String?),
        s2Ms: (j['s2Ms'] as num?)?.toInt(),
        s2Tier: _tierFrom(j['s2Tier'] as String?),
        s3Ms: (j['s3Ms'] as num?)?.toInt(),
        s3Tier: _tierFrom(j['s3Tier'] as String?),
        lapNumber: (j['lapNumber'] as num?)?.toInt(),
      );
}

class ReferenceSessionLaps {
  final int sessionId;
  final SessionType type;
  final String label;
  final List<ReferenceLap> laps;
  const ReferenceSessionLaps({
    required this.sessionId,
    required this.type,
    required this.label,
    required this.laps,
  });

  factory ReferenceSessionLaps.fromJson(Map<String, dynamic> j) =>
      ReferenceSessionLaps(
        sessionId: (j['sessionId'] as num).toInt(),
        type: SessionType.values.firstWhere(
          (t) => t.name == j['type'],
          orElse: () => SessionType.race,
        ),
        label: j['label'] as String,
        laps: (j['laps'] as List)
            .cast<Map<String, dynamic>>()
            .map(ReferenceLap.fromJson)
            .toList(growable: false),
      );
}

class ReferenceLapsResponse {
  final int predictSessionId;
  final SessionType predictSessionType;
  final List<ReferenceSessionLaps> references;
  const ReferenceLapsResponse({
    required this.predictSessionId,
    required this.predictSessionType,
    required this.references,
  });

  factory ReferenceLapsResponse.fromJson(Map<String, dynamic> j) =>
      ReferenceLapsResponse(
        predictSessionId: (j['predictSessionId'] as num).toInt(),
        predictSessionType: SessionType.values.firstWhere(
          (t) => t.name == j['predictSessionType'],
          orElse: () => SessionType.race,
        ),
        references: (j['references'] as List)
            .cast<Map<String, dynamic>>()
            .map(ReferenceSessionLaps.fromJson)
            .toList(growable: false),
      );

  /// Flatten into driver → ordered list of (session, lap?) so a row can render
  /// 3 fixed groups left-to-right. Missing data stays null.
  Map<String, List<ReferenceLap?>> get byDriver {
    final out = <String, List<ReferenceLap?>>{};
    for (final ref in references) {
      for (final l in ref.laps) {
        final list = out.putIfAbsent(driverCode(l), () => List.filled(references.length, null));
        final idx = references.indexOf(ref);
        list[idx] = l;
      }
    }
    return out;
  }

  String driverCode(ReferenceLap l) => l.driverCode;
}
