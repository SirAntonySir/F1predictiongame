// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import '../domain/leaderboard_trend.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'league_row.dart' show LeagueRowYouBadge;
import 'trend_badge.dart';

/// One row in a [StandingsList].
class StandingsEntry {
  final String userId;
  final String displayName;
  final int points;
  final PositionTrend? trend;
  const StandingsEntry({
    required this.userId,
    required this.displayName,
    required this.points,
    this.trend,
  });
}

/// Compact bordered standings list — rank · name (your row accented + YOU
/// badge) · optional trend badge · points. The caller supplies rows already
/// sorted and capped. Extracted from the home screen's league card so the
/// race-detail weekend view and home share one renderer.
class StandingsList extends StatelessWidget {
  final List<StandingsEntry> entries;
  final String? meId;
  final void Function(String userId)? onTapRow;
  const StandingsList({
    super.key,
    required this.entries,
    this.meId,
    this.onTapRow,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: t.strokeColor, width: Strokes.card),
        borderRadius: Radii.rLg,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: List.generate(entries.length, (i) {
          final e = entries[i];
          final isMe = e.userId == meId;
          return InkWell(
            onTap: onTapRow == null ? null : () => onTapRow!(e.userId),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.sm, vertical: Spacing.sm),
              decoration: BoxDecoration(
                border: i == entries.length - 1
                    ? null
                    : Border(
                        bottom: BorderSide(
                            color: t.strokeColor.withOpacity(0.25), width: 1),
                      ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    child: Text('${i + 1}',
                        style: AppText.display(13,
                            color: isMe
                                ? BrandColors.accent
                                : t.colorScheme.onSurface)),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            e.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.fade,
                            softWrap: false,
                            style: AppText.body(13,
                                weight:
                                    isMe ? FontWeight.w800 : FontWeight.w600),
                          ),
                        ),
                        if (isMe) ...[
                          const SizedBox(width: 6),
                          const LeagueRowYouBadge(),
                        ],
                      ],
                    ),
                  ),
                  if (e.trend != null &&
                      e.trend!.direction != TrendDirection.equal)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: TrendBadge(
                          direction: e.trend!.direction,
                          label: '${e.trend!.magnitude}'),
                    ),
                  SizedBox(
                    width: 40,
                    child: Text('${e.points}',
                        style: AppText.display(15),
                        textAlign: TextAlign.right),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}
