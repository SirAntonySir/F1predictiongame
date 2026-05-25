// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/team_colors.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

class DriverTile extends StatelessWidget {
  final String code;
  final int? number;
  final String constructorId;
  final int? pickedSlot;
  final VoidCallback? onTap;
  const DriverTile({
    super.key,
    required this.code,
    required this.constructorId,
    this.number,
    this.pickedSlot,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final picked = pickedSlot != null;
    final t = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: const BorderRadius.all(Radius.circular(8)),
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 5),
        decoration: BoxDecoration(
          color: picked ? Colors.black : t.colorScheme.surface,
          border: Border.all(color: t.strokeColor, width: Strokes.subtle),
          borderRadius: const BorderRadius.all(Radius.circular(8)),
        ),
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(width: 4, color: teamColor(constructorId)),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(code,
                      style: AppText.display(13, color: picked ? Colors.white : t.colorScheme.onSurface)),
                  if (number != null)
                    Text('#$number',
                        style: AppText.label(8, color: (picked ? Colors.white : t.colorScheme.onSurface).withOpacity(0.55))),
                ],
              ),
            ),
            if (picked)
              Positioned(
                top: 2,
                right: 3,
                child: Text('P$pickedSlot',
                    style: AppText.display(10, color: Colors.white)),
              ),
          ],
        ),
      ),
    );
  }
}
