// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:skeletonizer/skeletonizer.dart';

import 'package:country_flags/country_flags.dart';
import '../api/models/event.dart';
import '../api/models/player_profile.dart';
import '../components/avatar_thumbnail.dart';
import '../components/circuit_svg.dart';
import '../components/error_view.dart';
import '../theme/country_flags.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/team_colors.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// Composite player profile screen — opens when tapping a league row in
/// standings or on the home leaderboard preview.
///
/// Sections (top to bottom):
///   1. Header: name + league rank + total/inSeason/preseason points
///   2. Recent form ribbon (last 5 scored sessions)
///   3. Insight cards grid
///   4. Preseason scorecard
///   5. Locked-pick log (current season only, filtered server-side)
class PlayerScreen extends StatefulWidget {
  final String leagueId;
  final String userId;
  const PlayerScreen({super.key, required this.leagueId, required this.userId});
  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  Future<PlayerProfile>? _future;
  // Best-effort round → Event map, used to decorate the per-GP pick-log tiles
  // with the country flag + circuit map (same look as the calendar). Empty
  // until events() resolves; tiles degrade gracefully without it.
  Map<int, Event> _eventByRound = const {};
  bool _kickedEvents = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= AppState.of(context).api.leaguePlayer(widget.leagueId, widget.userId);
    if (!_kickedEvents) {
      _kickedEvents = true;
      final api = AppState.of(context).api;
      // ignore: discarded_futures
      () async {
        try {
          final evs = await api.events();
          if (mounted) {
            setState(() =>
                _eventByRound = {for (final e in evs) e.round: e});
          }
        } catch (_) {}
      }();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      backgroundColor: t.colorScheme.surface,
      body: SafeArea(
        child: FutureBuilder<PlayerProfile>(
          future: _future,
          builder: (ctx, snap) {
            if (snap.hasError) {
              return ErrorView(
                error: snap.error!,
                stack: snap.stackTrace,
                where: 'Player',
                onRetry: () => setState(() {
                  _future = AppState.of(context).api.leaguePlayer(widget.leagueId, widget.userId);
                }),
              );
            }
            if (!snap.hasData) {
              return Skeletonizer(child: _body(context, _placeholder()));
            }
            return _body(context, snap.data!);
          },
        ),
      ),
    );
  }

  PlayerProfile _placeholder() => PlayerProfile(
        player: PlayerHeader(
          userId: '', displayName: 'Loading…',
          joinedAt: DateTime.now(), isSelf: false,
        ),
        seasonYear: DateTime.now().year,
        standing: const PlayerStanding(
          leagueRank: null, leagueSize: 0, pointsTotal: 0,
          inSeasonPoints: 0, preseasonPoints: 0, sessionsScored: 0,
        ),
        recentForm: const [],
        insights: const PlayerInsights(
          mostPickedP1: null, bestWeekend: null,
          exactHitRate: null, teamBonusRate: null,
          sessionsScored: 0, totalSlots: 0, exactSlots: 0,
        ),
        preseason: const PlayerPreseason(
          picks: [], driverStandings: [], constructorStandings: [],
          projectedTotal: null,
        ),
        pickLog: const [],
      );

  Widget _body(BuildContext context, PlayerProfile p) {
    final t = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.lg, Spacing.lg, Spacing.xxl),
      children: [
        Row(children: [
          IconButton(
            onPressed: () => context.pop(),
            icon: const Icon(Icons.arrow_back_ios_new, size: 16),
          ),
          Expanded(
            child: Text(p.player.displayName.toUpperCase(),
                style: AppText.display(24),
                maxLines: 1, overflow: TextOverflow.fade, softWrap: false),
          ),
          if (p.player.isSelf)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: 3),
              decoration: const BoxDecoration(
                color: BrandColors.accent,
                borderRadius: Radii.rPill,
              ),
              child: Text('YOU', style: AppText.label(9, color: Colors.white)),
            ),
        ]),
        const SizedBox(height: Spacing.md),
        _StandingHeader(
          standing: p.standing,
          season: p.seasonYear,
          avatarConfig: p.player.avatarConfig,
        ),

        if (p.recentForm.isNotEmpty) ...[
          const SizedBox(height: Spacing.xl),
          Text('RECENT FORM', style: AppText.label(11)),
          const SizedBox(height: Spacing.sm),
          SizedBox(
            height: 68,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: p.recentForm.length,
              separatorBuilder: (_, __) => const SizedBox(width: Spacing.xs),
              itemBuilder: (_, i) => _RecentChip(item: p.recentForm[i]),
            ),
          ),
        ],

        const SizedBox(height: Spacing.xl),
        Text('INSIGHTS', style: AppText.label(11)),
        const SizedBox(height: Spacing.sm),
        _InsightGrid(insights: p.insights),

        if (p.preseason.picks.isNotEmpty || p.preseason.driverStandings.isNotEmpty) ...[
          const SizedBox(height: Spacing.xl),
          Text('PRESEASON', style: AppText.label(11)),
          const SizedBox(height: Spacing.sm),
          _PreseasonSummaryRow(
            preseason: p.preseason,
            onTap: () => context.push(
              '/league/${widget.leagueId}/player/${widget.userId}/preseason'
                  '?name=${Uri.encodeQueryComponent(p.player.displayName)}',
            ),
          ),
        ],

        const SizedBox(height: Spacing.xl),
        Text('LOCKED PICKS · ${p.seasonYear}', style: AppText.label(11)),
        const SizedBox(height: Spacing.sm),
        if (p.pickLog.isEmpty)
          Container(
            padding: const EdgeInsets.all(Spacing.lg),
            decoration: BoxDecoration(
              border: Border.all(color: t.strokeColor, width: Strokes.card),
              borderRadius: Radii.rLg,
            ),
            child: Text(
              p.player.isSelf
                  ? "You haven't locked any picks this season yet."
                  : "No locked picks yet this season.",
              style: AppText.body(13, color: t.colorScheme.onSurface.withOpacity(0.7)),
            ),
          )
        else
          ..._pickLogByGp(p.pickLog, _eventByRound),
      ],
    );
  }
}

