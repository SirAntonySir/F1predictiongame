// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:skeletonizer/skeletonizer.dart';
import '../../api/models/leaderboard_row.dart';
import '../../components/app_card.dart';
import '../../components/cached_view.dart';
import '../../components/league_row.dart';
import '../../components/racing_stripes.dart';
import '../../components/trend_badge.dart';
import '../../state/app_state.dart';
import '../../state/async_cache.dart';
import '../../theme/app_theme.dart';
import '../../theme/colors.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';

enum _Metric { inSeason, total }

extension on _Metric {
  String get label => switch (this) {
        _Metric.inSeason => 'IN-SEASON',
        _Metric.total => 'TOTAL',
      };

  int Function(LeaderboardRow) get extractor => switch (this) {
        _Metric.inSeason => (r) => r.inSeasonPoints,
        _Metric.total => (r) => r.pointsTotal,
      };
}

class LeagueTab extends StatefulWidget {
  /// Initial metric the tab should highlight + sort by. Parsed from a router
  /// query string (`?sort=total|inseason`) so the Home cards can deep-link to
  /// the matching view. Defaults to in-season.
  final String? initialMetric;
  final int? season;
  const LeagueTab({super.key, this.initialMetric, this.season});

  @override
  State<LeagueTab> createState() => _LeagueTabState();
}

class _LeagueTabState extends State<LeagueTab> {
  late final AsyncCache<List<LeaderboardRow>> _cache =
      AsyncCache<List<LeaderboardRow>>(_fetch);
  late _Metric _metric = switch (widget.initialMetric) {
    'total' => _Metric.total,
    _ => _Metric.inSeason,
  };
  bool _kickedOffRefresh = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_kickedOffRefresh) {
      _kickedOffRefresh = true;
      // ignore: discarded_futures
      _cache.refresh();
    }
  }

  @override
  void dispose() {
    _cache.dispose();
    super.dispose();
  }

  Future<List<LeaderboardRow>> _fetch() async {
    final scope = AppState.of(context);
    final leagues = scope.auth.leagues;
    if (leagues.isEmpty) return const [];
    return scope.api.leagueLeaderboard(leagues.first.id, season: widget.season);
  }

  static const _placeholder = <LeaderboardRow>[
    LeaderboardRow(userId: 'p1', displayName: 'Player one',   inSeasonPoints: 0, preseasonPoints: 0, pointsTotal: 0, sessionsScored: 0),
    LeaderboardRow(userId: 'p2', displayName: 'Player two',   inSeasonPoints: 0, preseasonPoints: 0, pointsTotal: 0, sessionsScored: 0),
    LeaderboardRow(userId: 'p3', displayName: 'Player three', inSeasonPoints: 0, preseasonPoints: 0, pointsTotal: 0, sessionsScored: 0),
    LeaderboardRow(userId: 'p4', displayName: 'Player four',  inSeasonPoints: 0, preseasonPoints: 0, pointsTotal: 0, sessionsScored: 0),
    LeaderboardRow(userId: 'p5', displayName: 'Player five',  inSeasonPoints: 0, preseasonPoints: 0, pointsTotal: 0, sessionsScored: 0),
    LeaderboardRow(userId: 'p6', displayName: 'Player six',   inSeasonPoints: 0, preseasonPoints: 0, pointsTotal: 0, sessionsScored: 0),
  ];

  @override
  Widget build(BuildContext context) {
    final scope = AppState.of(context);
    return CachedView<List<LeaderboardRow>>(
      cache: _cache,
      placeholder: _placeholder,
      where: 'League standings',
      builder: (_, rows) {
        if (rows.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(Spacing.lg),
              child: Text('No scores yet — once a session finishes, the leaderboard fills in.'),
            ),
          );
        }
        final me = scope.auth.currentUserId;
        final extractor = _metric.extractor;
        final sorted = [...rows]
          ..sort((a, b) => extractor(b).compareTo(extractor(a)));
        return ListView(
          padding: const EdgeInsets.only(bottom: Spacing.xxl),
          children: [
            // League identity pill — moved here from the Standings header so
            // the header is just the screen title + season switcher.
            Skeleton.keep(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    Spacing.lg, Spacing.md, Spacing.lg, Spacing.sm),
                child: Align(alignment: Alignment.centerLeft, child: _leaguePill(context)),
              ),
            ),
            // Toggle is a fixed control — Skeleton.keep so users can still
            // switch metrics even before the leaderboard lands.
            Skeleton.keep(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    Spacing.lg, 0, Spacing.lg, Spacing.sm),
                child: _MetricToggle(
                  metric: _metric,
                  onChanged: (m) => setState(() => _metric = m),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Spacing.lg, Spacing.xs, Spacing.lg, 0),
              child: _Podium(
                rows: sorted.take(3).toList(),
                points: extractor,
                metricLabel: _metric.label,
              ),
            ),
            const SizedBox(height: Spacing.md),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
              child: Column(
                children: [
                  LeagueRowHeader(
                    focus: _metric == _Metric.inSeason
                        ? LeagueRowFocus.inSeason
                        : LeagueRowFocus.total,
                  ),
                  ...List.generate(sorted.length, (i) {
                    final r = sorted[i];
                    final isMe = r.userId == me;
                    return LeagueRow(
                      rank: i + 1,
                      name: isMe ? '${r.displayName} (you)' : r.displayName,
                      inSeasonPoints: r.inSeasonPoints,
                      preseasonPoints: r.preseasonPoints,
                      pointsTotal: r.pointsTotal,
                      trend: TrendDirection.equal,
                      isMe: isMe,
                      focus: _metric == _Metric.inSeason
                          ? LeagueRowFocus.inSeason
                          : LeagueRowFocus.total,
                    );
                  }),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _leaguePill(BuildContext context) {
    final t = Theme.of(context);
    final league = AppState.of(context).league.league;
    final label = league == null ? 'No league' : '${league.name} · ${league.members.length}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 5),
      decoration: BoxDecoration(
        border: Border.all(color: t.strokeColor, width: 1.5),
        borderRadius: const BorderRadius.all(Radius.circular(999)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 8, height: 8, decoration: const BoxDecoration(color: BrandColors.accent, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: AppText.label(11, color: t.colorScheme.onSurface)),
      ]),
    );
  }
}

