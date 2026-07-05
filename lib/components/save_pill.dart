import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// Header SAVE pill for draft-based editor screens (avatar, app icon):
/// filled accent while there's something to save, muted outline otherwise.
class SavePill extends StatelessWidget {
  final bool enabled;
  final VoidCallback onTap;
  const SavePill({super.key, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: Spacing.lg, vertical: Spacing.xs),
        decoration: BoxDecoration(
          color: enabled ? BrandColors.accent : null,
          border: enabled
              ? null
              : Border.all(color: t.strokeColor, width: Strokes.subtle),
          borderRadius: Radii.rSm,
        ),
        child: Text('SAVE',
            style: AppText.label(12,
                color: enabled
                    ? Colors.white
                    : t.colorScheme.onSurface.withValues(alpha: 0.35))),
      ),
    );
  }
}