/// Group the pick log by Grand Prix (round). Returns one [_GpGroupTile] per GP,
/// newest weekend first, the latest one expanded by default and the rest
/// collapsed with their weekend total in the header.
List<Widget> _pickLogByGp(
    List<PlayerPickLogItem> log, Map<int, Event> eventByRound) {
  final byRound = <int, List<PlayerPickLogItem>>{};
  for (final it in log) {
    byRound.putIfAbsent(it.round, () => []).add(it);
  }
  final groups = byRound.entries.map((e) {
    final items = [...e.value]
      ..sort((a, b) => a.scheduledStart.compareTo(b.scheduledStart));
    final total =
        items.fold<int>(0, (s, x) => s + (x.score?.points ?? 0));
    final latest = items
        .map((x) => x.scheduledStart)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    return _GpGroup(
      round: e.key,
      eventName: items.first.eventName,
      items: items,
      total: total,
      latest: latest,
    );
  }).toList()
    ..sort((a, b) => b.latest.compareTo(a.latest));
  return [
    for (var i = 0; i < groups.length; i++) ...[
      _GpGroupTile(
        group: groups[i],
        event: eventByRound[groups[i].round],
        initiallyExpanded: i == 0,
      ),
      const SizedBox(height: Spacing.sm),
    ],
  ];
}

/// ISO 3166-1 alpha-2 code from a regional-indicator flag emoji (🇫🇷 → "FR").
/// Returns null for anything that isn't a two-codepoint flag.
String? _isoFromEmoji(String? emoji) {
  if (emoji == null || emoji.isEmpty) return null;
  final runes = emoji.runes.toList();
  if (runes.length < 2) return null;
  const base = 0x1F1E6;
  final a = runes[0] - base;
  final b = runes[1] - base;
  if (a < 0 || a > 25 || b < 0 || b > 25) return null;
  return String.fromCharCodes([65 + a, 65 + b]);
}

