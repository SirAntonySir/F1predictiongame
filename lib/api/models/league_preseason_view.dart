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

class StandingsDriverPickView {
  final int position;
  final String driverCode;
  const StandingsDriverPickView({required this.position, required this.driverCode});
  factory StandingsDriverPickView.fromJson(Map<String, dynamic> j) =>
      StandingsDriverPickView(
        position: (j['position'] as num).toInt(),
        driverCode: j['driverCode'] as String,
      );
}

class StandingsConstructorPickView {
  final int position;
  final String constructorId;
  const StandingsConstructorPickView({required this.position, required this.constructorId});
  factory StandingsConstructorPickView.fromJson(Map<String, dynamic> j) =>
      StandingsConstructorPickView(
        position: (j['position'] as num).toInt(),
        constructorId: j['constructorId'] as String,
      );
}

class StandingsProjectionView {
  final List<StandingsDriverPickView> myDriverPicks;
  final List<StandingsConstructorPickView> myConstructorPicks;
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
            .map(StandingsDriverPickView.fromJson)
            .toList(),
        myConstructorPicks: ((j['myConstructorPicks'] as List).cast<Map<String, dynamic>>())
            .map(StandingsConstructorPickView.fromJson)
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
