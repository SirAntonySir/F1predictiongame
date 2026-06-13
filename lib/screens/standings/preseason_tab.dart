// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import '../../api/models/league_preseason_view.dart';
import '../../api/models/standing.dart';
import '../../components/app_card.dart';
import '../../components/error_view.dart';
import '../../components/standings_skeleton.dart';
import '../../domain/preseason.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../theme/colors.dart';
import '../../theme/team_colors.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';

class PreseasonTab extends StatefulWidget {
  const PreseasonTab({super.key, this.season}) : _injected = null, _injectedMyUserId = null;
  const PreseasonTab.withView(LeaguePreseasonView view, {super.key, String? myUserId})
      : _injected = view,
        _injectedMyUserId = myUserId,
        season = null;

  final int? season;
  final LeaguePreseasonView? _injected;
  final String? _injectedMyUserId;

  @override
  State<PreseasonTab> createState() => _PreseasonTabState();
}

class PreseasonBodyData {
  final LeaguePreseasonView view;
  final Map<String, DriverStanding> driverById;
  final Map<String, ConstructorStanding> constructorById;
  const PreseasonBodyData({
    required this.view,
    required this.driverById,
    required this.constructorById,
  });

  /// Resolve the standings maps (driverById, constructorById) once we have
  /// just the view. Convenience constructor for callers (like the player
  /// preseason screen) that fetch the view via `?as=` and the standings
  /// lists separately.
  factory PreseasonBodyData.from({
    required LeaguePreseasonView view,
    required List<DriverStanding> drivers,
    required List<ConstructorStanding> constructors,
  }) => PreseasonBodyData(
        view: view,
        driverById: { for (final d in drivers) d.driverCode: d },
        constructorById: { for (final c in constructors) c.constructorId: c },
      );
}

class _PreseasonTabState extends State<PreseasonTab> {
  Future<PreseasonBodyData>? _data;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget._injected != null) {
      _data ??= Future.value(PreseasonBodyData(
        view: widget._injected!,
        driverById: const {},
        constructorById: const {},
      ));
    } else {
      _data ??= _load();
    }
  }

  Future<PreseasonBodyData> _load() async {
    final scope = AppState.of(context);
    final leagues = scope.auth.leagues;
    if (leagues.isEmpty) {
      throw StateError('No league joined');
    }
    final results = await Future.wait([
      scope.api.leaguePreseason(leagues.first.id, season: widget.season),
      scope.api.driverStandings(season: widget.season),
      scope.api.constructorStandings(season: widget.season),
    ]);
    final view = results[0] as LeaguePreseasonView;
    final drivers = results[1] as List<DriverStanding>;
    final constructors = results[2] as List<ConstructorStanding>;
    return PreseasonBodyData(
      view: view,
      driverById: { for (final d in drivers) d.driverCode: d },
      constructorById: { for (final c in constructors) c.constructorId: c },
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PreseasonBodyData>(
      future: _data,
      builder: (_, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const StandingsListSkeleton();
        }
        if (snap.hasError) {
          return ErrorView(
            error: snap.error!,
            stack: snap.stackTrace,
            where: 'Preseason tab',
            onRetry: () => setState(() => _data = _load()),
          );
        }
        return PreseasonBodyView(
          data: snap.data!,
          myUserId: widget._injectedMyUserId ?? AppState.of(context).auth.currentUserId,
        );
      },
    );
  }
}

/// Reusable preseason body view. Drives both the Standings → Preseason tab
/// (default params) and the per-player preseason screen launched from the
/// player profile (sectionTitle override + leaderboard hidden).
class PreseasonBodyView extends StatelessWidget {
  final PreseasonBodyData data;
  final String? myUserId;
  /// Section header above the per-category cards. Default: "YOUR PROJECTIONS"
  /// for the caller's own view. Player profile screen passes
  /// "{Name}'S PROJECTIONS".
  final String sectionTitle;
  /// When false, the LEAGUE PRESEASON LEADERBOARD section is omitted (used
  /// by the player screen — the league rank is already in the profile header).
  final bool showLeaderboard;
  const PreseasonBodyView({
    super.key,
    required this.data,
    required this.myUserId,
    this.sectionTitle = 'YOUR PROJECTIONS',
    this.showLeaderboard = true,
  });

  LeaguePreseasonView get view => data.view;

