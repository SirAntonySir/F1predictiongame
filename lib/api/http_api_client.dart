import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_client.dart';
import 'models/constructor.dart';
import 'models/driver.dart';
import 'models/event.dart';
import 'models/season.dart';
import 'models/session.dart';
import 'models/session_result.dart';
import 'models/standing.dart';

class HttpApiClient implements ApiClient {
  final String baseUrl;
  final http.Client client;
  HttpApiClient({required this.baseUrl, http.Client? client})
      : client = client ?? http.Client();

  Future<dynamic> _get(String path) async {
    final res = await client.get(Uri.parse('$baseUrl$path'));
    if (res.statusCode == 404) throw NotFoundException(path);
    if (res.statusCode >= 500) throw UpstreamException('HTTP ${res.statusCode}');
    if (res.statusCode >= 400) throw UpstreamException('HTTP ${res.statusCode}: ${res.body}');
    return jsonDecode(res.body);
  }

  @override
  Future<Season> currentSeason() async =>
      Season.fromJson(await _get('/api/seasons/current') as Map<String, dynamic>);

  @override
  Future<List<Event>> events() async => ((await _get('/api/events')) as List)
      .cast<Map<String, dynamic>>()
      .map(Event.fromJson)
      .toList();

  @override
  Future<Event> event(int round) async =>
      Event.fromJson(await _get('/api/events/$round') as Map<String, dynamic>);

  @override
  Future<Session> session(int id) async =>
      Session.fromJson(await _get('/api/sessions/$id') as Map<String, dynamic>);

  @override
  Future<List<SessionResult>> sessionResults(int id) async =>
      ((await _get('/api/sessions/$id/results')) as List)
          .cast<Map<String, dynamic>>()
          .map(SessionResult.fromJson)
          .toList();

  @override
  Future<Session> nextSession() async =>
      Session.fromJson(await _get('/api/next-session') as Map<String, dynamic>);

  @override
  Future<List<DriverStanding>> driverStandings() async =>
      ((await _get('/api/standings/drivers')) as List)
          .cast<Map<String, dynamic>>()
          .map(DriverStanding.fromJson)
          .toList();

  @override
  Future<List<ConstructorStanding>> constructorStandings() async =>
      ((await _get('/api/standings/constructors')) as List)
          .cast<Map<String, dynamic>>()
          .map(ConstructorStanding.fromJson)
          .toList();

  @override
  Future<Driver> driver(String code) async =>
      Driver.fromJson(await _get('/api/drivers/$code') as Map<String, dynamic>);

  @override
  Future<Constructor> constructor(String id) async => Constructor.fromJson(
      await _get('/api/constructors/$id') as Map<String, dynamic>);
}
