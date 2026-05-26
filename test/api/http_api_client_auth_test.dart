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
  late List<String> unauthorizedFires;
  String? token;

  setUpAll(() {
    registerFallbackValue(Uri());
  });

  setUp(() {
    http_ = _MockHttp();
    unauthorizedFires = [];
    token = null;
    client = HttpApiClient(
      baseUrl: 'https://api.example.com',
      client: http_,
      tokenProvider: () => token,
      onUnauthorized: () => unauthorizedFires.add('hit'),
    );
  });

  group('signup', () {
    test('200 returns AuthResult', () async {
      when(() => http_.post(any(), headers: any(named: 'headers'), body: any(named: 'body'))).thenAnswer(
        (_) async => http.Response(jsonEncode({
          'user': {'id': 'u1', 'email': 'a@b.com', 'displayName': 'A', 'createdAt': '2026-05-01T00:00:00.000Z'},
          'token': 'tok',
        }), 200),
      );
      final r = await client.signup(email: 'a@b.com', password: 'hunter22x', displayName: 'A');
      expect(r.token, 'tok');
      expect(r.user.id, 'u1');
    });

    test('409 throws ConflictException with backend message', () async {
      when(() => http_.post(any(), headers: any(named: 'headers'), body: any(named: 'body'))).thenAnswer(
        (_) async => http.Response(jsonEncode({'error': {'code': 'CONFLICT', 'message': 'Email already registered'}}), 409),
      );
      try {
        await client.signup(email: 'a@b.com', password: 'hunter22x', displayName: 'A');
        fail('expected ConflictException');
      } on ConflictException catch (e) {
        expect(e.message, 'Email already registered');
      }
    });

    test('422 throws ValidationException with backend message', () async {
      when(() => http_.post(any(), headers: any(named: 'headers'), body: any(named: 'body'))).thenAnswer(
        (_) async => http.Response(jsonEncode({'error': {'code': 'VALIDATION', 'message': 'Password must be at least 8 characters'}}), 422),
      );
      try {
        await client.signup(email: 'a@b.com', password: 'short', displayName: 'A');
        fail('expected ValidationException');
      } on ValidationException catch (e) {
        expect(e.message, 'Password must be at least 8 characters');
      }
    });
  });

  group('login', () {
    test('200 returns AuthResult', () async {
      when(() => http_.post(any(), headers: any(named: 'headers'), body: any(named: 'body'))).thenAnswer(
        (_) async => http.Response(jsonEncode({
          'user': {'id': 'u1', 'email': 'a@b.com', 'displayName': 'A', 'createdAt': '2026-05-01T00:00:00.000Z'},
          'token': 'tok',
        }), 200),
      );
      final r = await client.login(email: 'a@b.com', password: 'hunter22x');
      expect(r.token, 'tok');
    });

    test('401 throws UnauthorizedException and fires onUnauthorized once', () async {
      when(() => http_.post(any(), headers: any(named: 'headers'), body: any(named: 'body'))).thenAnswer(
        (_) async => http.Response(jsonEncode({'error': {'code': 'UNAUTHORIZED', 'message': 'Invalid email or password'}}), 401),
      );
      expect(client.login(email: 'a@b.com', password: 'x'), throwsA(isA<UnauthorizedException>()));
      await Future<void>.delayed(Duration.zero);
      expect(unauthorizedFires, ['hit']);
    });

    test('attaches Authorization header when token present', () async {
      token = 'mytok';
      when(() => http_.get(any(), headers: any(named: 'headers'))).thenAnswer(
        (_) async => http.Response(jsonEncode({
          'user': {'id': 'u1', 'email': 'a@b.com', 'displayName': 'A', 'createdAt': '2026-05-01T00:00:00.000Z'},
          'leagues': [],
        }), 200),
      );
      await client.me();
      final captured = verify(() => http_.get(any(), headers: captureAny(named: 'headers'))).captured;
      final headers = captured.last as Map<String, String>;
      expect(headers['Authorization'], 'Bearer mytok');
    });

    test('does NOT attach Authorization when token null', () async {
      when(() => http_.get(any(), headers: any(named: 'headers'))).thenAnswer(
        (_) async => http.Response(jsonEncode({'year': 2026, 'isCurrent': true}), 200),
      );
      await client.currentSeason();
      final captured = verify(() => http_.get(any(), headers: captureAny(named: 'headers'))).captured;
      final headers = captured.last as Map<String, String>;
      expect(headers.containsKey('Authorization'), isFalse);
    });
  });

  group('me/logout', () {
    test('me returns MeResult', () async {
      when(() => http_.get(any(), headers: any(named: 'headers'))).thenAnswer(
        (_) async => http.Response(jsonEncode({
          'user': {'id': 'u1', 'email': 'a@b.com', 'displayName': 'A', 'createdAt': '2026-05-01T00:00:00.000Z'},
          'leagues': [{'id': 'L', 'name': 'My', 'role': 'owner'}],
        }), 200),
      );
      final r = await client.me();
      expect(r.user.id, 'u1');
      expect(r.leagues.first.role, 'owner');
    });

    test('logout 200 returns void', () async {
      when(() => http_.post(any(), headers: any(named: 'headers'), body: any(named: 'body'))).thenAnswer(
        (_) async => http.Response('{"ok": true}', 200),
      );
      await client.logout();
    });
  });
}
