import '../api/models/session_result.dart';

// Points are the backend's job (exact / wrong position / team bonus per
// session type, see backend/src/scoring). The client only classifies each
// pick for row tinting and ticks — it must never invent a points total.

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
