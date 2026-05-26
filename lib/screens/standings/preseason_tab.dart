// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import '../../api/models/league_preseason_view.dart';
import '../../components/app_card.dart';
import '../../components/error_view.dart';
import '../../domain/preseason.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../theme/colors.dart';
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

class _PreseasonTabState extends State<PreseasonTab> {
  Future<LeaguePreseasonView>? _data;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget._injected != null) {
      _data ??= Future.value(widget._injected);
    } else {
      _data ??= _load();
    }
  }

  Future<LeaguePreseasonView> _load() async {
    final scope = AppState.of(context);
    final leagues = scope.auth.leagues;
    if (leagues.isEmpty) {
      throw StateError('No league joined');
    }
    return scope.api.leaguePreseason(leagues.first.id);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<LeaguePreseasonView>(
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
          view: snap.data!,
          myUserId: widget._injectedMyUserId ?? AppState.of(context).auth.currentUserId,
        );
      },
    );
  }
}

class _Body extends StatelessWidget {
  final LeaguePreseasonView view;
  final String? myUserId;
  const _Body({required this.view, required this.myUserId});

  @override
  Widget build(BuildContext context) {
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
          child: _StandingsCard(standings: view.me.standings),
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

class _StandingsCard extends StatelessWidget {
  final StandingsProjectionView standings;
  const _StandingsCard({required this.standings});

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
