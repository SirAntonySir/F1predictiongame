// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'app_card.dart';

class ScoreBanner extends StatelessWidget {
  final String label;
  final String value;
  final String? subtitle;
  final String? trailing;
  const ScoreBanner({
    super.key,
    required this.label,
    required this.value,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      background: BrandColors.accent,
      padding: const EdgeInsets.all(Spacing.lg),
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: Colors.white),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: AppText.label(10, color: Colors.white.withOpacity(0.85))),
                const SizedBox(height: 2),
                Text(value, style: AppText.display(36, color: Colors.white)),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: Spacing.xxs),
                    child: Text(subtitle!, style: AppText.body(12, color: Colors.white.withOpacity(0.9))),
                  ),
              ],
            ),
            if (trailing != null)
              Positioned(
                bottom: 0, right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: Spacing.xxs),
                  decoration: const BoxDecoration(
                    color: Color(0x4D000000),
                    borderRadius: BorderRadius.all(Radius.circular(6)),
                  ),
                  child: Text(trailing!, style: AppText.label(10, color: Colors.white)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
