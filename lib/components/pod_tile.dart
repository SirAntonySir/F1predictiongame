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
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 10, 6, 8),
      decoration: BoxDecoration(
        color: teamColor(constructorId),
        borderRadius: const BorderRadius.all(Radius.circular(10)),
      ),
      child: Stack(
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('P$position', style: AppText.label(9, color: Colors.white)),
                const SizedBox(height: 2),
                Text(driverCode, style: AppText.display(13, color: Colors.white)),
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
}
