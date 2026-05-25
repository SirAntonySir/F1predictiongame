import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/api_client.dart';
import 'package:predictiongame/api/mock_api_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final client = MockApiClient(bundle: rootBundle);

  test('currentSeason returns the year', () async {
    final s = await client.currentSeason();
    expect(s.year, greaterThan(2020));
    expect(s.isCurrent, true);
  });

  test('events returns the calendar', () async {
    final events = await client.events();
    expect(events, isNotEmpty);
    expect(events.first.round, 1);
  });

  test('nextSession returns one Session', () async {
    final s = await client.nextSession();
    expect(s.id, isPositive);
  });

  test('sessionResults returns ordered results', () async {
    final r = await client.sessionResults(42);
    expect(r, isNotEmpty);
    expect(r.first.position, 1);
  });

  test('driverStandings returns ordered standings', () async {
    final ds = await client.driverStandings();
    expect(ds, isNotEmpty);
    expect(ds.first.position, 1);
  });

  test('sessionResults throws NotFoundException for unknown session', () async {
    expect(() => client.sessionResults(99999), throwsA(isA<NotFoundException>()));
  });
}
