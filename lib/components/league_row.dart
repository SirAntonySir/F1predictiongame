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

// Shared column widths so the league header and rows align exactly.
const double leagueRowPosCol = 26;
const double leagueRowTrendCol = 22;
const double leagueRowPointsCol = 50;
const double leagueRowPointsGap = 8;

class LeagueRow extends StatelessWidget {
  final int rank;
  final String name;
  final String? subtitle;
  final int inSeasonPoints;
  final int preseasonPoints;
  final int pointsTotal;
  final TrendDirection trend;
  final bool isMe;
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
    this.focus = LeagueRowFocus.total,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.xs),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: Spacing.sm, vertical: Spacing.xs),
        decoration: BoxDecoration(
          color: isMe ? t.rowHighlight : null,
          border: Border.all(color: t.strokeColor, width: Strokes.card),
          borderRadius: Radii.rLg,
        ),
        child: Row(
          children: [
            SizedBox(
              width: leagueRowPosCol,
              child: Text('$rank',
                  style: AppText.display(18,
                      color: isMe ? BrandColors.accent : t.colorScheme.onSurface)),
            ),
            const SizedBox(width: Spacing.sm),
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
            // Trend slot — reserved width so points columns line up across
            // rows even when no trend badge is shown.
            SizedBox(
              width: leagueRowTrendCol,
              child: trend == TrendDirection.equal
                  ? const SizedBox.shrink()
                  : Center(child: TrendBadge(direction: trend, label: '1')),
            ),
            const SizedBox(width: Spacing.sm),
            // In-season tab: pre on the left, season (big) on the right so the
            // emphasised value sits in the same end-of-row slot as the total
            // does in the Total tab.
            if (focus == LeagueRowFocus.inSeason) ...[
              _pointsCell(t, '$preseasonPoints', 'pre'),
              const SizedBox(width: leagueRowPointsGap),
              _pointsCell(t, '$inSeasonPoints', 'season', emphasis: true),
            ] else ...[
              _pointsCell(t, '$inSeasonPoints', 'season'),
              const SizedBox(width: leagueRowPointsGap),
              _pointsCell(t, '$preseasonPoints', 'pre'),
              const SizedBox(width: leagueRowPointsGap),
              _pointsCell(t, '$pointsTotal', 'pts', emphasis: true),
            ],
          ],
        ),
      ),
    );
  }

  Widget _pointsCell(ThemeData t, String value, String label, {bool emphasis = false}) {
    return SizedBox(
      width: leagueRowPointsCol,
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

/// Column header strip for the league leaderboard. Same column widths as
/// [LeagueRow] so labels sit centered over their data.
class LeagueRowHeader extends StatelessWidget {
  final LeagueRowFocus focus;
  const LeagueRowHeader({super.key, required this.focus});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = AppText.label(8, color: t.colorScheme.onSurface.withOpacity(0.55));
    final rightCells = focus == LeagueRowFocus.inSeason
        ? const ['PRE', 'SEASON']
        : const ['SEASON', 'PRE', 'PTS'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.sm, 0, Spacing.sm, Spacing.xs),
      child: Row(
        children: [
          SizedBox(width: leagueRowPosCol, child: Text('P', style: muted)),
          const SizedBox(width: Spacing.sm),
          Expanded(child: Text('PLAYER', style: muted)),
          const SizedBox(width: leagueRowTrendCol),
          const SizedBox(width: Spacing.sm),
          for (var i = 0; i < rightCells.length; i++) ...[
            if (i > 0) const SizedBox(width: leagueRowPointsGap),
            SizedBox(
              width: leagueRowPointsCol,
              child: Text(rightCells[i], style: muted, textAlign: TextAlign.right),
            ),
          ],
        ],
      ),
    );
  }
}