  @override
  Widget build(BuildContext context) {
    final standings = view.me.standings;
    final myDriverByPosition = {for (final p in standings.myDriverPicks) p.position: p.driverCode};
    final myTeamByPosition = {for (final p in standings.myConstructorPicks) p.position: p.constructorId};
    final actualDriverPosition = {
      for (var i = 0; i < standings.projectedDriverOrder.length; i++)
        standings.projectedDriverOrder[i]: i + 1,
    };
    final actualTeamPosition = {
      for (var i = 0; i < standings.projectedConstructorOrder.length; i++)
        standings.projectedConstructorOrder[i]: i + 1,
    };

    return ListView(
      padding: const EdgeInsets.only(bottom: Spacing.xxl),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.lg, Spacing.lg, Spacing.xs),
          child: Row(
            children: [
              Expanded(child: Text('PROJECTED · LIVE', style: AppText.label(11))),
              Text('${view.me.projectedPointsTotal} pts',
                  style: AppText.display(18, color: BrandColors.accent)),
            ],
          ),
        ),
        if (showLeaderboard) ...[
          _h('LEAGUE PRESEASON LEADERBOARD'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
            child: Column(
              children: [
                const _LeaderHeader(),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).strokeColor, width: Strokes.card),
                    borderRadius: Radii.rLg,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (var i = 0; i < view.leaderboard.length; i++)
                        _LeaderRow(
                          rank: i + 1,
                          row: view.leaderboard[i],
                          isMe: view.leaderboard[i].userId == myUserId,
                          isLast: i == view.leaderboard.length - 1,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        _h(sectionTitle),
        for (final c in view.me.categories) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.sm, Spacing.lg, Spacing.xs),
            child: Text(_categoryLabelFor(c.category), style: AppText.label(11)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _CategoryAxisCard(card: c, axis: _PickAxis.driver, constructorById: data.constructorById)),
                  const SizedBox(width: Spacing.sm),
                  Expanded(child: _CategoryAxisCard(card: c, axis: _PickAxis.team, constructorById: data.constructorById)),
                ],
              ),
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: 3),
          child: _StandingsSummary(standings: standings),
        ),
        _h('COMPLETE CHAMPIONSHIP · DRIVERS'),
        for (var i = 0; i < standings.projectedDriverOrder.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: 3),
            child: _DriverPositionTile(
              position: i + 1,
              projectedCode: standings.projectedDriverOrder[i],
              myCode: myDriverByPosition[i + 1],
              projectedStanding: data.driverById[standings.projectedDriverOrder[i]],
              myStanding: myDriverByPosition[i + 1] == null
                  ? null
                  : data.driverById[myDriverByPosition[i + 1]!],
              myActualPosition: actualDriverPosition[myDriverByPosition[i + 1]],
            ),
          ),
        _h('COMPLETE CHAMPIONSHIP · TEAMS'),
        for (var i = 0; i < standings.projectedConstructorOrder.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: 3),
            child: _TeamPositionTile(
              position: i + 1,
              projectedId: standings.projectedConstructorOrder[i],
              myId: myTeamByPosition[i + 1],
              projectedStanding: data.constructorById[standings.projectedConstructorOrder[i]],
              myStanding: myTeamByPosition[i + 1] == null
                  ? null
                  : data.constructorById[myTeamByPosition[i + 1]!],
              myActualPosition: actualTeamPosition[myTeamByPosition[i + 1]],
            ),
          ),
      ],
    );
  }

  Widget _h(String s) => Padding(
        padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.lg, Spacing.lg, Spacing.xs),
        child: Text(s, style: AppText.label(11)),
      );
}

// Shared column widths for the preseason leaderboard header + rows.
const double _kLeaderPosCol = 22;
const double _kLeaderPointsCol = 50;

class _LeaderHeader extends StatelessWidget {
  const _LeaderHeader();
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = AppText.label(8, color: t.colorScheme.onSurface.withOpacity(0.55));
    return Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.sm, 0, Spacing.sm, Spacing.xs),
      child: Row(
        children: [
          SizedBox(width: _kLeaderPosCol, child: Text('P', style: muted)),
          const SizedBox(width: Spacing.sm),
          Expanded(child: Text('PLAYER', style: muted)),
          SizedBox(width: _kLeaderPointsCol, child: Text('PTS', style: muted, textAlign: TextAlign.right)),
        ],
      ),
    );
  }
}

