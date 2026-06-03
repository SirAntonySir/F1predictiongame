/// Lightweight singleton that lets the current screen veto navigation
/// triggered from outside its widget tree (e.g. the bottom-nav tab bar uses
/// `context.go(...)`, which bypasses `PopScope`).
///
/// Screens set [canLeave] in their `initState`/`didChangeDependencies` and
/// clear it in `dispose`. Callers (the shell, in practice) await the handler
/// before performing the navigation; if it returns `false`, navigation is
/// abandoned.
class NavGuard {
  NavGuard._();
  static final NavGuard instance = NavGuard._();

  Future<bool> Function()? canLeave;
}