class _MetricToggle extends StatelessWidget {
  final _Metric metric;
  final ValueChanged<_Metric> onChanged;
  const _MetricToggle({required this.metric, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: t.strokeColor, width: 1.5),
        borderRadius: const BorderRadius.all(Radius.circular(8)),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.all(Radius.circular(6.5)),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Expanded(child: _seg(t, _Metric.inSeason)),
              Container(width: 1.5, color: t.strokeColor),
              Expanded(child: _seg(t, _Metric.total)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _seg(ThemeData t, _Metric m) {
    final on = m == metric;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(m),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        color: on ? t.colorScheme.onSurface : Colors.transparent,
        child: Center(
          child: Text(
            m.label,
            style: AppText.label(
              10,
              color: on ? t.colorScheme.surface : t.colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

/// Podium card — visual order 2 | 1 | 3 with descending heights.
///
/// Each step is rendered as a pit-board: a ghost position numeral bleeds
/// across the back; a "P{n}" chip pins the top; the leader's step gets the
/// brand-red fill, racing-stripe overlay, and a checkered finish strip across
/// the bottom of the card.
class _Podium extends StatelessWidget {
  final List<LeaderboardRow> rows;
  final int Function(LeaderboardRow) points;
  final String metricLabel;
  const _Podium({
    required this.rows,
    required this.points,
    required this.metricLabel,
  });

  @override
  Widget build(BuildContext context) {
    if (rows.length < 3) return const SizedBox.shrink();
    final t = Theme.of(context);
    final first = rows[0];
    final second = rows[1];
    final third = rows[2];
    return AppCard(
      background: t.mutedSurface,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Spacing.md, Spacing.md, Spacing.md, Spacing.sm),
            // Header used to also carry a trophy + leader-name pill on
            // the right, but the leader's name already reads loud and
            // clear on the P1 step below — the pill was a redundant
            // second "P1" marker.
            child: Text('TOP 3 · $metricLabel', style: AppText.label(10)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: _PodiumStep(
                      row: second,
                      pos: 2,
                      height: 104,
                      points: points,
                    ),
                  ),
                  Expanded(
                    child: _PodiumStep(
                      row: first,
                      pos: 1,
                      height: 138,
                      points: points,
                    ),
                  ),
                  Expanded(
                    child: _PodiumStep(
                      row: third,
                      pos: 3,
                      height: 82,
                      points: points,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(
            height: 12,
            child: CustomPaint(painter: _CheckeredPainter()),
          ),
        ],
      ),
    );
  }

}

class _PodiumStep extends StatelessWidget {
  final LeaderboardRow row;
  final int pos;
  final double height;
  final int Function(LeaderboardRow) points;

  const _PodiumStep({
    required this.row,
    required this.pos,
    required this.height,
    required this.points,
  });

  @override
  Widget build(BuildContext context) {
    final isLeader = pos == 1;
    final stepColor = switch (pos) {
      1 => BrandColors.accent,
      2 => const Color(0xFFE2E2E2),
      _ => const Color(0xFFC08350),
    };
    final onColor = isLeader ? Colors.white : Colors.black;
    final posLabel = pos.toString().padLeft(2, '0');
    // Borders share edges between neighbours: 2nd drops its right, 3rd drops
    // its left, so every seam stays a uniform 2px line.
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: stepColor,
        border: Border(
          top: const BorderSide(color: Colors.black, width: 2),
          left: BorderSide(
              color: Colors.black, width: pos == 3 ? 0 : 2),
          right: BorderSide(
              color: Colors.black, width: pos == 2 ? 0 : 2),
        ),
      ),
        child: ClipRect(
          child: Stack(
            children: [
              if (isLeader)
                const Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter:
                          RacingStripesPainter(opacity: 0.18, gap: 14),
                    ),
                  ),
                ),
              // Ghost position numeral — big, bleeds off the bottom-right edge.
              Positioned(
                right: -10,
                bottom: -22,
                child: Text(
                  posLabel,
                  style: AppText.display(
                    isLeader ? 104 : 84,
                    color: onColor.withOpacity(isLeader ? 0.18 : 0.12),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 7, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      color: isLeader ? Colors.white : Colors.black,
                      child: Text(
                        'P$pos',
                        style: AppText.label(
                          9,
                          color:
                              isLeader ? Colors.black : Colors.white,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      row.displayName.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.display(
                        isLeader ? 16 : 13,
                        color: onColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          '${points(row)}',
                          style: AppText.display(
                            isLeader ? 28 : 22,
                            color: onColor,
                          ),
                        ),
                        const SizedBox(width: 3),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            'PTS',
                            style: AppText.label(
                              8,
                              color: onColor.withOpacity(0.8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
  }
}

/// Checkered "finish line" strip painted across the bottom of the podium card.
class _CheckeredPainter extends CustomPainter {
  const _CheckeredPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const cell = 6.0;
    final rows = (size.height / cell).ceil();
    final cols = (size.width / cell).ceil();
    final fill = Paint()..color = Colors.black;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        if ((r + c) % 2 == 0) {
          canvas.drawRect(
            Rect.fromLTWH(c * cell, r * cell, cell, cell),
            fill,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_CheckeredPainter old) => false;
}
