// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../api/models/standing.dart';
import '../components/app_card.dart';
import '../components/branded_toast.dart';
import '../components/error_view.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/team_colors.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

class PreseasonStandingsScreen extends StatefulWidget {
  final String kind; // 'drivers' or 'constructors'
  const PreseasonStandingsScreen({super.key, required this.kind});

  @override
  State<PreseasonStandingsScreen> createState() =>
      _PreseasonStandingsScreenState();
}

class _PreseasonStandingsScreenState extends State<PreseasonStandingsScreen> {
  Future<_LoadedData>? _data;
  List<String> _ordering = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _data ??= _load();
  }

  bool get _isDrivers => widget.kind == 'drivers';

  Future<_LoadedData> _load() async {
    final scope = AppState.of(context);
    await scope.preseason.refresh();
    if (_isDrivers) {
      final drivers = await scope.api.driverStandings();
      drivers.sort((a, b) => a.position.compareTo(b.position));
      final existing = scope.preseason.driverOrdering();
      _ordering = existing.isNotEmpty
          ? List<String>.from(existing)
          : drivers.map((d) => d.driverCode).toList();
      return _LoadedData(driverPool: drivers);
    } else {
      final constructors = await scope.api.constructorStandings();
      constructors.sort((a, b) => a.position.compareTo(b.position));
      final existing = scope.preseason.constructorOrdering();
      _ordering = existing.isNotEmpty
          ? List<String>.from(existing)
          : constructors.map((c) => c.constructorId).toList();
      return _LoadedData(constructorPool: constructors);
    }
  }

  Future<void> _save() async {
    final scope = AppState.of(context);
    try {
      if (_isDrivers) {
        await scope.preseason.setDriverOrdering(_ordering);
      } else {
        await scope.preseason.setConstructorOrdering(_ordering);
      }
    } catch (_) {
      if (mounted) {
        BrandedToast.show(context, "Couldn't save", tone: ToastTone.error);
      }
      return;
    }
    if (mounted) {
      BrandedToast.show(
        context,
        _isDrivers ? 'Driver order saved' : 'Team order saved',
        tone: ToastTone.ok,
      );
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      backgroundColor: t.colorScheme.surface,
      body: SafeArea(
        child: FutureBuilder<_LoadedData>(
          future: _data,
          builder: (_, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const SizedBox.shrink();
            }
            if (snap.hasError) {
              return ErrorView(
                error: snap.error!,
                stack: snap.stackTrace,
                where: 'Preseason · ${widget.kind}',
                onRetry: () {
                  setState(() {
                    _data = _load();
                  });
                },
              );
            }
            final data = snap.data!;
            final label = _isDrivers ? 'DRIVERS' : 'TEAMS';
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      Spacing.lg, Spacing.lg, Spacing.lg, Spacing.sm),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => context.canPop()
                            ? context.pop()
                            : context.go('/preseason'),
                        icon: const Icon(Icons.arrow_back_ios_new, size: 16),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                            minWidth: 32, minHeight: 32),
                      ),
                      const SizedBox(width: Spacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('ORDER · $label', style: AppText.label(11)),
                            Text(
                              _isDrivers
                                  ? 'Drag drivers into order'
                                  : 'Drag teams into order',
                              style: AppText.display(22),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.lg, vertical: Spacing.xs),
                  child: AppCard(
                    background: t.mutedSurface,
                    padding: const EdgeInsets.symmetric(
                        horizontal: Spacing.md, vertical: Spacing.sm),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, size: 14),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _isDrivers
                                ? '3 pts for each driver in the right slot at season end.'
                                : '4 pts for each team in the right slot at season end.',
                            style: AppText.body(11,
                                color:
                                    t.colorScheme.onSurface.withOpacity(0.7)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: Spacing.lg, vertical: Spacing.sm),
                    child: AppCard(
                      padding: EdgeInsets.zero,
                      child: ReorderableListView.builder(
                        proxyDecorator: (child, _, __) => Material(
                          color: BrandColors.accent.withOpacity(0.08),
                          child: child,
                        ),
                        buildDefaultDragHandles: false,
                        itemCount: _ordering.length,
                        onReorder: (oldIdx, newIdx) {
                          setState(() {
                            if (newIdx > oldIdx) newIdx--;
                            final item = _ordering.removeAt(oldIdx);
                            _ordering.insert(newIdx, item);
                          });
                        },
                        itemBuilder: (_, i) {
                          final id = _ordering[i];
                          if (_isDrivers) {
                            final d = data.driverPool!.firstWhere(
                              (e) => e.driverCode == id,
                              orElse: () => DriverStanding(
                                position: 0,
                                driverCode: id,
                                driverName: id,
                                constructorId: 'unknown',
                                points: 0,
                                wins: 0,
                              ),
                            );
                            return _driverRow(i, d, t);
                          } else {
                            final c = data.constructorPool!.firstWhere(
                              (e) => e.constructorId == id,
                              orElse: () => ConstructorStanding(
                                position: 0,
                                constructorId: id,
                                constructorName: id,
                                points: 0,
                                wins: 0,
                              ),
                            );
                            return _constructorRow(i, c, t);
                          }
                        },
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      Spacing.lg, Spacing.sm, Spacing.lg, Spacing.lg),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: BrandColors.accent,
                        foregroundColor: Colors.white,
                        padding:
                            const EdgeInsets.symmetric(vertical: Spacing.md),
                        shape: const RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.all(Radius.circular(12)),
                        ),
                      ),
                      child: Text(
                        'SAVE ORDER',
                        style: AppText.label(13, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _driverRow(int index, DriverStanding d, ThemeData t) {
    return Container(
      key: ValueKey('drv-${d.driverCode}'),
      padding:
          const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
              color: t.strokeColor.withOpacity(0.08), width: 1),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text('${index + 1}', style: AppText.display(16)),
          ),
          Container(
              width: 4, height: 22, color: teamColor(d.constructorId)),
          const SizedBox(width: 10),
          SizedBox(
            width: 44,
            child: Text(d.driverCode,
                style: AppText.body(13, weight: FontWeight.w800)),
          ),
          Expanded(
            child: Text(d.driverName,
                style: AppText.body(13, weight: FontWeight.w600)),
          ),
          ReorderableDragStartListener(
            index: index,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Icon(Icons.drag_handle, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _constructorRow(int index, ConstructorStanding c, ThemeData t) {
    return Container(
      key: ValueKey('con-${c.constructorId}'),
      padding:
          const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
              color: t.strokeColor.withOpacity(0.08), width: 1),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text('${index + 1}', style: AppText.display(16)),
          ),
          Container(
              width: 4, height: 22, color: teamColor(c.constructorId)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(c.constructorName,
                style: AppText.body(13, weight: FontWeight.w700)),
          ),
          ReorderableDragStartListener(
            index: index,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Icon(Icons.drag_handle, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadedData {
  final List<DriverStanding>? driverPool;
  final List<ConstructorStanding>? constructorPool;
  _LoadedData({this.driverPool, this.constructorPool});
}