class _LeaderRow extends StatelessWidget {
  final int rank;
  final LeaguePreseasonLeaderboardRow row;
  final bool isMe;
  final bool isLast;
  const _LeaderRow({
    required this.rank,
    required this.row,
    required this.isMe,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: Spacing.sm, vertical: Spacing.sm),
      decoration: BoxDecoration(
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
            width: _kLeaderPosCol,
            child: Text('$rank',
                style: AppText.display(15,
                    color: isMe ? BrandColors.accent : t.colorScheme.onSurface)),
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(row.displayName,
                      maxLines: 1, overflow: TextOverflow.fade, softWrap: false,
                      style: AppText.body(13,
                          weight: isMe ? FontWeight.w800 : FontWeight.w700)),
                ),
                if (isMe) ...[
                  const SizedBox(width: 6),
                  const _YouBadge(),
                ],
              ],
            ),
          ),
          SizedBox(
            width: _kLeaderPointsCol,
            child: Text('+${row.preseasonPointsProjected}',
                style: AppText.display(15,
                    color: isMe ? BrandColors.accent : null),
                textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}

/// Small red "YOU" pill — used everywhere we previously suffixed `(you)` to
/// the displayName.
class _YouBadge extends StatelessWidget {
  const _YouBadge();
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

/// `red_bull` -> `Red Bull`. Used as a fallback when we don't have a
/// ConstructorStanding for the id (e.g. category projections list a
/// constructorId without a paired standings row).
String _prettyConstructorId(String id) =>
    id.split('_').where((s) => s.isNotEmpty).map((s) {
      return s[0].toUpperCase() + s.substring(1);
    }).join(' ');

String constructorDisplayName(String id, Map<String, ConstructorStanding> byId) =>
    byId[id]?.constructorName ?? _prettyConstructorId(id);

String _categoryLabelFor(PreseasonCategory c) {
  switch (c) {
    case PreseasonCategory.surprise:       return 'SURPRISE';
    case PreseasonCategory.disappointment: return 'DISAPPOINTMENT';
    case PreseasonCategory.dnf:            return 'MOST DNFs';
    case PreseasonCategory.poles:          return 'MOST POLES';
    case PreseasonCategory.fastest_lap:    return 'MOST FASTEST LAPS';
    case PreseasonCategory.wdc_wcc:        return 'WDC + WCC';
  }
}

enum _PickAxis { driver, team }

/// One side of a category pair — focused on either the driver axis or the team
/// axis of the user's pick. Badge reflects only that axis, so it's a clean
/// full/none binary (no partial state needed).
class _CategoryAxisCard extends StatelessWidget {
  final CategoryProjectionView card;
  final _PickAxis axis;
  final Map<String, ConstructorStanding> constructorById;
  const _CategoryAxisCard({required this.card, required this.axis, required this.constructorById});

  bool get _isSubjective =>
      card.category == PreseasonCategory.surprise ||
      card.category == PreseasonCategory.disappointment;

  String? get _pickRaw =>
      axis == _PickAxis.driver ? card.myPick.driverCode : card.myPick.constructorId;
  String? get _truthRaw =>
      axis == _PickAxis.driver ? card.projectedTruth?.driverCode : card.projectedTruth?.constructorId;

  String _formatVal(String? raw) {
    if (raw == null) return '—';
    if (axis == _PickAxis.driver) return raw;
    return constructorDisplayName(raw, constructorById);
  }

  String _liveText() {
    if (_isSubjective) return 'Set at season end';
    if (_truthRaw == null) return 'Not yet recorded';
    return _formatVal(_truthRaw);
  }

  _MatchState _state() {
    if (_isSubjective) return _MatchState.subjective;
    if (_truthRaw == null) return _MatchState.pending;
    if (_pickRaw == null) return _MatchState.none;
    return _pickRaw == _truthRaw ? _MatchState.full : _MatchState.none;
  }

  // Backend awards each axis (driver / team) independently — half of the
  // category's `max`. So a 4/4 axis-card maps to a 8-point category total.
  String _scoreText(_MatchState state) {
    final axisMax = card.max ~/ 2;
    switch (state) {
      case _MatchState.full:    return '+$axisMax / $axisMax';
      case _MatchState.none:    return '+0 / $axisMax';
      case _MatchState.partial: return '+0 / $axisMax'; // not produced here
      case _MatchState.subjective:
      case _MatchState.pending: return '— / $axisMax';
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final state = _state();
    return AppCard(
      padding: const EdgeInsets.fromLTRB(Spacing.md, Spacing.sm, Spacing.md, Spacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  axis == _PickAxis.driver ? 'DRIVER' : 'TEAM',
                  style: AppText.label(9, color: t.colorScheme.onSurface.withOpacity(0.55)),
                ),
              ),
              Text(
                _scoreText(state),
                style: AppText.label(10, color: t.colorScheme.onSurface.withOpacity(0.6)),
              ),
              const SizedBox(width: Spacing.xs),
              _MatchBadge(state: state),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _formatVal(_pickRaw),
            maxLines: 1,
            overflow: TextOverflow.fade,
            softWrap: false,
            style: AppText.display(14, color: _pickRaw == null ? t.colorScheme.onSurface.withOpacity(0.4) : null),
          ),
          const SizedBox(height: 2),
          Text(
            _liveText(),
            maxLines: 1,
            overflow: TextOverflow.fade,
            softWrap: false,
            style: AppText.body(11, color: t.colorScheme.onSurface.withOpacity(0.6)),
          ),
        ],
      ),
    );
  }
}

