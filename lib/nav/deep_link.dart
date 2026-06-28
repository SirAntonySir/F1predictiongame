import 'package:go_router/go_router.dart';

/// Bridges push-notification taps to navigation. The router is built inside the
/// widget tree ([F1PgApp]), but taps are handled from [PushService] wiring set
/// up at boot — so the router registers itself here once built, and tap
/// handlers call [handlePushRoute].
///
/// A route that arrives before the router exists (cold start: the app was
/// launched by tapping a push) is buffered and replayed on registration.
GoRouter? _router;
String? _pending;

void registerAppRouter(GoRouter router) {
  _router = router;
  final pending = _pending;
  _pending = null;
  if (pending != null) router.go(pending);
}

/// Navigate to [route] (e.g. `/race/9/45`). Auth gating is handled by the
/// router's own redirect, so a deep link while logged out lands on login.
void handlePushRoute(String route) {
  final router = _router;
  if (router == null) {
    _pending = route;
    return;
  }
  try {
    router.go(route);
  } catch (_) {
    // Malformed/unknown route — ignore rather than crash on a tap.
  }
}
