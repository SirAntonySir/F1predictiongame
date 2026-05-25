// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

class BottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  const BottomNav({super.key, required this.currentIndex, required this.onTap});

  static const _labels = ['Home', 'Calendar', 'Predict', 'Standings'];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(Spacing.xl, Spacing.md, Spacing.xl, Spacing.xxl),
      decoration: BoxDecoration(
        color: t.colorScheme.surface,
        border: Border(top: BorderSide(color: t.strokeColor, width: Strokes.card)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: List.generate(_labels.length, (i) {
            final active = i == currentIndex;
            return Expanded(
              child: InkWell(
                onTap: () => onTap(i),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
                      child: Text(
                        _labels[i].toUpperCase(),
                        style: AppText.label(
                          11,
                          color: active
                              ? BrandColors.accent
                              : t.colorScheme.onSurface.withOpacity(0.55),
                        ),
                      ),
                    ),
                    if (active)
                      const Positioned(
                        top: 0,
                        child: SizedBox(
                          width: 24,
                          height: 3,
                          child: DecoratedBox(
                            decoration: BoxDecoration(color: BrandColors.accent, borderRadius: BorderRadius.all(Radius.circular(2))),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