enum _MatchState {
  /// No truth ever (e.g. "biggest surprise" — judged at season end).
  subjective,
  /// Objective but not yet recorded (e.g. no DNFs yet this season).
  pending,
  /// Pick matches truth on every non-null axis → full points.
  full,
  /// Pick matches some axes (e.g. team yes, driver no) → partial points.
  partial,
  /// Pick matches nothing → zero points.
  none,
}

/// Compact match-state pill next to a "Your pick" value.
///   full     → green ✓
///   partial  → yellow ½  (driver matched but team didn't, or vice versa)
///   none     → black  ✗
///   subjective / pending → no badge at all (nothing to judge yet)
class _MatchBadge extends StatelessWidget {
  final _MatchState state;
  const _MatchBadge({required this.state});

  @override
  Widget build(BuildContext context) {
    final (Color bg, String glyph, Color fg)? cfg = switch (state) {
      _MatchState.full    => (BrandColors.ok,     '✓', Colors.black),
      _MatchState.partial => (BrandColors.near,   '½', Colors.black),
      _MatchState.none    => (Colors.black,       '✗', Colors.white),
      _MatchState.subjective || _MatchState.pending => null,
    };
    if (cfg == null) return const SizedBox.shrink();
    return Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: cfg.$1, shape: BoxShape.circle),
      child: Text(cfg.$2, style: TextStyle(color: cfg.$3, fontWeight: FontWeight.w900, fontSize: 11)),
    );
  }
}

class _StandingsSummary extends StatelessWidget {
  final StandingsProjectionView standings;
  const _StandingsSummary({required this.standings});

  int _driverHits() {
    var hits = 0;
    for (final p in standings.myDriverPicks) {
      if (p.position - 1 < standings.projectedDriverOrder.length &&
          standings.projectedDriverOrder[p.position - 1] == p.driverCode) {
        hits++;
      }
    }
    return hits;
  }

  int _teamHits() {
    var hits = 0;
    for (final p in standings.myConstructorPicks) {
      if (p.position - 1 < standings.projectedConstructorOrder.length &&
          standings.projectedConstructorOrder[p.position - 1] == p.constructorId) {
        hits++;
      }
    }
    return hits;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.md, Spacing.lg, Spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: Text('COMPLETE CHAMPIONSHIP', style: AppText.display(15))),
              Text('+${standings.projectedPoints} / ${standings.max}',
                  style: AppText.label(11, color: t.colorScheme.onSurface.withOpacity(0.6))),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${_driverHits()} / ${standings.projectedDriverOrder.length} driver slots · '
            '${_teamHits()} / ${standings.projectedConstructorOrder.length} team slots',
            style: AppText.body(12, weight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// Compact RaceTile-style row for one championship position. Left: large position
/// number. Middle: the driver the *user predicted* for this slot (with team color
/// stripe). Right: badge showing where that pick actually stands today — ✓ if at
/// the predicted slot, ▲/▼ + magnitude otherwise, ✗ if the pick isn't in the
/// current projection at all.
class _DriverPositionTile extends StatelessWidget {
  final int position;
  final String projectedCode;
  final String? myCode;
  final DriverStanding? projectedStanding;
  final DriverStanding? myStanding;
  // Where the user's pick (`myCode`) actually sits in the projected order.
  // null = pick isn't in the current projection at all → fall back to ✗.
  final int? myActualPosition;
  const _DriverPositionTile({
    required this.position,
    required this.projectedCode,
    required this.myCode,
    required this.projectedStanding,
    required this.myStanding,
    required this.myActualPosition,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final correct = myCode != null && myCode == projectedCode;
    final delta = (myCode != null && myActualPosition != null)
        ? myActualPosition! - position
        : null;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: Spacing.sm, vertical: Spacing.xs),
      decoration: BoxDecoration(
        border: Border.all(color: t.strokeColor, width: Strokes.card),
        borderRadius: Radii.rLg,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text(
              position.toString().padLeft(2, '0'),
              style: AppText.display(20),
            ),
          ),
          const SizedBox(width: Spacing.xs),
          Container(
            width: 5,
            height: 32,
            decoration: BoxDecoration(
              color: myStanding != null
                  ? teamColor(myStanding!.constructorId)
                  : t.colorScheme.onSurface.withOpacity(0.15),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  myCode ?? '—',
                  style: AppText.display(15,
                      color: myCode == null ? t.colorScheme.onSurface.withOpacity(0.4) : null),
                ),
                if (myStanding != null) ...[
                  const SizedBox(height: 2),
                  Text(myStanding!.driverName,
                      style: AppText.body(11, color: t.colorScheme.onSurface.withOpacity(0.65))),
                ],
              ],
            ),
          ),
          _PickIndicator(
            myLabel: myCode,
            correct: correct,
            pickedDifferent: false,
            delta: delta,
          ),
        ],
      ),
    );
  }
}

