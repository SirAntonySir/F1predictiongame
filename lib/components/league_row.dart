// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'avatar_thumbnail.dart';
import 'trend_badge.dart';

/// Which column the row should emphasise. Drives both the bold/large
/// rendering of the "fat" number and (for [inSeason]) hides the redundant
/// total column entirely — the user is already looking at an in-season
/// leaderboard so the cumulated total is noise.
enum LeagueRowFocus { inSeason, total }

// Shared column widths so the league header and rows align exactly.
const double leagueRowPosCol = 26;
// Avatar head-crop diameter; the header reserves this + a gap so "PLAYER"
// stays aligned over the names.
const double leagueRowAvatarCol = 28;
// Wide enough to hold the one-row trend badge ("▲ 12") without wrapping the
// number under the arrow. Reserved on every row so the points columns line up.
const double leagueRowTrendCol = 38;
const double leagueRowPointsCol = 50;
const double leagueRowPointsGap = 8;

class LeagueRow extends StatelessWidget {
  final int rank;
  final String name;
  /// Opaque AvatarConfig JSON for the member's head-crop thumbnail (null →
  /// default livery). Kept for a future helmet-only marker; avatars are off in
  /// the leaderboard for now ([showAvatar] defaults false).
  final String? avatarConfig;
  final bool showAvatar;
  final String? subtitle;
  final int inSeasonPoints;
  final int preseasonPoints;
  final int pointsTotal;
  final TrendDirection trend;
  /// Number of positions moved since the previous event. Rendered as the
  /// digit inside the trend badge ("▲ 3"). Ignored when [trend] is equal.
  final int trendMagnitude;
  final bool isMe;
  final LeagueRowFocus focus;
  /// When true the row omits its bottom divider — used by the caller to
  /// suppress the last row's separator inside a single-bordered list.
  final bool isLast;

  const LeagueRow({
    super.key,
    required this.rank,
    required this.name,
    this.avatarConfig,
    this.showAvatar = false,
    this.subtitle,
    required this.inSeasonPoints,
    required this.preseasonPoints,
    required this.pointsTotal,
    required this.trend,
    this.trendMagnitude = 1,
    this.isMe = false,
    this.focus = LeagueRowFocus.total,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
        padding: const EdgeInsets.symmetric(
            horizontal: Spacing.sm, vertical: Spacing.sm),
        decoration: BoxDecoration(
          // No row-highlight bg: per-row tint clipped awkwardly against the
          // outer rounded-corner border. The YOU badge inside the name row
          // is the new "this is you" affordance.
          border: isLast
              ? null
              : Border(
                  bottom: BorderSide(
                      color: t.strokeColor.withOpacity(0.25), width: 1),
                ),
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
            if (showAvatar) ...[
              AvatarThumbnail(
                  configJson: avatarConfig,
                  size: leagueRowAvatarCol,
                  background: false),
              const SizedBox(width: Spacing.sm),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(name,
                            maxLines: 1, overflow: TextOverflow.fade, softWrap: false,
                            style: AppText.body(13,
                                weight: isMe ? FontWeight.w800 : FontWeight.w700)),
                      ),
                      if (isMe) ...[
                        const SizedBox(width: 6),
                        const LeagueRowYouBadge(),
                      ],
                    ],
                  ),
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
                  : Center(child: TrendBadge(direction: trend, label: '$trendMagnitude')),
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

/// Small red "YOU" pill rendered next to the current viewer's name on
/// every league/leaderboard row. Replaces the older "(you)" suffix +
/// highlighted background (which clipped at rounded list corners).
class LeagueRowYouBadge extends StatelessWidget {
  const LeagueRowYouBadge({super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: const BoxDecoration(
        color: BrandColors.accent,
        borderRadius: Radii.rSm,
      ),
      child: Text('YOU', style: AppText.label(8, color: Colors.white)),
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
