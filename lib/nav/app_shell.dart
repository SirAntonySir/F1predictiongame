import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../components/bottom_nav.dart';
import 'nav_guard.dart';

class AppShell extends StatelessWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  static const _paths = ['/home', '/calendar', '/predict', '/standings'];

  int _indexFor(String location) {
    for (var i = 0; i < _paths.length; i++) {
      if (location.startsWith(_paths[i])) return i;
    }
    return 0;
  }

  Future<void> _goTo(BuildContext context, int i, String location) async {
    final target = _paths[i];
    if (location.startsWith(target)) return;
    final guard = NavGuard.instance.canLeave;
    if (guard != null && !await guard()) return;
    if (context.mounted) context.go(target);
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final currentIdx = _indexFor(location);
    return Scaffold(
      body: GestureDetector(
        // Horizontal flick switches bottom-nav tabs. Threshold of 250 px/s
        // mirrors the previous race-screen swipe — anything below feels
        // accidental and risks hijacking the inner vertical scroll.
        // HitTestBehavior.translucent so taps still reach the child while
        // the gesture arena resolves drags between this and any inner
        // horizontally-scrollable widgets (which win when present).
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: (details) {
          final v = details.primaryVelocity ?? 0;
          if (v.abs() < 250) return;
          final nextIdx = v < 0 ? currentIdx + 1 : currentIdx - 1;
          if (nextIdx < 0 || nextIdx >= _paths.length) return;
          // ignore: discarded_futures
          _goTo(context, nextIdx, location);
        },
        child: child,
      ),
      bottomNavigationBar: BottomNav(
        currentIndex: currentIdx,
        onTap: (i) => _goTo(context, i, location),
      ),
    );
  }
}
