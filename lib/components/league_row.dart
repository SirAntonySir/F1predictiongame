// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'trend_badge.dart';

class LeagueRow extends StatelessWidget {
  final int rank;
  final String name;
  final String? subtitle;
  final int points;
  final TrendDirection trend;
  final bool isMe;
  final Color? accentStripe;

  const LeagueRow({
    super.key,
    required this.rank,
    required this.name,
    this.subtitle,
    required this.points,
    required this.trend,
    this.isMe = false,
    this.accentStripe,
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
          if (accentStripe != null) ...[
            const SizedBox(width: 10),
            Container(width: 4, height: 22, color: accentStripe),
          ],
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
          if (trend != TrendDirection.equal) ...[
            TrendBadge(direction: trend, label: '1'),
            const SizedBox(width: Spacing.sm),
          ],
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
