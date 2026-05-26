// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import '../../api/models/league_preseason_view.dart';
import '../../api/models/standing.dart';
import '../../components/app_card.dart';
import '../../components/error_view.dart';
import '../../domain/preseason.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../theme/colors.dart';
import '../../theme/team_colors.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';

class PreseasonTab extends StatefulWidget {
  const PreseasonTab({super.key}) : _injected = null, _injectedMyUserId = null;
  const PreseasonTab.withView(LeaguePreseasonView view, {super.key, String? myUserId})
      : _injected = view,
        _injectedMyUserId = myUserId;

  final LeaguePreseasonView? _injected;
  final String? _injectedMyUserId;

  @override
  State<PreseasonTab> createState() => _PreseasonTabState();
}

class _PreseasonData {
  final LeaguePreseasonView view;
  final Map<String, DriverStanding> driverById;
  final Map<String, ConstructorStanding> constructorById;
  const _PreseasonData({
    required this.view,
    required this.driverById,
    required this.constructorById,
  });
}

class _PreseasonTabState extends State<PreseasonTab> {
  Future<_PreseasonData>? _data;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget._injected != null) {
      _data ??= Future.value(_PreseasonData(
        view: widget._injected!,
        driverById: const {},
        constructorById: const {},
      ));
    } else {
      _data ??= _load();
    }
  }

  Future<_PreseasonData> _load() async {
    final scope = AppState.of(context);
    final leagues = scope.auth.leagues;
    if (leagues.isEmpty) {
      throw StateError('No league joined');
    }
    final results = await Future.wait([
      scope.api.leaguePreseason(leagues.first.id),
      scope.api.driverStandings(),
      scope.api.constructorStandings(),
    ]);
    final view = results[0] as LeaguePreseasonView;
    final drivers = results[1] as List<DriverStanding>;
    final constructors = results[2] as List<ConstructorStanding>;
    return _PreseasonData(
      view: view,
      driverById: { for (final d in drivers) d.driverCode: d },
      constructorById: { for (final c in constructors) c.constructorId: c },
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_PreseasonData>(
      future: _data,
      builder: (_, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return ErrorView(
            error: snap.error!,
            stack: snap.stackTrace,
            where: 'Preseason tab',
            onRetry: () => setState(() => _data = _load()),
          );
        }
        return _Body(
          data: snap.data!,
          myUserId: widget._injectedMyUserId ?? AppState.of(context).auth.currentUserId,
        );
      },
    );
  }
}

class _Body extends StatelessWidget {
  final _PreseasonData data;
  final String? myUserId;
  const _Body({required this.data, required this.myUserId});

  LeaguePreseasonView get view => data.view;

  @override
  Widget build(BuildContext context) {
    final standings = view.me.standings;
    final myDriverByPosition = {for (final p in standings.myDriverPicks) p.position: p.driverCode};
    final myTeamByPosition = {for (final p in standings.myConstructorPicks) p.position: p.constructorId};

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
        _h('LEAGUE PRESEASON LEADERBOARD'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
          child: AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < view.leaderboard.length; i++)
                  _LeaderRow(
                    rank: i + 1,
                    row: view.leaderboard[i],
                    isMe: view.leaderboard[i].userId == myUserId,
                  ),
              ],
            ),
          ),
        ),
        _h('YOUR PROJECTIONS'),
        for (final c in view.me.categories)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: 3),
            child: _CategoryCard(card: c),
          ),
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

