import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../theme/team_colors.dart';
import '../theme/typography.dart';

enum PodMark { none, exact, miss }

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
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 10, 6, 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.all(Radius.circular(10)),
      ),
      child: Stack(
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('P$position', style: AppText.label(9, color: fg)),
                const SizedBox(height: 2),
                Text(driverCode, style: AppText.display(13, color: fg)),
              ],
            ),
          ),
          if (mark != PodMark.none)
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: mark == PodMark.exact ? BrandColors.ok : Colors.black,
                ),
                child: Center(
                  child: Text(
                    mark == PodMark.exact ? '✓' : '✗',
                    style: TextStyle(
                      color: mark == PodMark.exact ? Colors.black : Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static Color _readableOn(Color bg) =>
      bg.computeLuminance() > 0.55 ? Colors.black : Colors.white;
}
