// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import '../../api/models/standing.dart';
import '../../components/error_view.dart';
import '../../components/standings_skeleton.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../theme/colors.dart';
import '../../theme/team_colors.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';

// Shared column widths so the driver/constructor headers and rows align.
const double _kPosCol = 24;
const double _kCodeCol = 44;
const double _kPointsCol = 50;

class F1Tab extends StatefulWidget {
  final int? season;
  /// Shared screen-level "refreshing" flag — toggled while a pull-to-refresh
  /// is in flight so the host screen can show a top progress bar.
  final ValueNotifier<bool>? busy;
  const F1Tab({super.key, this.season, this.busy});

  @override
  State<F1Tab> createState() => _F1TabState();
}

class _F1TabState extends State<F1Tab> {
  String _which = 'drivers';
  Future<List<DriverStanding>>? _drivers;
  Future<List<ConstructorStanding>>? _constructors;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final api = AppState.of(context).api;
    _drivers ??= api.driverStandings(season: widget.season);
    _constructors ??= api.constructorStandings(season: widget.season);
  }

  @override
  void dispose() {
    // Don't strand the shared bar on if we're torn down mid-refresh.
    widget.busy?.value = false;
    super.dispose();
  }

  // Re-fetch both standings lists. Stale-while-revalidate: we keep the old
  // futures (and their rendered rows) until the new data has landed, then
  // swap — so the list never flashes back to a skeleton on pull. The shared
  // [busy] flag drives the screen's top progress bar meanwhile. Errors surface
  // through the FutureBuilder's error branch once swapped in.
  Future<void> _refresh() async {
    final api = AppState.of(context).api;
    final drivers = api.driverStandings(season: widget.season);
    final constructors = api.constructorStandings(season: widget.season);
    widget.busy?.value = true;
    try {
      await Future.wait([drivers, constructors]);
    } catch (_) {/* swapped in below; FutureBuilder renders the error */}
    if (!mounted) return;
    setState(() {
      _drivers = drivers;
      _constructors = constructors;
    });
    widget.busy?.value = false;
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.md, Spacing.lg, Spacing.sm),
        child: Row(children: [
          _seg('drivers', 'DRIVERS'),
          _seg('constructors', 'CONSTRUCTORS'),
        ]),
      ),
      Expanded(child: _which == 'drivers' ? _driverList() : _constructorList()),
    ]);
  }

  Widget _seg(String id, String label) {
    final t = Theme.of(context);
    final on = id == _which;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () => setState(() => _which = id),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 6),
          decoration: BoxDecoration(
            color: on ? t.colorScheme.onSurface : null,
            border: Border.all(color: t.strokeColor, width: 1.5),
            borderRadius: const BorderRadius.all(Radius.circular(8)),
          ),
          child: Text(label,
              style: AppText.label(10,
                  color: on ? t.colorScheme.surface : t.colorScheme.onSurface)),
        ),
      ),
    );
  }

  Widget _driverList() => FutureBuilder<List<DriverStanding>>(
        future: _drivers,
        builder: (_, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const StandingsListSkeleton();
          }
          if (snap.hasError) {
            return ErrorView(
              error: snap.error!,
              stack: snap.stackTrace,
              where: 'Standings · F1',
              onRetry: () => setState(() {
                _drivers = null;
                _constructors = null;
              }),
            );
          }
          final t = Theme.of(context);
          final data = snap.data!;
          return RefreshIndicator(
            onRefresh: _refresh,
            color: BrandColors.accent,
            child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: Spacing.md),
            children: [
              _DriverHeader(t: t),
              // One bordered list, internal dividers between rows.
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: t.strokeColor, width: Strokes.card),
                  borderRadius: Radii.rLg,
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: List.generate(data.length, (i) {
                    final d = data[i];
                    final isLast = i == data.length - 1;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: Spacing.sm, vertical: Spacing.sm),
                      decoration: BoxDecoration(
                        border: isLast
                            ? null
                            : Border(
                                bottom: BorderSide(
                                    color: t.strokeColor.withOpacity(0.25),
                                    width: 1),
                              ),
                      ),
                      child: Row(
                        children: [
                          SizedBox(width: _kPosCol, child: Text('${d.position}', style: AppText.display(16))),
                          const SizedBox(width: Spacing.xs),
                          Container(
                            width: 5,
                            height: 28,
                            decoration: BoxDecoration(
                              color: teamColor(d.constructorId),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: Spacing.sm),
                          SizedBox(
                            width: _kCodeCol,
                            child: Text(d.driverCode, style: AppText.body(13, weight: FontWeight.w800)),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(d.driverName, style: AppText.body(13, weight: FontWeight.w600)),
                                Text('${d.wins} wins',
                                    style: AppText.body(10, color: t.colorScheme.onSurface.withOpacity(0.5))),
                              ],
                            ),
                          ),
                          SizedBox(
                            width: _kPointsCol,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('${d.points}', style: AppText.display(18)),
                                Text('pts', style: AppText.label(8, color: t.colorScheme.onSurface.withOpacity(0.6))),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
          );
        },
      );

  Widget _constructorList() => FutureBuilder<List<ConstructorStanding>>(
        future: _constructors,
        builder: (_, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const StandingsListSkeleton();
          }
          if (snap.hasError) {
            return ErrorView(
              error: snap.error!,
              stack: snap.stackTrace,
              where: 'Standings · F1',
              onRetry: () => setState(() {
                _drivers = null;
                _constructors = null;
              }),
            );
          }
          final t = Theme.of(context);
          final data = snap.data!;
          return RefreshIndicator(
            onRefresh: _refresh,
            color: BrandColors.accent,
            child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: Spacing.md),
            children: [
              _ConstructorHeader(t: t),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: t.strokeColor, width: Strokes.card),
                  borderRadius: Radii.rLg,
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: List.generate(data.length, (i) {
                    final c = data[i];
                    final isLast = i == data.length - 1;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: Spacing.sm, vertical: Spacing.sm),
                      decoration: BoxDecoration(
                        border: isLast
                            ? null
                            : Border(
                                bottom: BorderSide(
                                    color: t.strokeColor.withOpacity(0.25),
                                    width: 1),
                              ),
                      ),
                      child: Row(
                        children: [
                          SizedBox(width: _kPosCol, child: Text('${c.position}', style: AppText.display(16))),
                          const SizedBox(width: Spacing.xs),
                          Container(
                            width: 5,
                            height: 28,
                            decoration: BoxDecoration(
                              color: teamColor(c.constructorId),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: Spacing.sm),
                          Expanded(
                            child: Text(
                              c.constructorName,
                              style: AppText.body(13, weight: FontWeight.w700),
                            ),
                          ),
                          SizedBox(
                            width: _kPointsCol,
                            child: Text('${c.points}',
                                style: AppText.display(16),
                                textAlign: TextAlign.right),
                          ),
                        ],
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
          );
        },
      );
}

class _DriverHeader extends StatelessWidget {
  final ThemeData t;
  const _DriverHeader({required this.t});
  @override
  Widget build(BuildContext context) {
    final muted = AppText.label(8, color: t.colorScheme.onSurface.withOpacity(0.55));
    return Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.sm, 0, Spacing.sm, Spacing.xs),
      child: Row(
        children: [
          SizedBox(width: _kPosCol, child: Text('P', style: muted)),
          const SizedBox(width: Spacing.xs),
          const SizedBox(width: 5),
          const SizedBox(width: Spacing.sm),
          SizedBox(width: _kCodeCol, child: Text('CODE', style: muted)),
          Expanded(child: Text('DRIVER', style: muted)),
          SizedBox(width: _kPointsCol, child: Text('PTS', style: muted, textAlign: TextAlign.right)),
        ],
      ),
    );
  }
}

class _ConstructorHeader extends StatelessWidget {
  final ThemeData t;
  const _ConstructorHeader({required this.t});
  @override
  Widget build(BuildContext context) {
    final muted = AppText.label(8, color: t.colorScheme.onSurface.withOpacity(0.55));
    return Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.sm, 0, Spacing.sm, Spacing.xs),
      child: Row(
        children: [
          SizedBox(width: _kPosCol, child: Text('P', style: muted)),
          const SizedBox(width: Spacing.xs),
          const SizedBox(width: 5),
          const SizedBox(width: Spacing.sm),
          Expanded(child: Text('CONSTRUCTOR', style: muted)),
          SizedBox(width: _kPointsCol, child: Text('PTS', style: muted, textAlign: TextAlign.right)),
        ],
      ),
    );
  }
}
