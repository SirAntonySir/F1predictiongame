import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:predictiongame/api/api_client.dart';
import 'package:predictiongame/api/http_api_client.dart';
import 'package:predictiongame/api/models/pick.dart';

class _MockHttp extends Mock implements http.Client {}

void main() {
  late _MockHttp http_;
  late HttpApiClient client;
  setUpAll(() { registerFallbackValue(Uri()); });
  setUp(() {
    http_ = _MockHttp();
    client = HttpApiClient(
      baseUrl: 'https://api.example.com',
      client: http_,
      tokenProvider: () => 'tok',
      onUnauthorized: () {},
    );
  });

  test('getMyPrediction 200 returns PredictionView', () async {
    when(() => http_.get(any(), headers: any(named: 'headers'))).thenAnswer(
      (_) async => http.Response(jsonEncode({
        'prediction': {
          'sessionId': 42,
          'picks': [{'position': 1, 'driverCode': 'VER'}],
          'isLocked': false,
        }
      }), 200),
    );
    final v = await client.getMyPrediction(42);
    expect(v!.sessionId, 42);
    expect(v.picks.first.driverCode, 'VER');
  });

  test('getMyPrediction 404 returns null', () async {
    when(() => http_.get(any(), headers: any(named: 'headers'))).thenAnswer(
      (_) async => http.Response('{"error":{"code":"NOT_FOUND"}}', 404),
    );
    final v = await client.getMyPrediction(42);
    expect(v, isNull);
  });

  test('putMyPrediction 200 returns PredictionView', () async {
    when(() => http_.put(any(), headers: any(named: 'headers'), body: any(named: 'body'))).thenAnswer(
      (_) async => http.Response(jsonEncode({
        'prediction': {
          'sessionId': 42,
          'picks': [{'position': 1, 'driverCode': 'VER'}],
          'isLocked': false,
        }
      }), 200),
    );
    final v = await client.putMyPrediction(42, [const Pick(position: 1, driverCode: 'VER')]);
    expect(v.sessionId, 42);
  });

  test('putMyPrediction 409 → ConflictException', () async {
    when(() => http_.put(any(), headers: any(named: 'headers'), body: any(named: 'body'))).thenAnswer(
      (_) async => http.Response(jsonEncode({'error': {'message': 'Predictions for this session are locked'}}), 409),
    );
    expect(client.putMyPrediction(42, [const Pick(position: 1, driverCode: 'VER')]),
        throwsA(isA<ConflictException>()));
  });

  test('upcomingPredictions 200 returns bundle with joker state', () async {
    when(() => http_.get(any(), headers: any(named: 'headers'))).thenAnswer(
      (_) async => http.Response(jsonEncode({
        'upcoming': [
          {
            'session': {'id': 26, 'type': 'qualifying'},
            'event': {'id': 6, 'round': 6, 'name': 'Monaco Grand Prix', 'country': 'Monaco'},
            'picksRequired': 2,
            'locksAt': '2026-06-06T14:00:00.000Z',
            'isLocked': false,
            'isJoker': false,
            'myPicks': null,
          },
          {
            'session': {'id': 27, 'type': 'race'},
            'event': {'id': 6, 'round': 6, 'name': 'Monaco Grand Prix', 'country': 'Monaco'},
            'picksRequired': 5,
            'locksAt': '2026-06-07T14:00:00.000Z',
            'isLocked': true,
            'isJoker': true,
            'myPicks': [{'position': 1, 'driverCode': 'VER'}],
          }
        ],
        'jokersRemaining': 2,
      }), 200),
    );
    final bundle = await client.upcomingPredictions();
    expect(bundle.jokersRemaining, 2);
    expect(bundle.upcoming, hasLength(2));
    expect(bundle.upcoming.first.eventName, 'Monaco Grand Prix');
    expect(bundle.upcoming.first.isJoker, isFalse);
    expect(bundle.upcoming.last.isJoker, isTrue);
  });

  test('getMyPrediction parses isJoker', () async {
    when(() => http_.get(any(), headers: any(named: 'headers'))).thenAnswer(
      (_) async => http.Response(jsonEncode({
        'prediction': {
          'sessionId': 42,
          'picks': [{'position': 1, 'driverCode': 'VER'}],
          'isLocked': true,
          'isJoker': true,
        }
      }), 200),
    );
    final v = await client.getMyPrediction(42);
    expect(v!.isJoker, isTrue);
  });

  test('isJoker defaults to false when absent', () async {
    when(() => http_.get(any(), headers: any(named: 'headers'))).thenAnswer(
      (_) async => http.Response(jsonEncode({
        'prediction': {
          'sessionId': 42,
          'picks': [{'position': 1, 'driverCode': 'VER'}],
          'isLocked': false,
        }
      }), 200),
    );
    final v = await client.getMyPrediction(42);
    expect(v!.isJoker, isFalse);
  });
}
