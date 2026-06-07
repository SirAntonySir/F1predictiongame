import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:predictiongame/api/http_api_client.dart';
import 'package:predictiongame/api/models/live_snapshot.dart';

void main() {
  test('sessionLive GETs /live with leagueId and parses snapshot', () async {
    late Uri seen;
    final mock = MockClient((req) async {
      seen = req.url;
      return http.Response(
        '{"sessionId":5,"state":"live","asOf":"2026-06-07T13:30:00Z","order":[],"myProjected":{"pointsTotal":7},"leagueProjected":[]}',
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final api = HttpApiClient(
        baseUrl: 'https://x.test',
        tokenProvider: () => 'tok',
        onUnauthorized: () {},
        client: mock);
    final snap = await api.sessionLive(5, leagueId: 'lg1');
    expect(seen.path, '/api/sessions/5/live');
    expect(seen.queryParameters['leagueId'], 'lg1');
    expect(snap.state, LiveState.live);
    expect(snap.myPointsTotal, 7);
  });

  test('sessionLive without leagueId omits the query', () async {
    late Uri seen;
    final mock = MockClient((req) async {
      seen = req.url;
      return http.Response(
        '{"sessionId":5,"state":"pre","order":[],"myProjected":null,"leagueProjected":[]}',
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final api = HttpApiClient(
        baseUrl: 'https://x.test',
        tokenProvider: () => null,
        onUnauthorized: () {},
        client: mock);
    final snap = await api.sessionLive(5);
    expect(seen.query, isEmpty);
    expect(snap.state, LiveState.pre);
  });
}
