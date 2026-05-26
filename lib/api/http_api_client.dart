import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_client.dart';
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
import 'models/preseason_mine.dart';
import '../domain/preseason.dart';
import 'models/season.dart';
import 'models/session.dart';
import 'models/session_leaderboard_row.dart';
import 'models/session_result.dart';
import 'models/standing.dart';
import 'models/upcoming_prediction.dart';

typedef TokenProvider = String? Function();

class HttpApiClient implements ApiClient {
  final String baseUrl;
  final http.Client client;
  final TokenProvider _tokenProvider;
  final void Function() _onUnauthorized;
  bool _unauthorizedFired = false;

  HttpApiClient({
    required this.baseUrl,
    required TokenProvider tokenProvider,
    required void Function() onUnauthorized,
    http.Client? client,
  })  : client = client ?? http.Client(),
        _tokenProvider = tokenProvider,
        _onUnauthorized = onUnauthorized;

  Future<dynamic> _request(String method, String path, {Object? body}) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = <String, String>{};
    final token = _tokenProvider();
    if (token != null) headers['Authorization'] = 'Bearer $token';
    if (body != null) headers['Content-Type'] = 'application/json';
    final encoded = body == null ? null : jsonEncode(body);

    final http.Response res;
    switch (method) {
      case 'GET':    res = await client.get(uri, headers: headers); break;
      case 'POST':   res = await client.post(uri, headers: headers, body: encoded); break;
      case 'PUT':    res = await client.put(uri, headers: headers, body: encoded); break;
      case 'PATCH':  res = await client.patch(uri, headers: headers, body: encoded); break;
      case 'DELETE': res = await client.delete(uri, headers: headers); break;
      default:       throw StateError('Unsupported HTTP method: $method');
    }

    if (res.statusCode >= 200 && res.statusCode < 300) {
      _unauthorizedFired = false;
      if (res.body.isEmpty) return null;
      return jsonDecode(res.body);
    }

