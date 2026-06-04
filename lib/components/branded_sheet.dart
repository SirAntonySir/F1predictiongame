// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'big_pill.dart';

/// Presents [builder] as a house-style modal bottom sheet — surface stock,
/// rounded top, keyboard-aware — matching the app's other sheets. Returns
/// whatever value the sheet pops with.
Future<T?> showBrandedSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: builder,
  );
}

/// House-style bottom-sheet body: a drag handle, an Anton title, an optional
/// [content] slot, a primary [BigPill] action, and a muted secondary text
/// action. Pair with [showBrandedSheet]; for yes/no prompts use
/// [BrandedSheet.confirm].
class BrandedSheet extends StatelessWidget {
  final String title;
  final Widget? content;
  final String primaryLabel;
  /// Null disables/dims the primary pill.
  final VoidCallback? onPrimary;
  final String secondaryLabel;
  final VoidCallback onSecondary;

  const BrandedSheet({
    super.key,
    required this.title,
    this.content,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel = 'Cancel',
    required this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        // Ride above the keyboard when a field inside the sheet is focused.
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.sm, Spacing.lg, Spacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: Spacing.md),
                  decoration: BoxDecoration(
                    color: t.colorScheme.onSurface.withOpacity(0.2),
                    borderRadius: const BorderRadius.all(Radius.circular(999)),
                  ),
                ),
              ),
              Text(title, style: AppText.display(24, color: t.colorScheme.onSurface)),
              if (content != null) ...[
                const SizedBox(height: Spacing.md),
                content!,
              ],
              const SizedBox(height: Spacing.lg),
              BigPill(
                label: primaryLabel,
                background: BrandColors.accent,
                foreground: Colors.white,
                onTap: onPrimary,
              ),
              const SizedBox(height: Spacing.xxs),
              TextButton(
                onPressed: onSecondary,
                child: Text(
                  secondaryLabel,
                  style: AppText.label(12, color: t.colorScheme.onSurface.withOpacity(0.6)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Shows a yes/no confirmation as a bottom sheet. Returns true when the
  /// primary action is chosen, false otherwise (including dismissal).
  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    String? message,
    required String primaryLabel,
    String secondaryLabel = 'Cancel',
  }) async {
    final result = await showBrandedSheet<bool>(
      context,
      builder: (ctx) => BrandedSheet(
        title: title,
        content: message == null
            ? null
            : Text(
                message,
                style: AppText.body(13, color: Theme.of(ctx).colorScheme.onSurface.withOpacity(0.7)),
              ),
        primaryLabel: primaryLabel,
        onPrimary: () => Navigator.of(ctx).pop(true),
        secondaryLabel: secondaryLabel,
        onSecondary: () => Navigator.of(ctx).pop(false),
      ),
    );
    return result ?? false;
  }
}
