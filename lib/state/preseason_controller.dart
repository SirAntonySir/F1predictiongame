import 'package:flutter/foundation.dart';
import '../api/api_client.dart';
import '../api/models/preseason_mine.dart';
import '../domain/preseason.dart';

/// Backend-backed cache for the caller's pre-season state (single-pick categories
/// + driver/constructor standings orderings). One-time load; mutations re-fetch.
class PreseasonController extends ChangeNotifier {
  PreseasonController({required this.api});
  final ApiClient api;

  PreseasonMine? _mine;
  Object? _lastError;
  bool _loading = false;

  PreseasonMine? get mine => _mine;
  bool get isLoaded => _mine != null;
  bool get isLocked => _mine?.isLocked ?? false;
  int? get seasonYear => _mine?.seasonYear;
  Object? get lastError => _lastError;

  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;
    try {
      _mine = await api.getPreseasonMine();
      _lastError = null;
    } catch (e) {
      _lastError = e;
    }
    _loading = false;
    notifyListeners();
  }

  PreseasonSinglePick pickFor(PreseasonCategory cat) =>
      _mine?.picks[cat] ?? const PreseasonSinglePick();

  List<String> driverOrdering() =>
      _mine?.driverStandings.map((p) => p.driverCode).toList() ?? const [];

  List<String> constructorOrdering() =>
      _mine?.constructorStandings.map((p) => p.constructorId).toList() ?? const [];

  Future<void> setSinglePick(
    PreseasonCategory cat, {
    String? driverCode,
    String? constructorId,
  }) async {
    // The backend rejects "both null" via its zod validator. If the caller wants
    // to clear the pick entirely they should call deleteSinglePick instead.
    if (driverCode == null && constructorId == null) {
      await deleteSinglePick(cat);
      return;
    }
    await api.putPreseasonSinglePick(cat,
        driverCode: driverCode, constructorId: constructorId);
    await refresh();
  }

  Future<void> deleteSinglePick(PreseasonCategory cat) async {
    await api.deletePreseasonSinglePick(cat);
    await refresh();
  }

  Future<void> setDriverOrdering(List<String> orderedDriverCodes) async {
    final picks = [
      for (var i = 0; i < orderedDriverCodes.length; i++)
        PreseasonStandingsDriverPick(position: i + 1, driverCode: orderedDriverCodes[i]),
    ];
    await api.putPreseasonDriverStandings(picks);
    await refresh();
  }

  Future<void> setConstructorOrdering(List<String> orderedConstructorIds) async {
    final picks = [
      for (var i = 0; i < orderedConstructorIds.length; i++)
        PreseasonStandingsConstructorPick(position: i + 1, constructorId: orderedConstructorIds[i]),
    ];
    await api.putPreseasonConstructorStandings(picks);
    await refresh();
  }

  void clear() {
    _mine = null;
    _lastError = null;
    notifyListeners();
  }
}
