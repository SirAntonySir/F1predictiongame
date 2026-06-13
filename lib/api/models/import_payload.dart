// Models around the league JSON import endpoint.
//
// The schema-download response is opaque JSON (we just save it to disk and
// hand it to the user/AI to fill in). The upload preview / apply response
// is structured so the UI can render the override warning + score preview.

class ImportMemberPreview {
  final String userId;
  final String displayName;
  const ImportMemberPreview({required this.userId, required this.displayName});

  factory ImportMemberPreview.fromJson(Map<String, dynamic> j) =>
      ImportMemberPreview(
        userId: j['userId'] as String,
        displayName: j['displayName'] as String,
      );
}

class ImportPlanItem {
  final String userId;
  final String displayName;
  final int sessionId;
  final String eventName;
  final int round;
  final String sessionType;
  final List<Map<String, dynamic>> picks;
  /// 'app' = will overwrite a user's in-app pick (warning state).
  /// 'import' = will replace a previously-imported row (silent).
  /// null = brand-new prediction.
  final String? conflictsWith;
  /// Points the picks would score against current results. Null when the
  /// session hasn't been resulted yet.
  final int? previewPoints;
  const ImportPlanItem({
    required this.userId,
    required this.displayName,
    required this.sessionId,
    required this.eventName,
    required this.round,
    required this.sessionType,
    required this.picks,
    required this.conflictsWith,
    required this.previewPoints,
  });

  factory ImportPlanItem.fromJson(Map<String, dynamic> j) => ImportPlanItem(
        userId: j['userId'] as String,
        displayName: j['displayName'] as String,
        sessionId: (j['sessionId'] as num).toInt(),
        eventName: j['eventName'] as String,
        round: (j['round'] as num).toInt(),
        sessionType: j['sessionType'] as String,
        picks: (j['picks'] as List).cast<Map<String, dynamic>>(),
        conflictsWith: j['conflictsWith'] as String?,
        previewPoints: (j['previewPoints'] as num?)?.toInt(),
      );
}

class ImportScoreEntry {
  final String userId;
  final String displayName;
  final int addedPoints;
  const ImportScoreEntry({
    required this.userId,
    required this.displayName,
    required this.addedPoints,
  });

  factory ImportScoreEntry.fromJson(Map<String, dynamic> j) => ImportScoreEntry(
        userId: j['userId'] as String,
        displayName: j['displayName'] as String,
        addedPoints: (j['addedPoints'] as num).toInt(),
      );
}

class ImportSkip {
  final String kind;
  final String? userId;
  final int? sessionId;
  final String? category;
  final String reason;
  const ImportSkip({
    required this.kind,
    this.userId,
    this.sessionId,
    this.category,
    required this.reason,
  });
  factory ImportSkip.fromJson(Map<String, dynamic> j) => ImportSkip(
        kind: j['kind'] as String,
        userId: j['userId'] as String?,
        sessionId: (j['sessionId'] as num?)?.toInt(),
        category: j['category'] as String?,
        reason: j['reason'] as String,
      );
}

class ImportApplyCounts {
  final int predictions;
  final int preseasonPicks;
  final int preseasonStandings;
  const ImportApplyCounts({
    required this.predictions,
    required this.preseasonPicks,
    required this.preseasonStandings,
  });
  factory ImportApplyCounts.fromJson(Map<String, dynamic> j) => ImportApplyCounts(
        predictions: (j['predictions'] as num).toInt(),
        preseasonPicks: (j['preseasonPicks'] as num).toInt(),
        preseasonStandings: (j['preseasonStandings'] as num).toInt(),
      );
}

/// Result of a `?dryRun=1` POST — preview without writes.
class ImportPreview {
  final int seasonYear;
  final List<ImportMemberPreview> members;
  final ImportApplyCounts applied;
  final List<ImportPlanItem> overwrites;
  final List<ImportPlanItem> plan;
  final List<ImportSkip> skipped;
  final List<ImportScoreEntry> scorePreview;
  const ImportPreview({
    required this.seasonYear,
    required this.members,
    required this.applied,
    required this.overwrites,
    required this.plan,
    required this.skipped,
    required this.scorePreview,
  });

  factory ImportPreview.fromJson(Map<String, dynamic> j) => ImportPreview(
        seasonYear: (j['season']['year'] as num).toInt(),
        members: (j['members'] as List)
            .cast<Map<String, dynamic>>()
            .map(ImportMemberPreview.fromJson)
            .toList(),
        applied: ImportApplyCounts.fromJson(j['applied'] as Map<String, dynamic>),
        overwrites: (j['overwrites'] as List)
            .cast<Map<String, dynamic>>()
            .map(ImportPlanItem.fromJson)
            .toList(),
        plan: (j['plan'] as List)
            .cast<Map<String, dynamic>>()
            .map(ImportPlanItem.fromJson)
            .toList(),
        skipped: (j['skipped'] as List)
            .cast<Map<String, dynamic>>()
            .map(ImportSkip.fromJson)
            .toList(),
        scorePreview: (j['scorePreview'] as List)
            .cast<Map<String, dynamic>>()
            .map(ImportScoreEntry.fromJson)
            .toList(),
      );
}

/// Result of a real (non-dryRun) apply.
class ImportApplyResult {
  final String importId;
  final ImportApplyCounts applied;
  final int overwriteCount;
  final List<ImportSkip> skipped;
  final int rescoredSessions;
  const ImportApplyResult({
    required this.importId,
    required this.applied,
    required this.overwriteCount,
    required this.skipped,
    required this.rescoredSessions,
  });

  factory ImportApplyResult.fromJson(Map<String, dynamic> j) => ImportApplyResult(
        importId: j['importId'] as String,
        applied: ImportApplyCounts.fromJson(j['applied'] as Map<String, dynamic>),
        overwriteCount: (j['overwriteCount'] as num).toInt(),
        skipped: (j['skipped'] as List)
            .cast<Map<String, dynamic>>()
            .map(ImportSkip.fromJson)
            .toList(),
        rescoredSessions: (j['rescored']?['sessions'] as num?)?.toInt() ?? 0,
      );
}
