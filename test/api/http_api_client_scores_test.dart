import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:predictiongame/api/http_api_client.dart';

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

  test('myScores 200 returns list', () async {
    when(() => http_.get(any(), headers: any(named: 'headers'))).thenAnswer(
      (_) async => http.Response(jsonEncode({
        'season': 2026,
        'scores': [
          {
            'sessionId': 1, 'sessionType': 'race', 'eventRound': 1,
            'eventName': 'Australian Grand Prix',
            'sessionScheduledStart': '2026-03-08T04:00:00.000Z',
            'pointsTotal': 15,
            'breakdown': {
              'perPosition': [{'position': 1, 'exact': true, 'wrongPos': false, 'points': 3}],
              'teamBonus': {'applied': false, 'points': 0},
              'rule': 'race-v1',
            },
            'computedAt': '2026-05-26T20:00:00.000Z',
          }
        ]
      }), 200),
    );
    final list = await client.myScores(season: 2026);
    expect(list, hasLength(1));
    expect(list.first.pointsTotal, 15);
    expect(list.first.eventName, 'Australian Grand Prix');
  });

  test('myScores attaches season query param', () async {
    when(() => http_.get(any(), headers: any(named: 'headers'))).thenAnswer(
      (_) async => http.Response(jsonEncode({'scores': [], 'season': 2025}), 200),
    );
    await client.myScores(season: 2025);
    final captured = verify(() => http_.get(captureAny(), headers: any(named: 'headers'))).captured;
    expect((captured.last as Uri).toString(), 'https://api.example.com/api/users/me/scores?season=2025');
  });
}
