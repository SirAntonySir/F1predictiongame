// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// Full-width action button used across the app's auth / onboarding flows.
/// Mat-flat; dims when [onTap] is null instead of showing a Material disabled
/// grey wash. Optional [trailing] icon reinforces the "forward" direction
/// (e.g. arrow on a submit). Uses the app's canonical button radius
/// ([Radii.rLg]) so every generic button reads the same as the predict-screen
/// action bar.
class BigPill extends StatelessWidget {
  final String label;
  final IconData? trailing;
  final Color background;
  final Color foreground;
  final VoidCallback? onTap;
  const BigPill({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Opacity(
      opacity: disabled ? 0.55 : 1.0,
      child: Material(
        color: background,
        borderRadius: Radii.rLg,
        child: InkWell(
          onTap: onTap,
          borderRadius: Radii.rLg,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: Spacing.lg, vertical: Spacing.md),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label, style: AppText.label(13, color: foreground)),
                if (trailing != null) ...[
                  const SizedBox(width: 8),
                  Icon(trailing, size: 16, color: foreground),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
