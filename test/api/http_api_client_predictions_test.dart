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

  test('upcomingPredictions 200 returns list', () async {
    when(() => http_.get(any(), headers: any(named: 'headers'))).thenAnswer(
      (_) async => http.Response(jsonEncode({
        'upcoming': [
          {
            'session': {'id': 26, 'type': 'qualifying'},
            'event': {'id': 6, 'round': 6, 'name': 'Monaco Grand Prix', 'country': 'Monaco'},
            'picksRequired': 2,
            'locksAt': '2026-06-06T14:00:00.000Z',
            'isLocked': false,
            'myPicks': null,
          }
        ]
      }), 200),
    );
    final list = await client.upcomingPredictions();
    expect(list, hasLength(1));
    expect(list.first.eventName, 'Monaco Grand Prix');
  });
}
