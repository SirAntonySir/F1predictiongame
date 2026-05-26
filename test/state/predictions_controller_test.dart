import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/api_client.dart';
import 'package:predictiongame/api/models/my_score.dart';
import 'package:predictiongame/api/models/pick.dart';
import 'package:predictiongame/api/models/prediction_view.dart';
import 'package:predictiongame/api/models/score_breakdown.dart';
import 'package:predictiongame/api/models/session.dart';
import 'package:predictiongame/api/models/upcoming_prediction.dart';
import 'package:predictiongame/state/predictions_controller.dart';

class _FakeApi implements ApiClient {
  int getCalls = 0;
  int putCalls = 0;
  int upcomingCalls = 0;
  int scoresCalls = 0;
  PredictionView? predReply;
  List<UpcomingPrediction> upcomingReply = const [];
  List<MyScore> scoresReply = const [];

  @override Future<PredictionView?> getMyPrediction(int sessionId) async { getCalls += 1; return predReply; }
  @override Future<PredictionView>  putMyPrediction(int sessionId, List<Pick> picks) async {
    putCalls += 1;
    return predReply = PredictionView(sessionId: sessionId, picks: picks, updatedAt: DateTime.utc(2026,5,1), isLocked: false);
  }
  @override Future<List<UpcomingPrediction>> upcomingPredictions() async { upcomingCalls += 1; return upcomingReply; }
  @override Future<List<MyScore>> myScores({int? season}) async { scoresCalls += 1; return scoresReply; }
  @override noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

MyScore _ms(int sessionId, int pts) => MyScore(
      sessionId: sessionId,
      sessionType: SessionType.race,
      eventRound: 1,
      eventName: 'Australian Grand Prix',
      sessionScheduledStart: DateTime.utc(2026, 3, 8),
      pointsTotal: pts,
      breakdown: const ScoreBreakdown(
        perPosition: [],
        teamBonus: ScoreTeamBonus(applied: false, points: 0),
        rule: 'race-v1',
      ),
      computedAt: DateTime.utc(2026, 5, 26),
    );

void main() {
  test('fetchPrediction caches the result; second call does not hit API', () async {
    final api = _FakeApi()..predReply = const PredictionView(sessionId: 1, picks: [], updatedAt: null, isLocked: false);
    final c = PredictionsController(api: api);
    await c.fetchPrediction(1);
    await c.fetchPrediction(1);
    expect(api.getCalls, 1);
    expect(c.prediction(1)!.sessionId, 1);
  });

  test('fetchPrediction null cached too (no re-fetch)', () async {
    final api = _FakeApi()..predReply = null;
    final c = PredictionsController(api: api);
    await c.fetchPrediction(7);
    await c.fetchPrediction(7);
    expect(api.getCalls, 1);
    expect(c.prediction(7), isNull);
    expect(c.hasFetched(7), isTrue);
  });

  test('savePrediction updates cache and notifies', () async {
    final api = _FakeApi();
    final c = PredictionsController(api: api);
    var notifies = 0;
    c.addListener(() => notifies += 1);
    await c.savePrediction(1, [const Pick(position: 1, driverCode: 'VER')]);
    expect(c.prediction(1)!.picks.first.driverCode, 'VER');
    expect(notifies, greaterThanOrEqualTo(1));
  });

  test('refreshUpcoming stores list and notifies', () async {
    final api = _FakeApi()..upcomingReply = [
      UpcomingPrediction(
        sessionId: 26, sessionType: SessionType.qualifying, eventId: 6, eventRound: 6,
        eventName: 'Monaco', eventCountry: 'MC', picksRequired: 2,
        locksAt: DateTime.utc(2026, 6, 6), isLocked: false, myPicks: null,
      ),
    ];
    final c = PredictionsController(api: api);
    await c.refreshUpcoming();
    expect(c.upcoming, hasLength(1));
  });

  test('refreshScores indexes by sessionId', () async {
    final api = _FakeApi()..scoresReply = [_ms(1, 15), _ms(2, 8)];
    final c = PredictionsController(api: api);
    await c.refreshScores();
    expect(c.score(1)!.pointsTotal, 15);
    expect(c.score(2)!.pointsTotal, 8);
  });

  test('clear empties everything', () async {
    final api = _FakeApi()
      ..predReply = const PredictionView(sessionId: 1, picks: [], updatedAt: null, isLocked: false)
      ..scoresReply = [_ms(1, 15)];
    final c = PredictionsController(api: api);
    await c.fetchPrediction(1);
    await c.refreshScores();
    c.clear();
    expect(c.prediction(1), isNull);
    expect(c.score(1), isNull);
    expect(c.upcoming, isEmpty);
    expect(c.hasFetched(1), isFalse);
  });
}
