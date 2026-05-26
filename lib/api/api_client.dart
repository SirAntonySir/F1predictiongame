import 'models/auth_result.dart';
import 'models/constructor.dart';
import 'models/driver.dart';
import 'models/event.dart';
import 'models/leaderboard_row.dart';
import 'models/league_view.dart';
import 'models/me_result.dart';
import 'models/my_score.dart';
import 'models/pick.dart';
import 'models/prediction_view.dart';
import 'models/season.dart';
import 'models/session.dart';
import 'models/session_result.dart';
import 'models/standing.dart';
import 'models/upcoming_prediction.dart';

abstract class ApiClient {
  // existing read methods
  Future<Season> currentSeason();
  Future<List<Event>> events();
  Future<Event> event(int round);
  Future<Session> session(int id);
  Future<List<SessionResult>> sessionResults(int id);
  Future<Session> nextSession();
  Future<List<DriverStanding>> driverStandings();
  Future<List<ConstructorStanding>> constructorStandings();
  Future<Driver> driver(String code);
  Future<Constructor> constructor(String id);

  // auth
  Future<AuthResult> signup({required String email, required String password, required String displayName});
  Future<AuthResult> login({required String email, required String password});
  Future<MeResult>   me();
  Future<void>       logout();

  // leagues (onboarding)
  Future<LeagueView> createLeague({required String name});
  Future<LeagueView> joinLeague({required String code});

  // predictions
  Future<PredictionView?>          getMyPrediction(int sessionId);
  Future<PredictionView>           putMyPrediction(int sessionId, List<Pick> picks);
  Future<void>                     deleteMyPrediction(int sessionId);
  Future<List<UpcomingPrediction>> upcomingPredictions();

  // scores
  Future<List<MyScore>>            myScores({int? season});
  Future<List<LeaderboardRow>>     leagueLeaderboard(String leagueId, {int? season});
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
