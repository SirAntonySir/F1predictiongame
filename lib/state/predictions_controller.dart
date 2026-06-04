import 'package:flutter/foundation.dart';
import '../api/api_client.dart';
import '../api/models/my_score.dart';
import '../api/models/pick.dart';
import '../api/models/prediction_view.dart';
import '../api/models/upcoming_prediction.dart';

class PredictionsController extends ChangeNotifier {
  PredictionsController({
    required this.api,
    this.onUpcomingSynced,
    this.onPredictionSaved,
  });
  final ApiClient api;
  /// Fires after [refreshUpcoming] succeeds. Used by ReminderService to
  /// reschedule pick-reminders for unpicked sessions.
  final void Function(List<UpcomingPrediction> upcoming)? onUpcomingSynced;
  /// Fires after [savePrediction] succeeds. Used by ReminderService to cancel
  /// any pending reminders for the just-picked session.
  final void Function(int sessionId)? onPredictionSaved;

  final Map<int, PredictionView?> _predictions = {};
  final Set<int> _fetched = {};
  final Map<int, MyScore> _scores = {};
  List<UpcomingPrediction> _upcoming = const [];

  PredictionView?           prediction(int sessionId) => _predictions[sessionId];
  bool                      hasFetched(int sessionId) => _fetched.contains(sessionId);
  MyScore?                  score(int sessionId)      => _scores[sessionId];
  List<UpcomingPrediction>  get upcoming              => _upcoming;
  Iterable<int>             get allScoreIds           => _scores.keys;

  Future<PredictionView?> fetchPrediction(int sessionId) async {
    if (_fetched.contains(sessionId)) return _predictions[sessionId];
    final v = await api.getMyPrediction(sessionId);
    _predictions[sessionId] = v;
    _fetched.add(sessionId);
    notifyListeners();
    return v;
  }

  Future<PredictionView> savePrediction(int sessionId, List<Pick> picks) async {
    final v = await api.putMyPrediction(sessionId, picks);
    _predictions[sessionId] = v;
    _fetched.add(sessionId);
    notifyListeners();
    onPredictionSaved?.call(sessionId);
    return v;
  }

  Future<void> refreshUpcoming() async {
    _upcoming = await api.upcomingPredictions();
    notifyListeners();
    onUpcomingSynced?.call(_upcoming);
  }

  Future<void> refreshScores({int? season}) async {
    final list = await api.myScores(season: season);
    _scores
      ..clear()
      ..addEntries(list.map((s) => MapEntry(s.sessionId, s)));
    notifyListeners();
  }

  void clear() {
    _predictions.clear();
    _fetched.clear();
    _scores.clear();
    _upcoming = const [];
    notifyListeners();
    // Cancel any pending reminders on logout — they'd otherwise fire under the
    // new user's account or after the app is wiped.
    onUpcomingSynced?.call(const []);
  }
}