class _TeamPositionTile extends StatelessWidget {
  final int position;
  final String projectedId;
  final String? myId;
  final ConstructorStanding? projectedStanding;
  final ConstructorStanding? myStanding;
  final int? myActualPosition;
  const _TeamPositionTile({
    required this.position,
    required this.projectedId,
    required this.myId,
    required this.projectedStanding,
    required this.myStanding,
    required this.myActualPosition,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final correct = myId != null && myId == projectedId;
    final delta = (myId != null && myActualPosition != null)
        ? myActualPosition! - position
        : null;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: Spacing.sm, vertical: Spacing.xs),
      decoration: BoxDecoration(
        border: Border.all(color: t.strokeColor, width: Strokes.card),
        borderRadius: Radii.rLg,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text(
              position.toString().padLeft(2, '0'),
              style: AppText.display(20),
            ),
          ),
          const SizedBox(width: Spacing.xs),
          Container(
            width: 5,
            height: 32,
            decoration: BoxDecoration(
              color: myId != null
                  ? teamColor(myId!)
                  : t.colorScheme.onSurface.withOpacity(0.15),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              myId == null
                  ? '—'
                  : (myStanding?.constructorName ?? _prettyConstructorId(myId!)),
              style: AppText.display(15,
                  color: myId == null ? t.colorScheme.onSurface.withOpacity(0.4) : null),
            ),
          ),
          _PickIndicator(
            myLabel: myId,
            correct: correct,
            pickedDifferent: false,
            delta: delta,
          ),
        ],
      ),
    );
  }
}

class _PickIndicator extends StatelessWidget {
  final String? myLabel;
  final bool correct;
  final bool pickedDifferent;
  // Signed offset of the user's pick from this slot in the projected order:
  //   <0 → pick is currently *higher* than predicted (overperforming) → green ▲
  //   >0 → pick is currently *lower*  than predicted (underperforming) → red  ▼
  //   ==0 → exact match (renders as ✓ via `correct`)
  //   null → pick isn't in the projection at all (renders as ✗)
  final int? delta;
  const _PickIndicator({
    required this.myLabel,
    required this.correct,
    required this.pickedDifferent,
    this.delta,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    if (myLabel == null) {
      return Text('—', style: AppText.label(11, color: t.colorScheme.onSurface.withOpacity(0.4)));
    }
    final Widget badge;
    if (correct) {
      badge = _circleBadge(BrandColors.ok, '✓', Colors.black);
    } else if (delta != null && delta != 0) {
      final up = delta! < 0;
      badge = _arrowPill(
        bg: up ? BrandColors.ok : BrandColors.accent,
        fg: up ? Colors.black : Colors.white,
        arrow: up ? '▲' : '▼',
        magnitude: delta!.abs(),
      );
    } else {
      badge = _circleBadge(Colors.black, '✗', Colors.white);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (pickedDifferent) ...[
          Text(myLabel!, style: AppText.body(11, weight: FontWeight.w700, color: t.colorScheme.onSurface.withOpacity(0.75))),
          const SizedBox(width: 6),
        ],
        badge,
      ],
    );
  }

  Widget _circleBadge(Color bg, String glyph, Color fg) => Container(
        width: 20,
        height: 20,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        child: Text(glyph, style: TextStyle(color: fg, fontWeight: FontWeight.w900, fontSize: 11)),
      );

  Widget _arrowPill({required Color bg, required Color fg, required String arrow, required int magnitude}) => Container(
        height: 20,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg, borderRadius: const BorderRadius.all(Radius.circular(10))),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(arrow, style: TextStyle(color: fg, fontWeight: FontWeight.w900, fontSize: 9, height: 1.1)),
            const SizedBox(width: 2),
            Text('$magnitude', style: TextStyle(color: fg, fontWeight: FontWeight.w900, fontSize: 11)),
          ],
        ),
      );
}
