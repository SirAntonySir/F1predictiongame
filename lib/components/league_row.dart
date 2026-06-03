// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'trend_badge.dart';

/// Which column the row should emphasise. Drives both the bold/large
/// rendering of the "fat" number and (for [inSeason]) hides the redundant
/// total column entirely — the user is already looking at an in-season
/// leaderboard so the cumulated total is noise.
enum LeagueRowFocus { inSeason, total }

class LeagueRow extends StatelessWidget {
  final int rank;
  final String name;
  final String? subtitle;
  final int inSeasonPoints;
  final int preseasonPoints;
  final int pointsTotal;
  final TrendDirection trend;
  final bool isMe;
  final Color? accentStripe;
  final LeagueRowFocus focus;

  const LeagueRow({
    super.key,
    required this.rank,
    required this.name,
    this.subtitle,
    required this.inSeasonPoints,
    required this.preseasonPoints,
    required this.pointsTotal,
    required this.trend,
    this.isMe = false,
    this.accentStripe,
    this.focus = LeagueRowFocus.total,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: Spacing.md),
      color: isMe ? t.rowHighlight : null,
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text('$rank',
                style: AppText.display(18,
                    color: isMe ? BrandColors.accent : t.colorScheme.onSurface)),
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
                Text(name,
                    style: AppText.body(13,
                        weight: isMe ? FontWeight.w800 : FontWeight.w700)),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!,
                        style: AppText.body(10,
                            color: t.colorScheme.onSurface.withOpacity(0.5))),
                  ),
              ],
            ),
          ),
          if (trend != TrendDirection.equal) ...[
            TrendBadge(direction: trend, label: '1'),
            const SizedBox(width: Spacing.sm),
          ],
          // In-season tab: pre on the left, season (big) on the right so the
          // emphasised value sits in the same end-of-row slot as the total
          // does in the Total tab.
          if (focus == LeagueRowFocus.inSeason) ...[
            _pointsCell(t, '$preseasonPoints', 'pre'),
            const SizedBox(width: 8),
            _pointsCell(t, '$inSeasonPoints', 'season', emphasis: true),
          ] else ...[
            _pointsCell(t, '$inSeasonPoints', 'season'),
            const SizedBox(width: 8),
            _pointsCell(t, '$preseasonPoints', 'pre'),
            const SizedBox(width: 8),
            _pointsCell(t, '$pointsTotal', 'pts', emphasis: true),
          ],
        ],
      ),
    );
  }

  Widget _pointsCell(ThemeData t, String value, String label, {bool emphasis = false}) {
    // Width 50 lets the longest label ("season") render on a single line at
    // AppText.label(8) — the previous 38 caused it to wrap into "seaso\nn".
    return SizedBox(
      width: 50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(value,
              style: AppText.display(emphasis ? 18 : 14,
                  color: emphasis
                      ? t.colorScheme.onSurface
                      : t.colorScheme.onSurface.withOpacity(0.65))),
          Text(
            label,
            softWrap: false,
            overflow: TextOverflow.visible,
            style: AppText.label(8,
                color: t.colorScheme.onSurface.withOpacity(0.6)),
          ),
        ],
      ),
    );
  }
}
