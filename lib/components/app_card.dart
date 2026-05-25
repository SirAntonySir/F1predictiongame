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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background ?? t.colorScheme.surface,
        borderRadius: Radii.rLg,
        border: Border.all(color: t.strokeColor, width: Strokes.card),
        boxShadow: elevated
            ? const [
                BoxShadow(
                  color: Colors.black,
                  offset: Offset(0, 6),
                  blurRadius: 0,
                )
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: Radii.rLg,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
