import 'models/constructor.dart';
import 'models/driver.dart';
import 'models/event.dart';
import 'models/season.dart';
import 'models/session.dart';
import 'models/session_result.dart';
import 'models/standing.dart';

abstract class ApiClient {
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
}

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
