import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? background;
  final bool elevated;
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Spacing.lg),
    this.background,
    this.elevated = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final card = Material(
      color: background ?? t.colorScheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: t.strokeColor, width: Strokes.card),
        borderRadius: Radii.rLg,
      ),
      child: Padding(padding: padding, child: child),
    );
    if (!elevated) return card;
    return Container(
      decoration: const BoxDecoration(
        boxShadow: [
          BoxShadow(color: Colors.black, offset: Offset(0, 6), blurRadius: 0),
        ],
      ),
      child: card,
    );
  }
}