class _LeaderRow extends StatelessWidget {
  final int rank;
  final LeaguePreseasonLeaderboardRow row;
  final bool isMe;
  const _LeaderRow({required this.rank, required this.row, required this.isMe});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: 10),
      color: isMe ? t.rowHighlight : null,
      child: Row(
        children: [
          SizedBox(width: 22, child: Text('$rank', style: AppText.display(15))),
          const SizedBox(width: 8),
          Expanded(
            child: Text(row.displayName,
                style: AppText.body(13, weight: isMe ? FontWeight.w800 : FontWeight.w700)),
          ),
          Text('+${row.preseasonPointsProjected}',
              style: AppText.display(15, color: isMe ? BrandColors.accent : null)),
        ],
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final CategoryProjectionView card;
  const _CategoryCard({required this.card});

  String _categoryLabel() {
    switch (card.category) {
      case PreseasonCategory.surprise:
        return 'SURPRISE';
      case PreseasonCategory.disappointment:
        return 'DISAPPOINTMENT';
      case PreseasonCategory.dnf:
        return 'MOST DNFs';
      case PreseasonCategory.poles:
        return 'MOST POLES';
      case PreseasonCategory.fastest_lap:
        return 'MOST FASTEST LAPS';
      case PreseasonCategory.wdc_wcc:
        return 'WDC + WCC';
    }
  }

  String _renderPair(PickPairView? p) {
    if (p == null) return '—';
    final parts = <String>[];
    if (p.driverCode != null) parts.add(p.driverCode!);
    if (p.constructorId != null) parts.add(p.constructorId!);
    return parts.isEmpty ? '—' : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final subjective = card.projectedTruth == null;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.md, Spacing.lg, Spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: Text(_categoryLabel(), style: AppText.display(15))),
              Text(subjective ? '— / ${card.max}' : '+${card.projectedPoints} / ${card.max}',
                  style: AppText.label(11, color: t.colorScheme.onSurface.withOpacity(0.6))),
            ],
          ),
          const SizedBox(height: 6),
          _kv('Your pick', _renderPair(card.myPick), t),
          const SizedBox(height: 2),
          _kv('On track', subjective ? 'Set at season end' : _renderPair(card.projectedTruth), t),
        ],
      ),
    );
  }

  Widget _kv(String k, String v, ThemeData t) => Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(k.toUpperCase(),
                style: AppText.label(10, color: t.colorScheme.onSurface.withOpacity(0.55))),
          ),
          Expanded(child: Text(v, style: AppText.body(13, weight: FontWeight.w700))),
        ],
      );
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
/// number. Middle: the driver projected to land in that slot, with team color
/// stripe. Right: the caller's pick for that slot (if any) plus ✓/✗.
class _DriverPositionTile extends StatelessWidget {
  final int position;
  final String projectedCode;
  final String? myCode;
  final DriverStanding? projectedStanding;
  final DriverStanding? myStanding;
  const _DriverPositionTile({
    required this.position,
    required this.projectedCode,
    required this.myCode,
    required this.projectedStanding,
    required this.myStanding,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final correct = myCode != null && myCode == projectedCode;
    final pickedDifferent = myCode != null && myCode != projectedCode;
    return AppCard(
      padding: EdgeInsets.zero,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.sm, Spacing.md, Spacing.sm),
              child: SizedBox(
                width: 30,
                child: Text(
                  position.toString().padLeft(2, '0'),
                  style: AppText.display(22),
                ),
              ),
            ),
            if (projectedStanding != null)
              Container(width: 4, color: teamColor(projectedStanding!.constructorId)),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(projectedCode, style: AppText.display(15)),
                    if (projectedStanding != null) ...[
                      const SizedBox(height: 2),
                      Text(projectedStanding!.driverName,
                          style: AppText.body(11, color: t.colorScheme.onSurface.withOpacity(0.65))),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Spacing.sm, Spacing.sm, Spacing.lg, Spacing.sm),
              child: Align(
                alignment: Alignment.center,
                child: _PickIndicator(
                  myLabel: myCode,
                  correct: correct,
                  pickedDifferent: pickedDifferent,
                ),
              ),
            ),
          ],
        ),
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
  const _TeamPositionTile({
    required this.position,
    required this.projectedId,
    required this.myId,
    required this.projectedStanding,
    required this.myStanding,
  });

  @override
  Widget build(BuildContext context) {
    final correct = myId != null && myId == projectedId;
    final pickedDifferent = myId != null && myId != projectedId;
    return AppCard(
      padding: EdgeInsets.zero,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.sm, Spacing.md, Spacing.sm),
              child: SizedBox(
                width: 30,
                child: Text(
                  position.toString().padLeft(2, '0'),
                  style: AppText.display(22),
                ),
              ),
            ),
            Container(width: 4, color: teamColor(projectedId)),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
                child: Text(
                  projectedStanding?.constructorName ?? projectedId,
                  style: AppText.display(15),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Spacing.sm, Spacing.sm, Spacing.lg, Spacing.sm),
              child: Align(
                alignment: Alignment.center,
                child: _PickIndicator(
                  myLabel: myStanding?.constructorName ?? myId,
                  correct: correct,
                  pickedDifferent: pickedDifferent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickIndicator extends StatelessWidget {
  final String? myLabel;
  final bool correct;
  final bool pickedDifferent;
  const _PickIndicator({required this.myLabel, required this.correct, required this.pickedDifferent});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    if (myLabel == null) {
      return Text('—', style: AppText.label(11, color: t.colorScheme.onSurface.withOpacity(0.4)));
    }
    final (bg, glyph, fg) = correct
        ? (BrandColors.ok, '✓', Colors.black)
        : (Colors.black, '✗', Colors.white);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (pickedDifferent) ...[
          Text(myLabel!, style: AppText.body(11, weight: FontWeight.w700, color: t.colorScheme.onSurface.withOpacity(0.75))),
          const SizedBox(width: 6),
        ],
        Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          child: Text(glyph, style: TextStyle(color: fg, fontWeight: FontWeight.w900, fontSize: 11)),
        ),
      ],
    );
  }
}
