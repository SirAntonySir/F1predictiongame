import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../components/bottom_nav.dart';
import 'nav_guard.dart';

class AppShell extends StatelessWidget {
  final StatefulNavigationShell shell;
  const AppShell({super.key, required this.shell});

  static const _tabCount = 4;

  // Branch index of the predict tab — the only screen that registers a
  // NavGuard. Tab states are kept alive by the StatefulShellRoute, so the
  // guard stays registered even while other tabs are visible; consult it
  // only when the user is actually leaving predict, otherwise a dirty
  // predict tab would also gate e.g. Home → Calendar.
  static const _predictIndex = 2;

  Future<void> _goTo(BuildContext context, int i) async {
    if (i == shell.currentIndex) return;
    if (shell.currentIndex == _predictIndex) {
      final guard = NavGuard.instance.canLeave;
      if (guard != null && !await guard()) return;
    }
    if (context.mounted) shell.goBranch(i);
  }

  @override
  Widget build(BuildContext context) {
    final currentIdx = shell.currentIndex;
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
          if (nextIdx < 0 || nextIdx >= _tabCount) return;
          // ignore: discarded_futures
          _goTo(context, nextIdx);
        },
        child: shell,
      ),
      bottomNavigationBar: BottomNav(
        currentIndex: currentIdx,
        onTap: (i) => _goTo(context, i),
      ),
    );
  }
}
