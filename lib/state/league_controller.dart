import 'package:flutter/foundation.dart';
import '../api/api_client.dart';
import '../api/models/league_view.dart';

/// Holds the currently-active league (members, name, joinCode) fetched from
/// the backend. Loaded once after auth bootstrap; reloaded on demand.
class LeagueController extends ChangeNotifier {
  LeagueController({required this.api});
  final ApiClient api;

  LeagueView? _league;
  Object? _lastError;

  LeagueView? get league => _league;
  Object? get lastError => _lastError;
  bool get hasLeague => _league != null;

  Future<void> load(String leagueId) async {
    try {
      _league = await api.getLeague(leagueId);
      _lastError = null;
    } catch (e) {
      _lastError = e;
    }
    notifyListeners();
  }

  void clear() {
    _league = null;
    _lastError = null;
    notifyListeners();
  }
}
