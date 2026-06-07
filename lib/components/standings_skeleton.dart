// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:skeletonizer/skeletonizer.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'app_card.dart';

/// Branded loading skeleton for the standings-style list tabs (F1 drivers /
/// constructors, preseason). Renders [rows] placeholder rows inside the same
/// AppCard frame the real lists use; the global Skeletonizer pulse config
/// turns them into bones.
class StandingsListSkeleton extends StatelessWidget {
  final int rows;
  const StandingsListSkeleton({super.key, this.rows = 10});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Skeletonizer(
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: Spacing.md),
        children: [
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: List.generate(
                rows,
                (i) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 10),
                  child: Row(
                    children: [
                      SizedBox(width: 24, child: Text('${i + 1}', style: AppText.display(16))),
                      Container(width: 4, height: 22, color: t.colorScheme.onSurface),
                      const SizedBox(width: 10),
                      SizedBox(width: 44, child: Text('VER', style: AppText.body(13, weight: FontWeight.w800))),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Driver Name', style: AppText.body(13, weight: FontWeight.w600)),
                            Text('0 wins', style: AppText.body(10, color: t.colorScheme.onSurface.withOpacity(0.5))),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 42,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('000', style: AppText.display(18)),
                            Text('pts', style: AppText.label(8, color: t.colorScheme.onSurface.withOpacity(0.6))),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
