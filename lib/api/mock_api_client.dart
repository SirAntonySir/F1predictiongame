import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart' show AssetBundle;
import 'api_client.dart';
import 'models/constructor.dart';
import 'models/driver.dart';
import 'models/event.dart';
import 'models/season.dart';
import 'models/session.dart';
import 'models/session_result.dart';
import 'models/standing.dart';

class MockApiClient implements ApiClient {
  final AssetBundle bundle;
  MockApiClient({required this.bundle});

  Future<dynamic> _read(String name) async {
    final s = await bundle.loadString('lib/mock/fixtures/$name');
    return jsonDecode(s);
  }

  @override
  Future<Season> currentSeason() async =>
      Season.fromJson(await _read('current_season.json') as Map<String, dynamic>);

  @override
  Future<List<Event>> events() async => ((await _read('events.json')) as List)
      .cast<Map<String, dynamic>>()
      .map(Event.fromJson)
      .toList();

  @override
  Future<Event> event(int round) async {
    final all = await events();
    return all.firstWhere(
      (e) => e.round == round,
      orElse: () => throw NotFoundException('event $round'),
    );
  }

  @override
  Future<Session> session(int id) async {
    final all = await events();
    for (final e in all) {
      for (final s in e.sessions) {
        if (s.id == id) return s;
      }
    }
    throw NotFoundException('session $id');
  }

  @override
  Future<List<SessionResult>> sessionResults(int id) async {
    try {
      final raw = await _read('session_${id}_results.json');
      return (raw as List)
          .cast<Map<String, dynamic>>()
          .map(SessionResult.fromJson)
          .toList();
    } catch (_) {
      throw NotFoundException('session $id results');
    }
  }

  @override
  Future<Session> nextSession() async =>
      Session.fromJson(await _read('next_session.json') as Map<String, dynamic>);

  @override
  Future<List<DriverStanding>> driverStandings() async =>
      ((await _read('driver_standings.json')) as List)
          .cast<Map<String, dynamic>>()
          .map(DriverStanding.fromJson)
          .toList();

  @override
  Future<List<ConstructorStanding>> constructorStandings() async =>
      ((await _read('constructor_standings.json')) as List)
          .cast<Map<String, dynamic>>()
          .map(ConstructorStanding.fromJson)
          .toList();

  @override
  Future<Driver> driver(String code) async {
    final results = await sessionResults(42);
    final r = results.firstWhere(
      (r) => r.driverCode == code,
      orElse: () => throw NotFoundException('driver $code'),
    );
    return Driver(
      code: r.driverCode,
      givenName: r.driverName.split(' ').first,
      familyName: r.driverName.split(' ').skip(1).join(' '),
      nationality: 'Unknown',
    );
  }

  @override
  Future<Constructor> constructor(String id) async {
    final standings = await constructorStandings();
    final c = standings.firstWhere(
      (s) => s.constructorId == id,
      orElse: () => throw NotFoundException('constructor $id'),
    );
    return Constructor(id: c.constructorId, name: c.constructorName, nationality: 'Unknown');
  }
}
