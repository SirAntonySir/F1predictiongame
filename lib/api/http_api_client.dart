import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_client.dart';
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
import 'models/import_payload.dart';
import 'models/player_profile.dart';
import 'models/prediction_view.dart';
import 'models/preseason_mine.dart';
import 'models/reference_laps.dart';
import '../domain/preseason.dart';
import 'models/season.dart';
import 'models/session.dart';
import 'models/session_leaderboard_row.dart';
import 'models/live_snapshot.dart';
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

  String _seasonQ(int? season) => season == null ? '' : '?season=$season';

  // -------- existing read methods (refactored through _request) --------

  @override
  Future<Season> currentSeason() async =>
      Season.fromJson(await _request('GET', '/api/seasons/current') as Map<String, dynamic>);

  @override
  Future<List<Season>> seasons() async =>
      ((await _request('GET', '/api/seasons')) as List)
          .cast<Map<String, dynamic>>()
          .map(Season.fromJson)
          .toList();

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
  Future<ReferenceLapsResponse> sessionReferenceLaps(int id) async =>
      ReferenceLapsResponse.fromJson(
        await _request('GET', '/api/sessions/$id/reference-laps') as Map<String, dynamic>,
      );

  @override
  Future<LiveSnapshot> sessionLive(int id, {String? leagueId}) async {
    final q = leagueId == null ? '' : '?leagueId=$leagueId';
    final j = await _request('GET', '/api/sessions/$id/live$q');
    return LiveSnapshot.fromJson(j as Map<String, dynamic>);
  }

  @override
  Future<Session> nextSession() async =>
      Session.fromJson(await _request('GET', '/api/next-session') as Map<String, dynamic>);

  @override
  Future<List<DriverStanding>> driverStandings({int? season}) async =>
      ((await _request('GET', '/api/standings/drivers${_seasonQ(season)}')) as List)
          .cast<Map<String, dynamic>>()
          .map(DriverStanding.fromJson)
          .toList();

  @override
  Future<List<ConstructorStanding>> constructorStandings({int? season}) async =>
      ((await _request('GET', '/api/standings/constructors${_seasonQ(season)}')) as List)
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
  Future<void> changePassword({
    required String email,
    required String currentPassword,
    required String newPassword,
  }) async {
    await _request('POST', '/api/auth/change-password', body: {
      'email': email,
      'currentPassword': currentPassword,
      'newPassword': newPassword,
    });
  }

  @override
  Future<LeagueView> createLeague({required String name, String? password}) async {
    final body = <String, dynamic>{'name': name};
    if (password != null && password.isNotEmpty) body['password'] = password;
    final j = await _request('POST', '/api/leagues', body: body) as Map<String, dynamic>;
    return LeagueView.fromJson(j);
  }

  @override
  Future<LeagueView> joinLeague({required String code, String? password}) async {
    final body = <String, dynamic>{'joinCode': code};
    if (password != null && password.isNotEmpty) body['password'] = password;
    final j = await _request('POST', '/api/leagues/join', body: body) as Map<String, dynamic>;
    return LeagueView.fromJson(j);
  }

  @override
  Future<LeagueView> updateLeague(String id, {String? name, String? password}) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    // null → omit (leave unchanged). Empty string → null on backend (clear).
    if (password != null) body['password'] = password.isEmpty ? null : password;
    final j = await _request('PATCH', '/api/leagues/$id', body: body) as Map<String, dynamic>;
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
  Future<LeagueSessionPredictions> leagueSessionPredictions(String leagueId, int sessionId) async {
    final j = await _request(
      'GET',
      '/api/leagues/$leagueId/sessions/$sessionId/predictions',
    ) as Map<String, dynamic>;
    return LeagueSessionPredictions.fromJson(j);
  }

  @override
  Future<LeagueGossip> leagueGossip(String leagueId, {int? season}) async {
    final j = await _request('GET', '/api/leagues/$leagueId/gossip${_seasonQ(season)}')
        as Map<String, dynamic>;
    return LeagueGossip.fromJson(j);
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

  @override
  Future<LeaguePreseasonView> leaguePreseason(String leagueId, {int? season, String? asUserId}) async {
    final parts = <String>[];
    if (season != null) parts.add('season=$season');
    if (asUserId != null) parts.add('as=$asUserId');
    final q = parts.isEmpty ? '' : '?${parts.join('&')}';
    final j = await _request('GET', '/api/leagues/$leagueId/preseason$q') as Map<String, dynamic>;
    return LeaguePreseasonView.fromJson(j);
  }

  @override
  Future<Map<String, dynamic>> getImportSchema(String leagueId, int seasonYear) async {
    return await _request('GET', '/api/leagues/$leagueId/imports/schema?season=$seasonYear')
        as Map<String, dynamic>;
  }

  @override
  Future<ImportPreview> previewImport(String leagueId, Map<String, dynamic> body) async {
    final j = await _request('POST', '/api/leagues/$leagueId/imports?dryRun=1', body: body) as Map<String, dynamic>;
    return ImportPreview.fromJson(j);
  }

  @override
  Future<ImportApplyResult> applyImport(String leagueId, Map<String, dynamic> body) async {
    final j = await _request('POST', '/api/leagues/$leagueId/imports', body: body) as Map<String, dynamic>;
    return ImportApplyResult.fromJson(j);
  }

  @override
  Future<PlayerProfile> leaguePlayer(String leagueId, String userId, {int? season}) async {
    final q = season == null ? '' : '?season=$season';
    final j = await _request('GET', '/api/leagues/$leagueId/players/$userId$q')
        as Map<String, dynamic>;
    return PlayerProfile.fromJson(j);
  }

  @override
  Future<String?> circuitSvg(String circuitId, {String detail = 'detailed', String variant = 'white', String? layout}) async {
    final parts = <String>['detail=$detail', 'variant=$variant'];
    if (layout != null) parts.add('layout=$layout');
    final q = '?${parts.join('&')}';
    try {
      // Endpoint returns raw SVG, not JSON — talk to the http client directly
      // so we don't go through _request's JSON decoder.
      final headers = <String, String>{};
      final token = _tokenProvider();
      if (token != null) headers['Authorization'] = 'Bearer $token';
      final res = await client.get(
        Uri.parse('$baseUrl/api/circuits/$circuitId/svg$q'),
        headers: headers,
      );
      if (res.statusCode == 404) return null;
      if (res.statusCode >= 200 && res.statusCode < 300) return res.body;
      return null;
    } catch (_) {
      return null;
    }
  }
}