class _GpGroup {
  final int round;
  final String eventName;
  final List<PlayerPickLogItem> items;
  final int total;
  final DateTime latest;
  _GpGroup({
    required this.round,
    required this.eventName,
    required this.items,
    required this.total,
    required this.latest,
  });
}

/// Collapsible per-GP tile: a bordered header (R{round} · event · weekend total)
/// that toggles its body of [_PickLogCard]s.
class _GpGroupTile extends StatefulWidget {
  final _GpGroup group;
  final Event? event;
  final bool initiallyExpanded;
  const _GpGroupTile({
    required this.group,
    required this.event,
    required this.initiallyExpanded,
  });

  @override
  State<_GpGroupTile> createState() => _GpGroupTileState();
}

class _GpGroupTileState extends State<_GpGroupTile> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final g = widget.group;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: Radii.rLg,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: t.strokeColor, width: Strokes.card),
              borderRadius: Radii.rLg,
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                // Faint circuit map anchored to the right — same watermark
                // treatment as the calendar race tiles.
                if (widget.event != null)
                  Positioned(
                    right: -14,
                    top: -18,
                    bottom: -18,
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: 0.16,
                        child: CircuitSvg(
                          event: widget.event!,
                          variant: 'white',
                          width: 120,
                          height: 120,
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.md, vertical: Spacing.md),
                  child: Row(
                    children: [
                      if (widget.event != null) ...[
                        _flag(flagFor(widget.event!.country)),
                        const SizedBox(width: Spacing.sm),
                      ],
                      Expanded(
                        child: Text('R${g.round} · ${g.eventName}',
                            maxLines: 1,
                            overflow: TextOverflow.fade,
                            softWrap: false,
                            style: AppText.label(11)),
                      ),
                      const SizedBox(width: Spacing.sm),
                      Text('${g.total}',
                          style:
                              AppText.display(15, color: BrandColors.accent)),
                      const SizedBox(width: 4),
                      Text('PTS',
                          style: AppText.label(9,
                              color: t.colorScheme.onSurface.withOpacity(0.5))),
                      const SizedBox(width: Spacing.sm),
                      Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                          size: 18,
                          color: t.colorScheme.onSurface.withOpacity(0.6)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: Spacing.sm),
          for (final it in g.items) ...[
            _PickLogCard(item: it),
            const SizedBox(height: Spacing.sm),
          ],
        ],
      ],
    );
  }

  Widget _flag(String? flag) {
    if (flag == null) return const SizedBox(width: 22, height: 16);
    final code = _isoFromEmoji(flag);
    if (code != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: CountryFlag.fromCountryCode(code, height: 16, width: 22),
      );
    }
    return Text(flag, style: const TextStyle(fontSize: 16, height: 1));
  }
}

