import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:predictiongame/api/api_client.dart';
import 'package:predictiongame/api/http_api_client.dart';

class _MockHttp extends Mock implements http.Client {}

void main() {
  late _MockHttp http_;
  late HttpApiClient client;

  setUpAll(() {
    registerFallbackValue(Uri());
  });

  setUp(() {
    http_ = _MockHttp();
    client = HttpApiClient(
      baseUrl: 'https://api.example.com',
      client: http_,
      tokenProvider: () => 'tok',
      onUnauthorized: () {},
    );
  });

  test('createLeague 200 returns LeagueView', () async {
    when(() => http_.post(any(), headers: any(named: 'headers'), body: any(named: 'body'))).thenAnswer(
      (_) async => http.Response(jsonEncode({
        'league': {'id': 'L', 'name': 'New', 'role': 'owner', 'joinCode': 'JJJJ22'},
        'members': [{'userId': 'u1', 'displayName': 'A', 'role': 'owner'}],
      }), 200),
    );
    final l = await client.createLeague(name: 'New');
    expect(l.joinCode, 'JJJJ22');
    expect(l.role, 'owner');
  });

  test('createLeague 409 → ConflictException', () async {
    when(() => http_.post(any(), headers: any(named: 'headers'), body: any(named: 'body'))).thenAnswer(
      (_) async => http.Response(jsonEncode({'error': {'code': 'CONFLICT', 'message': 'You already own a league'}}), 409),
    );
    expect(client.createLeague(name: 'New'), throwsA(isA<ConflictException>()));
  });

  test('joinLeague 200 returns LeagueView', () async {
    when(() => http_.post(any(), headers: any(named: 'headers'), body: any(named: 'body'))).thenAnswer(
      (_) async => http.Response(jsonEncode({
        'league': {'id': 'L', 'name': 'Eins', 'role': 'member'},
        'members': [],
      }), 200),
    );
    final l = await client.joinLeague(code: 'AAAAAA');
    expect(l.id, 'L');
    expect(l.role, 'member');
    expect(l.joinCode, isNull);
  });

  test('joinLeague 404 → NotFoundException', () async {
    when(() => http_.post(any(), headers: any(named: 'headers'), body: any(named: 'body'))).thenAnswer(
      (_) async => http.Response(jsonEncode({'error': {'code': 'NOT_FOUND', 'message': 'Unknown join code'}}), 404),
    );
    expect(client.joinLeague(code: 'NOPE99'), throwsA(isA<NotFoundException>()));
  });

  test('joinLeague 409 → ConflictException', () async {
    when(() => http_.post(any(), headers: any(named: 'headers'), body: any(named: 'body'))).thenAnswer(
      (_) async => http.Response(jsonEncode({'error': {'code': 'CONFLICT', 'message': 'Already a member'}}), 409),
    );
    expect(client.joinLeague(code: 'XXXXXX'), throwsA(isA<ConflictException>()));
  });
}
