import 'models/auth_result.dart';
import 'models/constructor.dart';
import 'models/driver.dart';
import 'models/event.dart';
import 'models/leaderboard_row.dart';
import 'models/league_gossip.dart';
import 'models/league_preseason_view.dart';
import 'models/league_view.dart';
import 'models/member_prediction.dart';
import 'models/me_result.dart';
import 'models/my_score.dart';
import 'models/pick.dart';
import 'models/prediction_view.dart';
import 'models/preseason_mine.dart';
import '../domain/preseason.dart';
import 'models/season.dart';
import 'models/session.dart';
import 'models/reference_laps.dart';
import 'models/session_leaderboard_row.dart';
import 'models/session_result.dart';
import 'models/live_snapshot.dart';
import 'models/standing.dart';
import 'models/upcoming_prediction.dart';

abstract class ApiClient {
  // existing read methods
  Future<Season> currentSeason();
  Future<List<Season>> seasons();
  Future<List<Event>> events();
  Future<Event> event(int round);
  Future<Session> session(int id);
  Future<List<SessionResult>> sessionResults(int id);
  Future<ReferenceLapsResponse> sessionReferenceLaps(int id);
  Future<LiveSnapshot> sessionLive(int id, {String? leagueId});
  Future<Session> nextSession();
  Future<List<DriverStanding>> driverStandings({int? season});
  Future<List<ConstructorStanding>> constructorStandings({int? season});
  Future<Driver> driver(String code);
  Future<Constructor> constructor(String id);

  // auth
  Future<AuthResult> signup({required String email, required String password, required String displayName});
  Future<AuthResult> login({required String email, required String password});
  Future<MeResult>   me();
  Future<void>       logout();
  Future<void>       changePassword({
    required String email,
    required String currentPassword,
    required String newPassword,
  });

  // leagues
  Future<LeagueView> createLeague({required String name, String? password});
  Future<LeagueView> joinLeague({required String code, String? password});
  /// Owner-only. `password` semantics:
  /// - null  → leave unchanged
  /// - ''    → clear (league becomes open)
  /// - any  → set as the new password.
  Future<LeagueView> updateLeague(String id, {String? name, String? password});
  Future<LeagueView> getLeague(String id);

  // predictions
  Future<PredictionView?>          getMyPrediction(int sessionId);
  Future<PredictionView>           putMyPrediction(int sessionId, List<Pick> picks);
  Future<void>                     deleteMyPrediction(int sessionId);
  Future<List<UpcomingPrediction>> upcomingPredictions();

  // scores
  Future<List<MyScore>>            myScores({int? season});
  Future<List<LeaderboardRow>>     leagueLeaderboard(String leagueId, {int? season});
  Future<List<SessionLeaderboardRow>> leagueSessionBreakdown(String leagueId, {int? season});
  Future<LeagueSessionPredictions> leagueSessionPredictions(String leagueId, int sessionId);
  Future<LeagueGossip>             leagueGossip(String leagueId, {int? season});

  // preseason
  Future<PreseasonMine>            getPreseasonMine();
  Future<PreseasonSinglePick>      putPreseasonSinglePick(
    PreseasonCategory category, {
    String? driverCode,
    String? constructorId,
  });
  Future<void>                     deletePreseasonSinglePick(PreseasonCategory category);
  Future<List<PreseasonStandingsDriverPick>> putPreseasonDriverStandings(List<PreseasonStandingsDriverPick> picks);
  Future<List<PreseasonStandingsConstructorPick>> putPreseasonConstructorStandings(List<PreseasonStandingsConstructorPick> picks);
  Future<LeaguePreseasonView> leaguePreseason(String leagueId, {int? season});
}

// Exceptions
class NotFoundException implements Exception {
  final String resource;
  const NotFoundException(this.resource);
  @override
  String toString() => 'NotFoundException: $resource';
}

class UpstreamException implements Exception {
  final String message;
  const UpstreamException(this.message);
  @override
  String toString() => 'UpstreamException: $message';
}

class UnauthorizedException implements Exception {
  const UnauthorizedException();
  @override
  String toString() => 'UnauthorizedException';
}

class ForbiddenException implements Exception {
  final String message;
  const ForbiddenException(this.message);
  @override
  String toString() => 'ForbiddenException: $message';
}

class ConflictException implements Exception {
  final String message;
  const ConflictException(this.message);
  @override
  String toString() => 'ConflictException: $message';
}

class ValidationException implements Exception {
  final String message;
  const ValidationException(this.message);
  @override
  String toString() => 'ValidationException: $message';
}

class BadRequestException implements Exception {
  final String message;
  const BadRequestException(this.message);
  @override
  String toString() => 'BadRequestException: $message';
}