/// Top header card with league rank + the three point totals, plus the
/// player's avatar as a centered hero shot fading out toward the bottom.
class _StandingHeader extends StatelessWidget {
  final PlayerStanding standing;
  final int season;
  final String? avatarConfig;
  const _StandingHeader({
    required this.standing,
    required this.season,
    this.avatarConfig,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      // Border sits in foregroundDecoration so it paints *over* the hero bust
      // (the svg is behind the card's border, not clipped by it).
      foregroundDecoration: BoxDecoration(
        border: Border.all(color: t.strokeColor, width: Strokes.card),
        borderRadius: Radii.rLg,
      ),
      decoration: const BoxDecoration(borderRadius: Radii.rLg),
      // Fixed height (bounded, so bust + stats can both be Positioned.fill):
      // tall enough that the full upper body shows, with the rank pinned to
      // the top and the metrics row pinned to the bottom.
      height: 210,
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Hero bust behind the stats: full upper body, centered, fading out
          // toward the bottom so the metrics row stays readable.
          Positioned.fill(
            child: AvatarBust(configJson: avatarConfig),
          ),
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(Spacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        standing.leagueRank == null
                            ? '—'
                            : 'P${standing.leagueRank}',
                        style: AppText.display(36, color: BrandColors.accent),
                      ),
                      const SizedBox(width: Spacing.sm),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          standing.leagueRank == null
                              ? 'unranked'
                              : 'of ${standing.leagueSize}',
                          style: AppText.label(10,
                              color:
                                  t.colorScheme.onSurface.withOpacity(0.55)),
                        ),
                      ),
                      const Spacer(),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text('SEASON $season',
                            style: AppText.label(10,
                                color: t.colorScheme.onSurface
                                    .withOpacity(0.55))),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Row(children: [
                    _MetricCell(label: 'TOTAL', value: '${standing.pointsTotal}'),
                    const SizedBox(width: Spacing.lg),
                    _MetricCell(label: 'SEASON', value: '${standing.inSeasonPoints}'),
                    const SizedBox(width: Spacing.lg),
                    _MetricCell(label: 'PRESEASON', value: '${standing.preseasonPoints}'),
                    const Spacer(),
                    _MetricCell(label: 'SESSIONS', value: '${standing.sessionsScored}', muted: true),
                  ]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCell extends StatelessWidget {
  final String label;
  final String value;
  final bool muted;
  const _MetricCell({required this.label, required this.value, this.muted = false});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: AppText.label(9,
                color: t.colorScheme.onSurface.withOpacity(0.55))),
        const SizedBox(height: 2),
        Text(value,
            style: AppText.display(muted ? 16 : 22,
                color: muted
                    ? t.colorScheme.onSurface.withOpacity(0.7)
                    : t.colorScheme.onSurface)),
      ],
    );
  }
}

class _RecentChip extends StatelessWidget {
  final RecentFormItem item;
  const _RecentChip({required this.item});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md, vertical: Spacing.xs),
      decoration: BoxDecoration(
        border: Border.all(color: t.strokeColor, width: Strokes.card),
        borderRadius: Radii.rLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('+${item.points}', style: AppText.display(18)),
          const SizedBox(height: 2),
          Text('R${item.round} · ${_shortType(item.sessionType)}',
              style: AppText.label(8,
                  color: t.colorScheme.onSurface.withOpacity(0.55))),
          const SizedBox(height: Spacing.xs),
          Row(
            children: [
              for (final g in item.glyphs)
                if (g != FormGlyph.teamBonus) ...[
                  _Glyph(glyph: g),
                  const SizedBox(width: 2),
                ],
            ],
          ),
        ],
      ),
    );
  }
}

String _shortType(String t) => switch (t) {
      'race' => 'RACE',
      'qualifying' => 'Q',
      'sprint' => 'SPR',
      'sprint_quali' => 'SQ',
      _ => t.toUpperCase(),
    };

