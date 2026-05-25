import '../api/models/session_result.dart';

class ScoringRules {
  static const int exact = 8;
  static const int inTopN = 4;
  static const int miss = 0;
}

enum PickOutcome { exact, inTopN, miss }

PickOutcome outcomeFor(
  String pick,
  int slot,
  List<SessionResult> result,
  int topN,
) {
  final top = result.where((r) => r.position <= topN).toList();
  for (final r in top) {
    if (r.driverCode == pick) {
      return r.position == slot ? PickOutcome.exact : PickOutcome.inTopN;
    }
  }
  return PickOutcome.miss;
}

int _scoreOrdered(List<String> picks, List<SessionResult> result, int topN) {
  var total = 0;
  for (var i = 0; i < picks.length; i++) {
    final slot = i + 1;
    switch (outcomeFor(picks[i], slot, result, topN)) {
      case PickOutcome.exact:
        total += ScoringRules.exact;
      case PickOutcome.inTopN:
        total += ScoringRules.inTopN;
      case PickOutcome.miss:
        total += ScoringRules.miss;
    }
  }
  return total;
}

int scoreQualifying(List<String> picks, List<SessionResult> result) =>
    _scoreOrdered(picks, result, 2);

int scoreRace(List<String> picks, List<SessionResult> result) =>
    _scoreOrdered(picks, result, 5);

int scoreSprintQualifying(List<String> picks, List<SessionResult> result) =>
    _scoreOrdered(picks, result, 1);

int scoreSprint(List<String> picks, List<SessionResult> result) =>
    _scoreOrdered(picks, result, 3);
