// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'trend_badge.dart';

class LeagueRow extends StatelessWidget {
  final int rank;
  final String initials;
  final String name;
  final String? subtitle;
  final int points;
  final TrendDirection trend;
  final bool isMe;
  const LeagueRow({
    super.key,
    required this.rank,
    required this.initials,
    required this.name,
    this.subtitle,
    required this.points,
    required this.trend,
    this.isMe = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: Spacing.md),
      color: isMe ? const Color(0xFFFFF7D1) : null,
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text('$rank',
                style: AppText.display(18, color: isMe ? BrandColors.accent : t.colorScheme.onSurface)),
          ),
          const SizedBox(width: 10),
          Container(
            width: 32, height: 32,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFEEEEEE)),
            alignment: Alignment.center,
            child: Text(initials, style: AppText.display(12)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name, style: AppText.body(13, weight: isMe ? FontWeight.w800 : FontWeight.w700)),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!, style: AppText.body(10, color: t.colorScheme.onSurface.withOpacity(0.5))),
                  ),
              ],
            ),
          ),
          TrendBadge(direction: trend, label: trend == TrendDirection.equal ? '' : '1'),
          const SizedBox(width: Spacing.sm),
          SizedBox(
            width: 42,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('$points', style: AppText.display(18)),
                Text('pts', style: AppText.label(8, color: t.colorScheme.onSurface.withOpacity(0.6))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