class _Glyph extends StatelessWidget {
  final FormGlyph glyph;
  const _Glyph({required this.glyph});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final color = switch (glyph) {
      FormGlyph.exact => BrandColors.ok,
      FormGlyph.wrongPos => BrandColors.near,
      FormGlyph.teamBonus => BrandColors.accent,
      FormGlyph.miss => t.colorScheme.onSurface.withOpacity(0.25),
    };
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _InsightGrid extends StatelessWidget {
  final PlayerInsights insights;
  const _InsightGrid({required this.insights});

  String _pct(double? v) => v == null ? '—' : '${(v * 100).round()}%';

  @override
  Widget build(BuildContext context) {
    final p1 = insights.mostPickedP1;
    final best = insights.bestWeekend;
    final cards = <Widget>[
      _InsightCard(
        label: 'MOST P1',
        value: p1?.driverCode ?? '—',
        sub: p1 == null ? null : '×${p1.count}',
      ),
      _InsightCard(
        label: 'BEST GP',
        value: best == null ? '—' : '+${best.points}',
        sub: best == null ? null : '${best.eventName} · ${best.sessions} ses.',
      ),
      _InsightCard(
        label: 'EXACT %',
        value: _pct(insights.exactHitRate),
        sub: insights.totalSlots == 0
            ? null
            : '${insights.exactSlots}/${insights.totalSlots} slots',
      ),
      _InsightCard(
        label: 'TEAM BONUS',
        value: _pct(insights.teamBonusRate),
        sub: insights.teamBonusRate == null
            ? 'no P1 picks yet'
            : '${insights.sessionsScored} sessions',
      ),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: Spacing.xs,
      crossAxisSpacing: Spacing.xs,
      childAspectRatio: 1.7,
      children: cards,
    );
  }
}

class _InsightCard extends StatelessWidget {
  final String label;
  final String value;
  final String? sub;
  const _InsightCard({required this.label, required this.value, required this.sub});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: t.strokeColor, width: Strokes.card),
        borderRadius: Radii.rLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: AppText.label(9,
                  color: t.colorScheme.onSurface.withOpacity(0.55))),
          const Spacer(),
          Text(value, style: AppText.display(22)),
          if (sub != null) ...[
            const SizedBox(height: 2),
            Text(sub!,
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: AppText.body(11,
                    color: t.colorScheme.onSurface.withOpacity(0.6))),
          ],
        ],
      ),
    );
  }
}

/// Compact preseason summary row on the player profile. Shows projected
/// total + currently-hitting category count. The full per-category detail
/// (driver/team axes + projected standings) lives on the dedicated
/// PlayerPreseasonScreen reached via the chevron tap.
class _PreseasonSummaryRow extends StatelessWidget {
  final PlayerPreseason preseason;
  final VoidCallback onTap;
  const _PreseasonSummaryRow({required this.preseason, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    // 'Hitting' counts categories with either the driver OR team correct
    // (each axis scores half the category's max independently).
    final hits = preseason.picks.where((p) => p.driverExact || p.teamExact).length;
    return InkWell(
      onTap: onTap,
      borderRadius: Radii.rLg,
      child: Container(
        padding: const EdgeInsets.all(Spacing.lg),
        decoration: BoxDecoration(
          border: Border.all(color: t.strokeColor, width: Strokes.card),
          borderRadius: Radii.rLg,
        ),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('PROJECTED TOTAL',
                    style: AppText.label(9,
                        color: t.colorScheme.onSurface.withOpacity(0.55))),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text('+${preseason.projectedTotal ?? 0}',
                        style: AppText.display(22, color: BrandColors.accent)),
                    const SizedBox(width: Spacing.sm),
                    Text(
                      '${preseason.picks.length} categories · $hits hitting',
                      style: AppText.body(11,
                          color: t.colorScheme.onSurface.withOpacity(0.7)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Text('›',
              style: TextStyle(fontSize: 22, color: t.colorScheme.onSurface)),
        ]),
      ),
    );
  }
}

// Legacy detailed card — kept for reference but no longer referenced.
// ignore: unused_element
class _PreseasonCard extends StatelessWidget {
  final PlayerPreseason preseason;
  final ThemeData t;
  const _PreseasonCard({required this.preseason, required this.t});

