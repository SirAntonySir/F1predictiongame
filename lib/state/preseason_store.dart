import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/preseason.dart';

class PreseasonStore extends ChangeNotifier {
  static const _key = 'preseason_v1';
  final Map<String, _Entry> _entries;
  PreseasonStore(this._entries);

  static String _k(String userId, int seasonYear) =>
      '$userId:$seasonYear';

  static Future<PreseasonStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    final map = <String, _Entry>{};
    if (raw != null) {
      final decoded = (jsonDecode(raw) as Map).cast<String, dynamic>();
      decoded.forEach((k, v) {
        map[k] = _Entry.fromJson((v as Map).cast<String, dynamic>());
      });
    }
    return PreseasonStore(map);
  }

  _Entry _for(String userId, int seasonYear) =>
      _entries.putIfAbsent(_k(userId, seasonYear), () => _Entry.empty());

  PreseasonPick pickFor({
    required String userId,
    required int seasonYear,
    required PreseasonCategory category,
  }) =>
      _for(userId, seasonYear).picks[category] ?? const PreseasonPick();

  List<String> driverOrdering({
    required String userId,
    required int seasonYear,
  }) =>
      List.unmodifiable(_for(userId, seasonYear).drivers);

  List<String> constructorOrdering({
    required String userId,
    required int seasonYear,
  }) =>
      List.unmodifiable(_for(userId, seasonYear).constructors);

  Future<void> setSinglePick({
    required String userId,
    required int seasonYear,
    required PreseasonCategory category,
    String? driverCode,
    String? constructorId,
  }) async {
    final entry = _for(userId, seasonYear);
    entry.picks[category] = PreseasonPick(
      driverCode: driverCode,
      constructorId: constructorId,
    );
    await _persist();
    notifyListeners();
  }

  Future<void> setDriverOrdering({
    required String userId,
    required int seasonYear,
    required List<String> ordering,
  }) async {
    _for(userId, seasonYear).drivers
      ..clear()
      ..addAll(ordering);
    await _persist();
    notifyListeners();
  }

  Future<void> setConstructorOrdering({
    required String userId,
    required int seasonYear,
    required List<String> ordering,
  }) async {
    _for(userId, seasonYear).constructors
      ..clear()
      ..addAll(ordering);
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(_entries.map((k, v) => MapEntry(k, v.toJson()))),
    );
  }
}

class _Entry {
  final Map<PreseasonCategory, PreseasonPick> picks;
  final List<String> drivers;
  final List<String> constructors;

  _Entry({
    required this.picks,
    required this.drivers,
    required this.constructors,
  });

  factory _Entry.empty() => _Entry(
        picks: {},
        drivers: [],
        constructors: [],
      );

  Map<String, dynamic> toJson() => {
        'picks': picks.map((k, v) => MapEntry(k.name, v.toJson())),
        'drivers': drivers,
        'constructors': constructors,
      };

  factory _Entry.fromJson(Map<String, dynamic> j) {
    final picksJson =
        ((j['picks'] as Map?) ?? const {}).cast<String, dynamic>();
    final picks = <PreseasonCategory, PreseasonPick>{};
    picksJson.forEach((k, v) {
      try {
        final cat = PreseasonCategory.values.byName(k);
        picks[cat] =
            PreseasonPick.fromJson((v as Map).cast<String, dynamic>());
      } catch (_) {}
    });
    return _Entry(
      picks: picks,
      drivers: ((j['drivers'] as List?) ?? const []).cast<String>().toList(),
      constructors:
          ((j['constructors'] as List?) ?? const []).cast<String>().toList(),
    );
  }
}
