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
    client = HttpApiClient(baseUrl: 'https://api.example.com', client: http_);
  });

  test('currentSeason maps a 200 response', () async {
    when(() => http_.get(any())).thenAnswer(
      (_) async => http.Response('{"year": 2026, "isCurrent": true}', 200),
    );
    final s = await client.currentSeason();
    expect(s.year, 2026);
  });

  test('throws NotFoundException on 404', () async {
    when(() => http_.get(any())).thenAnswer(
      (_) async => http.Response('{"error":{"code":"NOT_FOUND"}}', 404),
    );
    expect(client.session(99), throwsA(isA<NotFoundException>()));
  });

  test('throws UpstreamException on 500', () async {
    when(() => http_.get(any())).thenAnswer(
      (_) async => http.Response('boom', 500),
    );
    expect(client.events(), throwsA(isA<UpstreamException>()));
  });
}