  String _categoryLabel(String c) => switch (c) {
        'surprise' => 'Surprise',
        'disappointment' => 'Disappointment',
        'dnf' => 'Most DNFs',
        'poles' => 'Most poles',
        'fastest_lap' => 'Fastest laps',
        'wdc_wcc' => 'WDC / WCC',
        _ => c,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        border: Border.all(color: t.strokeColor, width: Strokes.card),
        borderRadius: Radii.rLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (preseason.projectedTotal != null) ...[
            Row(children: [
              Text('PROJECTED TOTAL', style: AppText.label(9, color: t.colorScheme.onSurface.withOpacity(0.55))),
              const Spacer(),
              Text('+${preseason.projectedTotal}',
                  style: AppText.display(20, color: BrandColors.accent)),
            ]),
            const SizedBox(height: Spacing.sm),
          ],
          for (final p in preseason.picks)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                SizedBox(
                  width: 130,
                  child: Text(_categoryLabel(p.category).toUpperCase(),
                      style: AppText.label(10,
                          color: t.colorScheme.onSurface.withOpacity(0.55))),
                ),
                Text(
                  p.driverCode ?? p.constructorId ?? '—',
                  style: AppText.body(13,
                      weight: FontWeight.w800,
                      color: (p.driverExact || p.teamExact)
                          ? BrandColors.ok
                          : t.colorScheme.onSurface),
                ),
                const Spacer(),
                if (p.driverExact || p.teamExact)
                  Text('+${p.points}',
                      style: AppText.display(13, color: BrandColors.ok)),
              ]),
            ),
          if (preseason.driverStandings.isNotEmpty) ...[
            const SizedBox(height: Spacing.sm),
            Text('PROJECTED DRIVER ORDER',
                style: AppText.label(9, color: t.colorScheme.onSurface.withOpacity(0.55))),
            const SizedBox(height: Spacing.xs),
            Wrap(
              spacing: 6, runSpacing: 4,
              children: [
                for (final d in preseason.driverStandings)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      border: Border.all(color: t.strokeColor, width: 1),
                      borderRadius: Radii.rSm,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${d.position}',
                            style: AppText.label(8,
                                color: t.colorScheme.onSurface.withOpacity(0.5))),
                        const SizedBox(width: 4),
                        Text(d.code,
                            style: AppText.body(11, weight: FontWeight.w800)),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Mini classification-style row block for one locked session's picks.
class _PickLogCard extends StatelessWidget {
  final PlayerPickLogItem item;
  const _PickLogCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final resultsByPos = {for (final r in item.topResults) r.position: r};

    // Parse the score breakdown into a per-position lookup so we can render
    // exact / wrong-pos / miss state and the points each slot was worth.
    // Keys we care about: { position, exact, wrongPos, points }.
    final breakdownByPos = <int, _SlotBreakdown>{};
    bool teamBonusApplied = false;
    int teamBonusPoints = 0;
    final bd = item.score?.breakdown;
    if (bd != null) {
      final perPosition = (bd['perPosition'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      for (final p in perPosition) {
        final pos = (p['position'] as num).toInt();
        breakdownByPos[pos] = _SlotBreakdown(
          exact: p['exact'] as bool? ?? false,
          wrongPos: p['wrongPos'] as bool? ?? false,
          points: (p['points'] as num?)?.toInt() ?? 0,
        );
      }
      final tb = bd['teamBonus'] as Map<String, dynamic>?;
      teamBonusApplied = tb?['applied'] as bool? ?? false;
      teamBonusPoints = (tb?['points'] as num?)?.toInt() ?? 0;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () =>
          context.push('/race/${item.round}/${item.sessionId}'),
      child: Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        border: Border.all(color: t.strokeColor, width: Strokes.card),
        borderRadius: Radii.rLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(
                'R${item.round} · ${item.eventName} · ${_shortType(item.sessionType)}'
                    .toUpperCase(),
                style: AppText.label(11),
                maxLines: 1, overflow: TextOverflow.fade, softWrap: false,
              ),
            ),
            if (item.source == 'import') ...[
              const SizedBox(width: Spacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  border: Border.all(color: t.strokeColor, width: 1),
                  borderRadius: Radii.rSm,
                ),
                child: Text('IMPORT',
                    style: AppText.label(8,
                        color: t.colorScheme.onSurface.withOpacity(0.6))),
              ),
            ],
            if (item.provisional) ...[
              const SizedBox(width: Spacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: BrandColors.accent.withOpacity(0.15),
                  borderRadius: Radii.rSm,
                ),
                child: Text('PROVISIONAL',
                    style: AppText.label(8, color: BrandColors.accent)),
              ),
            ],
            if (item.score != null) ...[
              const SizedBox(width: Spacing.sm),
              Text('+${item.score!.points}',
                  style: AppText.display(18, color: BrandColors.accent)),
            ],
          ]),
          const SizedBox(height: Spacing.sm),
          for (final pick in item.picks) ...[
            _PickLine(
              pick: pick,
              actual: resultsByPos[pick.position],
              breakdown: breakdownByPos[pick.position],
            ),
            const SizedBox(height: 2),
          ],
          if (teamBonusApplied) ...[
            const SizedBox(height: Spacing.xs),
            Row(
              children: [
                const SizedBox(width: 26),
                Container(
                  width: 5, height: 14,
                  decoration: BoxDecoration(
                    color: BrandColors.accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Text('TEAM BONUS',
                    style: AppText.label(10,
                        color: BrandColors.accent)),
                const Spacer(),
                Text('+$teamBonusPoints',
                    style: AppText.display(13, color: BrandColors.accent)),
              ],
            ),
          ],
        ],
      ),
      ),
    );
  }
}

