// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/colors.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../big_pill.dart';
import 'podium_data.dart';
import 'results_podium.dart';

/// Shows the results podium as a temporary bottom-sheet modal. Dismiss via
/// drag-down, the top-right X, or the "Nice" button. When [onShowAll] is set,
/// a second "Show all" button dismisses the sheet and runs the callback
/// (typically opening the full session results).
Future<void> showResultsPodium(
  BuildContext context,
  PodiumData data, {
  VoidCallback? onShowAll,
}) {
  return showModalBottomSheet<void>(
    context: context,
    // Transparent here; the sheet paints its own surface from the BUILDER
    // context below. Reading the colour at the call site can resolve a
    // different brightness than the sheet's own subtree (e.g. a light call
    // context under a dark app), which showed a white sheet in dark mode.
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => _ResultsPodiumSheet(data: data, onShowAll: onShowAll),
  );
}

class _ResultsPodiumSheet extends StatelessWidget {
  final PodiumData data;
  final VoidCallback? onShowAll;
  const _ResultsPodiumSheet({required this.data, this.onShowAll});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: SafeArea(
        top: false,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Spacing.lg, Spacing.sm, Spacing.lg, Spacing.lg),
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
                        borderRadius:
                            const BorderRadius.all(Radius.circular(999)),
                      ),
                    ),
                  ),
                  Text('RESULTS ARE IN',
                      textAlign: TextAlign.center,
                      style: AppText.label(10, color: BrandColors.accent)),
                  const SizedBox(height: 3),
                  Text(data.eventName.toUpperCase(),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style:
                          AppText.display(22, color: t.colorScheme.onSurface)),
                  const SizedBox(height: 2),
                  Text('${data.sessionLabel} · Round ${data.round}',
                      textAlign: TextAlign.center,
                      style: AppText.body(12,
                          color: t.colorScheme.onSurface.withOpacity(0.55))),
                  const SizedBox(height: Spacing.sm),
                  ResultsPodium(data: data),
                  const SizedBox(height: Spacing.md),
                  BigPill(
                    label: 'NICE',
                    background: BrandColors.accent,
                    foreground: Colors.white,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  if (onShowAll != null) ...[
                    const SizedBox(height: Spacing.xs),
                    BigPill(
                      label: 'SHOW ALL',
                      background: Colors.transparent,
                      foreground: t.colorScheme.onSurface,
                      border: t.strokeColor,
                      onTap: () {
                        Navigator.of(context).pop();
                        onShowAll!();
                      },
                    ),
                  ],
                ],
              ),
            ),
            // Top-right dismiss.
            Positioned(
              top: Spacing.xs,
              right: Spacing.xs,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, size: 20),
                tooltip: 'Close',
                style: IconButton.styleFrom(
                  foregroundColor: t.colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
