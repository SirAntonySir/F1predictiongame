import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/api_client.dart';
import 'package:predictiongame/api/models/event.dart';
import 'package:predictiongame/api/models/session.dart';
import 'package:predictiongame/api/models/live_snapshot.dart';
import 'package:predictiongame/state/live_session_controller.dart';

class _FakeApi implements ApiClient {
  int liveCalls = 0;
  int? lastId;
  String? lastLeague;
  LiveSnapshot reply = const LiveSnapshot(
      sessionId: 10,
      state: LiveState.live,
      order: [],
      myPointsTotal: 5,
      league: []);
  @override
  Future<LiveSnapshot> sessionLive(int id, {String? leagueId}) async {
    liveCalls += 1;
    lastId = id;
    lastLeague = leagueId;
    return reply;
  }

  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Session _s(int id, SessionType type, DateTime start, DateTime end,
        SessionStatus status) =>
    Session(
        id: id,
        type: type,
        scheduledStart: start,
        scheduledEnd: end,
        status: status);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime.utc(2026, 6, 7, 13, 30);
  Event ev(Session s) => Event(
      round: 1,
      name: 'A',
      country: 'X',
      circuitName: 'c',
      hasSprint: false,
      sessions: [s]);

  test('update() detects the live session and refreshOnce() fetches it',
      () async {
    final api = _FakeApi();
    final c = LiveSessionController(api: api);
    c.update([
      ev(_s(10, SessionType.race, now.subtract(const Duration(hours: 1)),
          now.add(const Duration(hours: 1)), SessionStatus.scheduled))
    ], now, leagueId: 'lg1', autoPoll: false);
    expect(c.liveSessionId, 10);
    await c.refreshOnce();
    expect(api.liveCalls, 1);
    expect(api.lastId, 10);
    expect(api.lastLeague, 'lg1');
    expect(c.snapshot?.myPointsTotal, 5);
    expect(c.isLiveFor(10), isTrue);
    expect(c.isLiveFor(99), isFalse);
    c.dispose();
  });

  test('onSessionFinalised fires exactly once when the snapshot finalises',
      () async {
    final api = _FakeApi();
    final c = LiveSessionController(api: api);
    var fired = 0;
    c.onSessionFinalised = () => fired++;
    c.update([
      ev(_s(10, SessionType.race, now.subtract(const Duration(hours: 1)),
          now.add(const Duration(hours: 1)), SessionStatus.scheduled))
    ], now, leagueId: null, autoPoll: false);

    // Still live → no announcement.
    await c.refreshOnce();
    expect(fired, 0);

    // Backend scores the session → announce once…
    api.reply = const LiveSnapshot(
        sessionId: 10,
        state: LiveState.finalised,
        order: [],
        myPointsTotal: 8,
        league: []);
    await c.refreshOnce();
    expect(fired, 1);

    // …and never again for the same session (manual re-poll).
    await c.refreshOnce();
    expect(fired, 1);
    c.dispose();
  });

  test('update() with no live session clears state', () async {
    final api = _FakeApi();
    final c = LiveSessionController(api: api);
    c.update([
      ev(_s(10, SessionType.race, now.add(const Duration(hours: 1)),
          now.add(const Duration(hours: 2)), SessionStatus.scheduled))
    ], now, leagueId: null, autoPoll: false);
    expect(c.liveSessionId, isNull);
    await c.refreshOnce();
    expect(api.liveCalls, 0);
    expect(c.snapshot, isNull);
    c.dispose();
  });
}
