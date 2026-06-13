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
      padding: EdgeInsets.fromLTRB(filled ? 0 : 10, Spacing.sm, 10, Spacing.sm),
      decoration: BoxDecoration(
        border: Border.all(
          color: t.strokeColor,
          width: Strokes.subtle,
          style: filled ? BorderStyle.solid : BorderStyle.solid,
        ),
        borderRadius: const BorderRadius.all(Radius.circular(10)),
      ),
      // Match the empty-state row height when filled: empty state has no
      // stripe and no IconButton, so the row height is driven by the "P$n"
      // label + body text. We hold that line by giving the team stripe a
      // shorter height (20 instead of 32) and replacing the IconButton —
      // which forces a 48pt min touch target — with a tap-target-sized
      // InkWell that doesn't dictate row height.
      child: Row(
        children: [
          if (filled && constructorId != null)
            Container(width: 5, height: 20, color: teamColor(constructorId!)),
          if (filled) const SizedBox(width: Spacing.sm),
          Container(
            width: 32,
            padding: const EdgeInsets.only(left: 0),
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
            Text('#$number', style: AppText.label(11, color: t.colorScheme.onSurface.withOpacity(0.5))),
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
