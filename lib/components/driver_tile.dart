// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/team_colors.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

class DriverTile extends StatelessWidget {
  final String code;
  final int? number;
  final String constructorId;
  final int? pickedSlot;
  final VoidCallback? onTap;
  /// Optional reference-session lap time (e.g. "1:18.234" from FP3, or
  /// "1:17.512 (Q1)" for a quali driver knocked out in Q1) shown under the
  /// driver code. Null → no time row.
  final String? lapTime;
  /// Optional 1-based position in the reference session. Rendered next to the
  /// stripe as the primary ranking cue. Hidden when null (e.g. season-opener
  /// fallback with no weekend reference).
  final int? position;
  const DriverTile({
    super.key,
    required this.code,
    required this.constructorId,
    this.number,
    this.pickedSlot,
    this.onTap,
    this.lapTime,
    this.position,
  });

  @override
  Widget build(BuildContext context) {
    final picked = pickedSlot != null;
    final t = Theme.of(context);
    // Use the brand accent (red) for the picked state instead of plain black —
    // black-on-dark-surface renders the picked tile invisible in dark mode,
    // and the accent matches LOCK PICK / PREDICT highlights elsewhere.
    final bg = picked ? BrandColors.accent : t.colorScheme.surface;
    final fg = picked ? Colors.white : t.colorScheme.onSurface;
    final muted = fg.withOpacity(0.65);
    return InkWell(
      onTap: onTap,
      borderRadius: const BorderRadius.all(Radius.circular(8)),
      child: Container(
        padding: const EdgeInsets.fromLTRB(0, 6, 8, 6),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: t.strokeColor, width: Strokes.subtle),
          borderRadius: const BorderRadius.all(Radius.circular(8)),
        ),
        child: Row(
          children: [
            // Team stripe.
            Container(width: 4, color: teamColor(constructorId)),
            const SizedBox(width: 6),
            // Position number (only when a reference session is in play).
            if (position != null) ...[
              SizedBox(
                width: 18,
                child: Text(
                  '$position',
                  textAlign: TextAlign.center,
                  style: AppText.display(15, color: fg),
                ),
              ),
              const SizedBox(width: 6),
            ],
            // Code + time stacked.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(code, style: AppText.display(13, color: fg)),
                      if (picked)
                        Text('P$pickedSlot',
                            style: AppText.display(10, color: fg)),
                    ],
                  ),
                  if (lapTime != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        lapTime!,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.fade,
                        style: AppText.label(9, color: muted),
                      ),
                    )
                  else if (number != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text('#$number',
                          style: AppText.label(8, color: muted)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
