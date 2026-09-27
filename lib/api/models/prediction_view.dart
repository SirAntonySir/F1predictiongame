import 'pick.dart';

class PredictionView {
  final int sessionId;
  final List<Pick> picks;
  final DateTime? updatedAt;
  final bool isLocked;
  /// True when the picks were auto-copied from the previous race by a joker.
  final bool isJoker;

  const PredictionView({
    required this.sessionId,
    required this.picks,
    required this.updatedAt,
    required this.isLocked,
    this.isJoker = false,
  });

  factory PredictionView.fromJson(Map<String, dynamic> j) => PredictionView(
        sessionId: j['sessionId'] as int,
        picks: (j['picks'] as List).cast<Map<String, dynamic>>().map(Pick.fromJson).toList(),
        updatedAt: j['updatedAt'] == null ? null : DateTime.parse(j['updatedAt'] as String),
        isLocked: j['isLocked'] as bool,
        isJoker: j['isJoker'] as bool? ?? false,
      );
}
