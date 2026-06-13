import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../theme/team_colors.dart';
import '../theme/typography.dart';

enum PodMark { none, exact, nearMiss, miss }

class PodTile extends StatelessWidget {
  final int position;
  final String driverCode;
  final String constructorId;
  final PodMark mark;
  const PodTile({
    super.key,
    required this.position,
    required this.driverCode,
    required this.constructorId,
    this.mark = PodMark.none,
  });

  @override
  Widget build(BuildContext context) {
    final bg = teamColor(constructorId);
    final fg = _readableOn(bg);
    final ring = switch (mark) {
      PodMark.exact => BrandColors.ok,
      PodMark.nearMiss => BrandColors.near,
      PodMark.miss || PodMark.none => null,
    };
    final tile = Container(
      padding: const EdgeInsets.fromLTRB(6, 10, 6, 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.all(Radius.circular(10)),
        border: Border.all(
          color: ring ?? Colors.transparent,
          width: 2,
        ),
        boxShadow: ring == null
            ? null
            : [BoxShadow(color: ring.withOpacity(0.35), blurRadius: 6)],
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('P$position', style: AppText.label(9, color: fg)),
            const SizedBox(height: 2),
            Text(driverCode, style: AppText.display(13, color: fg)),
          ],
        ),
      ),
    );
    return mark == PodMark.miss ? Opacity(opacity: 0.45, child: tile) : tile;
  }

  static Color _readableOn(Color bg) =>
      bg.computeLuminance() > 0.55 ? Colors.black : Colors.white;
}
