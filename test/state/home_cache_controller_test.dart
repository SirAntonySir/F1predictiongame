import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/api_client.dart';
import 'package:predictiongame/api/models/event.dart';
import 'package:predictiongame/api/models/pick.dart';
import 'package:predictiongame/api/models/prediction_view.dart';
import 'package:predictiongame/api/models/session.dart';
import 'package:predictiongame/api/models/session_result.dart';
import 'package:predictiongame/api/models/upcoming_prediction.dart';
import 'package:predictiongame/state/auth_controller.dart';
import 'package:predictiongame/state/home_cache_controller.dart';
import 'package:predictiongame/state/predictions_controller.dart';
import 'package:predictiongame/state/token_storage.dart';

class _FakeApi implements ApiClient {
  List<Event> eventsReply = const [];
  List<SessionResult> resultsReply = const [];
  PredictionView? predReply;
  final List<int> getPredictionIds = [];

  @override
  Future<List<Event>> events() async => eventsReply;
  @override
  Future<Session> nextSession() async => throw const NotFoundException('next');
  @override
  Future<List<UpcomingPrediction>> upcomingPredictions() async => const [];
  @override
  Future<List<SessionResult>> sessionResults(int id) async => resultsReply;
  @override
  Future<PredictionView?> getMyPrediction(int sessionId) async {
    getPredictionIds.add(sessionId);
    return predReply;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Session _s(int id, SessionType type, String startIso,
        {SessionStatus status = SessionStatus.finished}) =>
    Session(
      id: id,
      type: type,
      scheduledStart: DateTime.parse(startIso),
      scheduledEnd: DateTime.parse(startIso),
      status: status,
    );

Event _ev(int round, String name, List<Session> sessions) => Event(
      round: round,
      name: name,
      country: name,
      circuitName: name,
      hasSprint: false,
      sessions: sessions,
    );

SessionResult _r(int pos, String code) => SessionResult(
      position: pos,
      driverCode: code,
      driverName: code,
      constructorId: 'x',
      constructorName: 'X',
    );

void main() {
  test('refresh() loads the last finished session\'s prediction into the cache '
      'so the card can show the score on first paint', () async {
    final api = _FakeApi()
      ..eventsReply = [
        _ev(6, 'Monaco Grand Prix', [
          _s(30, SessionType.race, '2026-06-07T13:00:00Z'),
        ]),
      ]
      ..resultsReply = [_r(1, 'VER'), _r(2, 'NOR')]
      ..predReply = const PredictionView(
        sessionId: 30,
        picks: [Pick(position: 1, driverCode: 'VER')],
        updatedAt: null,
        isLocked: true,
      );

    final preds = PredictionsController(api: api);
    final auth = AuthController(storage: InMemoryTokenStorage());
    final cache =
        HomeCacheController(api: api, auth: auth, predictions: preds);

    await cache.refresh();

    expect(api.getPredictionIds, contains(30),
        reason: 'home load should fetch the last session prediction');
    expect(preds.prediction(30), isNotNull);
    expect(preds.prediction(30)!.picks.first.driverCode, 'VER');
  });
}