class _SlotBreakdown {
  final bool exact;
  final bool wrongPos;
  final int points;
  const _SlotBreakdown({
    required this.exact,
    required this.wrongPos,
    required this.points,
  });
}

class _PickLine extends StatelessWidget {
  final PickLogPick pick;
  final PickLogResult? actual;
  final _SlotBreakdown? breakdown;
  const _PickLine({
    required this.pick,
    required this.actual,
    required this.breakdown,
  });
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    // Stripe color = team of the *picked* driver. Falls back to the actual
    // finisher's team only if the backend didn't send a constructorId for
    // the pick (older response payloads).
    final pickedConstructor = pick.constructorId;
    final team = pickedConstructor != null
        ? teamColor(pickedConstructor)
        : (actual == null
            ? t.colorScheme.onSurface.withOpacity(0.2)
            : teamColor(actual!.constructorId));

    // Outcome label + color come from the canonical breakdown rather than
    // string-comparing pick vs. actual — that misses wrong-pos hits, where
    // the driver finished inside the top-N but at a different slot.
    final bd = breakdown;
    String tag;
    Color tagColor;
    if (bd == null) {
      tag = '';
      tagColor = t.colorScheme.onSurface.withOpacity(0.5);
    } else if (bd.exact) {
      tag = 'EXACT';
      tagColor = BrandColors.ok;
    } else if (bd.wrongPos) {
      tag = 'WRONG POS';
      tagColor = BrandColors.near;
    } else {
      tag = 'MISS';
      tagColor = t.colorScheme.onSurface.withOpacity(0.45);
    }

    return Row(children: [
      SizedBox(
        width: 26,
        child: Text('P${pick.position}',
            style: AppText.label(10,
                color: t.colorScheme.onSurface.withOpacity(0.55))),
      ),
      Container(
        width: 5,
        height: 18,
        decoration: BoxDecoration(
          color: team,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: Spacing.sm),
      SizedBox(
        width: 46,
        child: Text(pick.driverCode,
            style: AppText.body(13, weight: FontWeight.w800)),
      ),
      // `actual CODE` sits immediately to the right of the picked code (left-
      // aligned within the row) so the eye can scan pick → finisher on a
      // single line. The outcome pill + points still pin to the right edge.
      if (actual != null && bd != null && !bd.exact) ...[
        Text('actual ',
            style: AppText.label(9,
                color: t.colorScheme.onSurface.withOpacity(0.5))),
        Text(actual!.driverCode,
            style: AppText.body(12,
                weight: FontWeight.w800,
                color: t.colorScheme.onSurface.withOpacity(0.7))),
      ],
      const Spacer(),
      Text(tag, style: AppText.label(9, color: tagColor)),
      if (bd != null) ...[
        const SizedBox(width: 6),
        Text(bd.points > 0 ? '+${bd.points}' : '+0',
            style: AppText.display(12, color: tagColor)),
      ],
    ]);
  }
}
