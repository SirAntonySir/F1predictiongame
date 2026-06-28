import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
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

  test('registerDevice POSTs token, platform and timezone', () async {
    Uri? sentUri;
    Object? sentBody;
    when(() => http_.post(any(), headers: any(named: 'headers'), body: any(named: 'body')))
        .thenAnswer((inv) async {
      sentUri = inv.positionalArguments[0] as Uri;
      sentBody = inv.namedArguments[#body];
      return http.Response('', 200);
    });

    await client.registerDevice(token: 'fcm-1', platform: 'ios', timezone: 'Europe/Vienna');

    expect(sentUri.toString(), 'https://api.example.com/api/devices');
    expect(jsonDecode(sentBody as String), {
      'token': 'fcm-1',
      'platform': 'ios',
      'timezone': 'Europe/Vienna',
    });
  });

  test('deleteDevice sends the token in the DELETE body', () async {
    Object? sentBody;
    when(() => http_.delete(any(), headers: any(named: 'headers'), body: any(named: 'body')))
        .thenAnswer((inv) async {
      sentBody = inv.namedArguments[#body];
      return http.Response('', 200);
    });

    await client.deleteDevice('fcm-bye');

    expect(jsonDecode(sentBody as String), {'token': 'fcm-bye'});
  });

  test('getNotificationPrefs parses the prefs envelope', () async {
    when(() => http_.get(any(), headers: any(named: 'headers'))).thenAnswer(
      (_) async => http.Response(
        jsonEncode({
          'prefs': {
            'enabled': false,
            'quietEnabled': true,
            'quietStartMin': 1380,
            'quietEndMin': 420,
            'timezone': 'America/New_York',
          }
        }),
        200,
      ),
    );

    final prefs = await client.getNotificationPrefs();
    expect(prefs.enabled, false);
    expect(prefs.quietEnabled, true);
    expect(prefs.quietStartMin, 1380);
    expect(prefs.quietEndMin, 420);
    expect(prefs.timezone, 'America/New_York');
  });

  test('putNotificationPrefs sends only provided fields and returns the result', () async {
    Object? sentBody;
    when(() => http_.put(any(), headers: any(named: 'headers'), body: any(named: 'body')))
        .thenAnswer((inv) async {
      sentBody = inv.namedArguments[#body];
      return http.Response(
        jsonEncode({
          'prefs': {'enabled': false, 'quietEnabled': false, 'quietStartMin': 1320, 'quietEndMin': 480}
        }),
        200,
      );
    });

    final prefs = await client.putNotificationPrefs(enabled: false);

    expect(jsonDecode(sentBody as String), {'enabled': false});
    expect(prefs.enabled, false);
  });
}