    final msg = _extractMessage(res.body);
    switch (res.statusCode) {
      case 400: throw BadRequestException(msg ?? 'Bad request');
      case 401:
        if (!_unauthorizedFired) {
          _unauthorizedFired = true;
          _onUnauthorized();
        }
        throw const UnauthorizedException();
      case 403: throw ForbiddenException(msg ?? 'Forbidden');
      case 404: throw NotFoundException(path);
      case 409: throw ConflictException(msg ?? 'Conflict');
      case 422: throw ValidationException(msg ?? 'Validation failed');
    }
    if (res.statusCode >= 500) throw UpstreamException('HTTP ${res.statusCode}');
    throw UpstreamException('HTTP ${res.statusCode}: ${res.body}');
  }

  String? _extractMessage(String body) {
    if (body.isEmpty) return null;
    try {
      final j = jsonDecode(body);
      final err = j is Map ? j['error'] : null;
      if (err is Map && err['message'] is String) return err['message'] as String;
    } catch (_) {/* ignore */}
    return null;
  }

  // -------- existing read methods (refactored through _request) --------

  @override
  Future<Season> currentSeason() async =>
      Season.fromJson(await _request('GET', '/api/seasons/current') as Map<String, dynamic>);

  @override
  Future<List<Event>> events() async => ((await _request('GET', '/api/events')) as List)
      .cast<Map<String, dynamic>>()
      .map(Event.fromJson)
      .toList();

  @override
  Future<Event> event(int round) async =>
      Event.fromJson(await _request('GET', '/api/events/$round') as Map<String, dynamic>);

  @override
  Future<Session> session(int id) async =>
      Session.fromJson(await _request('GET', '/api/sessions/$id') as Map<String, dynamic>);

  @override
  Future<List<SessionResult>> sessionResults(int id) async =>
      ((await _request('GET', '/api/sessions/$id/results')) as List)
          .cast<Map<String, dynamic>>()
          .map(SessionResult.fromJson)
          .toList();

  @override
  Future<Session> nextSession() async =>
      Session.fromJson(await _request('GET', '/api/next-session') as Map<String, dynamic>);

  @override
  Future<List<DriverStanding>> driverStandings() async =>
      ((await _request('GET', '/api/standings/drivers')) as List)
          .cast<Map<String, dynamic>>()
          .map(DriverStanding.fromJson)
          .toList();

  @override
  Future<List<ConstructorStanding>> constructorStandings() async =>
      ((await _request('GET', '/api/standings/constructors')) as List)
          .cast<Map<String, dynamic>>()
          .map(ConstructorStanding.fromJson)
          .toList();

  @override
  Future<Driver> driver(String code) async =>
      Driver.fromJson(await _request('GET', '/api/drivers/$code') as Map<String, dynamic>);

  @override
  Future<Constructor> constructor(String id) async => Constructor.fromJson(
      await _request('GET', '/api/constructors/$id') as Map<String, dynamic>);

  // -------- auth + leagues --------

  @override
  Future<AuthResult> signup({required String email, required String password, required String displayName}) async {
    final j = await _request('POST', '/api/auth/signup', body: {
      'email': email, 'password': password, 'displayName': displayName,
    }) as Map<String, dynamic>;
    return AuthResult.fromJson(j);
  }

  @override
  Future<AuthResult> login({required String email, required String password}) async {
    final j = await _request('POST', '/api/auth/login', body: {'email': email, 'password': password}) as Map<String, dynamic>;
    return AuthResult.fromJson(j);
  }

  @override
  Future<MeResult> me() async {
    final j = await _request('GET', '/api/auth/me') as Map<String, dynamic>;
    return MeResult.fromJson(j);
  }

  @override
  Future<void> logout() async {
    await _request('POST', '/api/auth/logout');
  }

  @override
  Future<LeagueView> createLeague({required String name}) async {
    final j = await _request('POST', '/api/leagues', body: {'name': name}) as Map<String, dynamic>;
    return LeagueView.fromJson(j);
  }

  @override
  Future<LeagueView> joinLeague({required String code}) async {
    final j = await _request('POST', '/api/leagues/join', body: {'joinCode': code}) as Map<String, dynamic>;
    return LeagueView.fromJson(j);
  }

  @override
  Future<LeagueView> getLeague(String id) async {
    final j = await _request('GET', '/api/leagues/$id') as Map<String, dynamic>;
    return LeagueView.fromJson(j);
  }

  @override
  Future<PredictionView?> getMyPrediction(int sessionId) async {
    try {
      final j = await _request('GET', '/api/sessions/$sessionId/my-prediction') as Map<String, dynamic>;
      return PredictionView.fromJson(j['prediction'] as Map<String, dynamic>);
    } on NotFoundException {
      return null;
    }
  }

  @override
  Future<PredictionView> putMyPrediction(int sessionId, List<Pick> picks) async {
    final j = await _request('PUT', '/api/sessions/$sessionId/my-prediction', body: {
      'picks': picks.map((p) => p.toJson()).toList(),
    }) as Map<String, dynamic>;
    return PredictionView.fromJson(j['prediction'] as Map<String, dynamic>);
  }

  @override
  Future<void> deleteMyPrediction(int sessionId) async {
    await _request('DELETE', '/api/sessions/$sessionId/my-prediction');
  }

  @override
  Future<List<UpcomingPrediction>> upcomingPredictions() async {
    final j = await _request('GET', '/api/predictions/upcoming') as Map<String, dynamic>;
    return (j['upcoming'] as List).cast<Map<String, dynamic>>().map(UpcomingPrediction.fromJson).toList();
  }

  @override
  Future<List<MyScore>> myScores({int? season}) async {
    final q = season == null ? '' : '?season=$season';
    final j = await _request('GET', '/api/users/me/scores$q') as Map<String, dynamic>;
    return (j['scores'] as List).cast<Map<String, dynamic>>().map(MyScore.fromJson).toList();
  }

  @override
  Future<List<LeaderboardRow>> leagueLeaderboard(String leagueId, {int? season}) async {
    final q = season == null ? '' : '?season=$season';
    final j = await _request('GET', '/api/leagues/$leagueId/leaderboard$q') as Map<String, dynamic>;
    return (j['leaderboard'] as List).cast<Map<String, dynamic>>().map(LeaderboardRow.fromJson).toList();
  }

  @override
  Future<List<SessionLeaderboardRow>> leagueSessionBreakdown(String leagueId, {int? season}) async {
    final q = season == null ? '' : '?season=$season';
    final j = await _request('GET', '/api/leagues/$leagueId/leaderboard/sessions$q') as Map<String, dynamic>;
    return (j['sessions'] as List).cast<Map<String, dynamic>>().map(SessionLeaderboardRow.fromJson).toList();
  }

  @override
  Future<PreseasonMine> getPreseasonMine() async {
    final j = await _request('GET', '/api/preseason/my') as Map<String, dynamic>;
    return PreseasonMine.fromJson(j);
  }

  @override
  Future<PreseasonSinglePick> putPreseasonSinglePick(
    PreseasonCategory category, {
    String? driverCode,
    String? constructorId,
  }) async {
    final body = <String, dynamic>{
      if (driverCode != null) 'driverCode': driverCode,
      if (constructorId != null) 'constructorId': constructorId,
    };
    final j = await _request('PUT', '/api/preseason/${category.name}', body: body) as Map<String, dynamic>;
    return PreseasonSinglePick.fromJson(j['pick'] as Map<String, dynamic>);
  }

  @override
  Future<void> deletePreseasonSinglePick(PreseasonCategory category) async {
    await _request('DELETE', '/api/preseason/${category.name}');
  }

  @override
  Future<List<PreseasonStandingsDriverPick>> putPreseasonDriverStandings(
      List<PreseasonStandingsDriverPick> picks) async {
    final j = await _request('PUT', '/api/preseason/standings/drivers',
        body: {'picks': picks.map((p) => p.toJson()).toList()}) as Map<String, dynamic>;
    return (j['picks'] as List).cast<Map<String, dynamic>>().map(PreseasonStandingsDriverPick.fromJson).toList();
  }

  @override
  Future<List<PreseasonStandingsConstructorPick>> putPreseasonConstructorStandings(
      List<PreseasonStandingsConstructorPick> picks) async {
    final j = await _request('PUT', '/api/preseason/standings/constructors',
        body: {'picks': picks.map((p) => p.toJson()).toList()}) as Map<String, dynamic>;
    return (j['picks'] as List).cast<Map<String, dynamic>>().map(PreseasonStandingsConstructorPick.fromJson).toList();
  }
}
