// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/team_colors.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

class Slot extends StatelessWidget {
  final int position;
  final String? driverCode;
  final String? driverName;
  final int? number;
  final String? constructorId;
  final VoidCallback? onClear;
  const Slot({
    super.key,
    required this.position,
    this.driverCode,
    this.driverName,
    this.number,
    this.constructorId,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final filled = driverCode != null;
    final t = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: Spacing.sm, vertical: Spacing.xs),
      decoration: BoxDecoration(
        border: Border.all(color: t.strokeColor, width: Strokes.card),
        borderRadius: Radii.rLg,
      ),
      // Min height matches the DriverSectorRow + classification row anatomy so
      // empty/filled states don't pop.
      child: Row(
        children: [
          // Inset team-color bar (matches DriverSectorRow + classification row).
          Container(
            width: 5,
            height: 28,
            decoration: BoxDecoration(
              color: filled && constructorId != null
                  ? teamColor(constructorId!)
                  : t.colorScheme.onSurface.withOpacity(0.15),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: Spacing.sm),
          SizedBox(
            width: 36,
            child: Text('P$position', style: AppText.display(18)),
          ),
          Expanded(
            child: filled
                ? Text(driverName ?? '', style: AppText.body(14, weight: FontWeight.w700))
                : Text('Tap a driver below',
                    style: AppText.body(12, color: t.colorScheme.onSurface.withOpacity(0.35))
                        .copyWith(fontStyle: FontStyle.italic)),
          ),
          if (filled && number != null)
            Padding(
              padding: const EdgeInsets.only(right: Spacing.sm),
              child: Text('#$number',
                  style: AppText.label(11,
                      color: t.colorScheme.onSurface.withOpacity(0.5))),
            ),
          if (filled && onClear != null)
            InkWell(
              onTap: onClear,
              borderRadius: const BorderRadius.all(Radius.circular(999)),
              child: const Padding(
                padding: EdgeInsets.all(2),
                child: Icon(Icons.close, size: 16),
              ),
            ),
        ],
      ),
    );
  }
}
