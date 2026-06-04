import 'package:flutter/foundation.dart';

/// Generic stale-while-revalidate cache for a single async resource.
///
/// Used by screens that load a single payload (or a small composite struct)
/// from the API. Holds the last successful value, dedupes concurrent
/// refreshes, and notifies listeners on every state change so widgets can
/// repaint when fresh data lands.
///
/// State combinations a consumer needs to handle:
///   - data == null && refreshing      → first-load skeleton
///   - data == null && error  != null  → first-load error (showing retry)
///   - data != null && refreshing      → stale value + thin progress bar
///   - data != null                    → fresh value
///
/// Use [clear] on logout / dependency change to drop the cached value.
class AsyncCache<T> extends ChangeNotifier {
  AsyncCache(this._fetch);
  Future<T> Function() _fetch;

  T? _data;
  Object? _error;
  StackTrace? _stack;
  bool _refreshing = false;
  Future<void>? _inflight;

  T? get data => _data;
  Object? get error => _error;
  StackTrace? get stack => _stack;
  bool get refreshing => _refreshing;

  /// Swap the fetch closure (e.g. when a dependency like `auth.leagues`
  /// changes). Doesn't trigger a refresh — call [refresh] yourself.
  set fetch(Future<T> Function() value) => _fetch = value;

  /// Trigger a fresh fetch. Returns the in-flight future if one is already
  /// running so callers can `await` without starting a second load.
  Future<void> refresh() => _inflight ??= _doRefresh();

  Future<void> _doRefresh() async {
    _refreshing = true;
    notifyListeners();
    try {
      _data = await _fetch();
      _error = null;
      _stack = null;
    } catch (e, st) {
      _error = e;
      _stack = st;
      // Keep previous _data so a network blip doesn't blank the screen.
    } finally {
      _refreshing = false;
      _inflight = null;
      notifyListeners();
    }
  }

  void clear() {
    _data = null;
    _error = null;
    _stack = null;
    _refreshing = false;
    _inflight = null;
    notifyListeners();
  }
}
