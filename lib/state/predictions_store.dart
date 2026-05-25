import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/prediction.dart';

class PredictionsStore extends ChangeNotifier {
  static const _key = 'predictions_v1';
  final Map<String, PredictionEntry> _entries;

  PredictionsStore(this._entries);

  static Future<PredictionsStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    final map = <String, PredictionEntry>{};
    if (raw != null) {
      final decoded = (jsonDecode(raw) as Map).cast<String, dynamic>();
      decoded.forEach((k, v) {
        map[k] = PredictionEntry.fromJson((v as Map).cast<String, dynamic>());
      });
    }
    return PredictionsStore(map);
  }

  String _k(String userId, int sessionId) => '$userId:$sessionId';

  List<String> picksFor({required String userId, required int sessionId}) =>
      _entries[_k(userId, sessionId)]?.picks ?? const [];

  bool isLocked({required String userId, required int sessionId}) =>
      _entries[_k(userId, sessionId)]?.isLocked ?? false;

  PredictionEntry? entryFor({required String userId, required int sessionId}) =>
      _entries[_k(userId, sessionId)];

  Future<void> save({
    required String userId,
    required int sessionId,
    required List<String> picks,
  }) async {
    final existing = _entries[_k(userId, sessionId)];
    if (existing?.isLocked == true) {
      throw StateError('Prediction is locked');
    }
    _entries[_k(userId, sessionId)] = PredictionEntry(
      sessionId: sessionId,
      userId: userId,
      picks: List.unmodifiable(picks),
    );
    await _persist();
    notifyListeners();
  }

  Future<void> lock({required String userId, required int sessionId}) async {
    final existing = _entries[_k(userId, sessionId)];
    if (existing == null) return;
    _entries[_k(userId, sessionId)] =
        existing.copyWith(lockedAt: DateTime.now().toUtc());
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(
      _entries.map((k, v) => MapEntry(k, v.toJson())),
    );
    await prefs.setString(_key, encoded);
  }
}
