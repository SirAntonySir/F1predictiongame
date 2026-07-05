import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Remembers which scored sessions have already had their results podium
/// celebrated, so a given session only pops the podium once. Backed by
/// SharedPreferences (a JSON list of session ids under [_key]).
///
/// The prefs accessor is injectable so tests can supply a mocked instance.
class SeenResultsStore {
  static const _key = 'seen_scored_sessions';

  final Future<SharedPreferences> Function() _prefs;
  SeenResultsStore({Future<SharedPreferences> Function()? prefs})
      : _prefs = prefs ?? SharedPreferences.getInstance;

  /// The set of session ids already celebrated. Never throws — a prefs/decode
  /// failure degrades to an empty set (worst case: a podium re-shows once).
  Future<Set<int>> load() async {
    try {
      final raw = (await _prefs()).getString(_key);
      if (raw == null || raw.isEmpty) return <int>{};
      return (jsonDecode(raw) as List).map((n) => (n as num).toInt()).toSet();
    } catch (_) {
      return <int>{};
    }
  }

  /// Unions [ids] into the seen set and persists it. Best-effort.
  Future<void> markSeen(Iterable<int> ids) async {
    if (ids.isEmpty) return;
    try {
      final prefs = await _prefs();
      final current = await load()..addAll(ids);
      await prefs.setString(_key, jsonEncode(current.toList()));
    } catch (_) {
      // Non-fatal — the podium simply isn't suppressed next launch.
    }
  }
}
