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

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    return Scaffold(
      body: child,
      bottomNavigationBar: BottomNav(
        currentIndex: _indexFor(location),
        onTap: (i) async {
          final target = _paths[i];
          if (location.startsWith(target)) return;
          final guard = NavGuard.instance.canLeave;
          if (guard != null && !await guard()) return;
          if (context.mounted) context.go(target);
        },
      ),
    );
  }
}
