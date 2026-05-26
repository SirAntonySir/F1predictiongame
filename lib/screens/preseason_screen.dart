// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../api/models/standing.dart';
import '../components/app_card.dart';
import '../components/countdown.dart';
import '../components/error_view.dart';
import '../domain/preseason.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/team_colors.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

class PreseasonScreen extends StatefulWidget {
  const PreseasonScreen({super.key});

  @override
  State<PreseasonScreen> createState() => _PreseasonScreenState();
}

class _PreseasonScreenState extends State<PreseasonScreen> {
  Future<_PreData>? _data;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _data ??= _load();
  }

  Future<_PreData> _load() async {
    final scope = AppState.of(context);
    // Refresh server-side state first so locks/picks reflect the latest backend.
    await scope.preseason.refresh();
    final results = await Future.wait([
      scope.api.driverStandings(),
      scope.api.constructorStandings(),
    ]);
    final drivers = results[0] as List<DriverStanding>;
    final constructors = results[1] as List<ConstructorStanding>;
    drivers.sort((a, b) => a.position.compareTo(b.position));
    constructors.sort((a, b) => a.position.compareTo(b.position));
    final mine = scope.preseason.mine;
    return _PreData(
      drivers: drivers,
      constructors: constructors,
      locksAt: mine?.locksAt,
      seasonYear: mine?.seasonYear ?? DateTime.now().year,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final scope = AppState.of(context);
    return Scaffold(
      backgroundColor: t.colorScheme.surface,
      body: SafeArea(
        child: FutureBuilder<_PreData>(
          future: _data,
          builder: (_, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const SizedBox.shrink();
            }
            if (snap.hasError) {
              return ErrorView(
                error: snap.error!,
                stack: snap.stackTrace,
                where: 'Preseason',
                onRetry: () {
                  setState(() {
                    _data = _load();
                  });
                },
              );
            }
            final d = snap.data!;
            final locked = scope.preseason.isLocked;
            return ListenableBuilder(
              listenable: scope.preseason,
              builder: (_, __) => CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _header(d, locked, t, context)),
                  SliverToBoxAdapter(
                      child: _filledSummary(d, scope, locked, t)),
                  for (final cat in PreseasonCategory.values)
                    SliverToBoxAdapter(
                      child: _categoryCard(cat, d, scope, locked, t),
                    ),
                  SliverToBoxAdapter(
                      child: _standingsCard(d, scope, locked, t, context)),
                  const SliverToBoxAdapter(child: SizedBox(height: Spacing.xxl)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ---- header --------------------------------------------------------------

  Widget _header(_PreData d, bool locked, ThemeData t, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          Spacing.lg, Spacing.lg, Spacing.lg, Spacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          IconButton(
            onPressed: () =>
                context.canPop() ? context.pop() : context.go('/home'),
            icon: const Icon(Icons.arrow_back_ios_new, size: 16),
            padding: EdgeInsets.zero,
            constraints:
                const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('PRE-SEASON', style: AppText.label(11)),
                Text('Make your bets', style: AppText.display(24)),
              ],
            ),
          ),
          _lockChip(d.locksAt, locked, t),
        ],
      ),
    );
  }

  Widget _lockChip(DateTime? locksAt, bool locked, ThemeData t) {
    if (locked) {
      return Container(
        padding:
            const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 5),
        decoration: const BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.all(Radius.circular(999)),
        ),
        child: Text('LOCKED',
            style: AppText.label(10, color: Colors.white)),
      );
    }
    if (locksAt == null) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 5),
      decoration: BoxDecoration(
        border: Border.all(color: BrandColors.accent, width: 1.5),
        borderRadius: const BorderRadius.all(Radius.circular(999)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('LOCKS',
              style: AppText.label(9, color: BrandColors.accent)),
          const SizedBox(width: 6),
          Countdown(target: locksAt, size: 14),
        ],
      ),
    );
  }

  Widget _filledSummary(
      _PreData d, scope, bool locked, ThemeData t) {
    int filled = 0;
    for (final cat in PreseasonCategory.values) {
      final pick = scope.preseason.pickFor(cat);
      if (!pick.isEmpty) filled++;
    }
    final orderedDrivers = scope.preseason.driverOrdering();
    final orderedTeams = scope.preseason.constructorOrdering();
    final hasOrdering =
        orderedDrivers.isNotEmpty || orderedTeams.isNotEmpty;
    final progressTotal = PreseasonCategory.values.length + 1; // 6 + 1 ordering
    final progressDone = filled + (hasOrdering ? 1 : 0);
    final maxPts = preseasonMaxPoints(
      driverCount: d.drivers.length,
      constructorCount: d.constructors.length,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: Spacing.lg, vertical: Spacing.xs),
      child: AppCard(
        background: t.mutedSurface,
        padding: const EdgeInsets.symmetric(
            horizontal: Spacing.lg, vertical: Spacing.md),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('PROGRESS', style: AppText.label(10)),
                  const SizedBox(height: 4),
                  Text('$progressDone / $progressTotal categories',
                      style: AppText.body(13, weight: FontWeight.w700)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('MAX (${d.seasonYear})', style: AppText.label(10)),
                const SizedBox(height: 4),
                Text('$maxPts pts',
                    style: AppText.body(13, weight: FontWeight.w700)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---- category card -------------------------------------------------------

  Widget _categoryCard(
      PreseasonCategory cat, _PreData d, scope, bool locked, ThemeData t) {
    final meta = preseasonMeta[cat]!;
    final pick = scope.preseason.pickFor(cat);
    final driver = pick.driverCode == null
        ? null
        : d.drivers.firstWhere(
            (e) => e.driverCode == pick.driverCode,
            orElse: () => DriverStanding(
              position: 0,
              driverCode: pick.driverCode!,
              driverName: pick.driverCode!,
              constructorId: 'unknown',
              points: 0,
              wins: 0,
            ),
          );
    final team = pick.constructorId == null
        ? null
        : d.constructors.firstWhere(
            (e) => e.constructorId == pick.constructorId,
            orElse: () => ConstructorStanding(
              position: 0,
              constructorId: pick.constructorId!,
              constructorName: pick.constructorId!,
              points: 0,
              wins: 0,
            ),
          );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          Spacing.lg, Spacing.xs, Spacing.lg, Spacing.xs),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(
            Spacing.lg, Spacing.md, Spacing.lg, Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  constraints: const BoxConstraints(minWidth: 32),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 4),
                  decoration: const BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.all(Radius.circular(6)),
                  ),
                  alignment: Alignment.center,
                  child: Text(meta.emblem,
                      style: AppText.display(13, color: Colors.white)),
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text(meta.title.toUpperCase(),
                      style: AppText.display(16)),
                ),
                Text('${meta.max} pts',
                    style: AppText.label(10,
                        color: t.colorScheme.onSurface.withOpacity(0.6))),
              ],
            ),
            const SizedBox(height: 4),
            Text(meta.subtitle,
                style: AppText.body(11,
                    color: t.colorScheme.onSurface.withOpacity(0.65))),
            const SizedBox(height: Spacing.md),
            Row(
              children: [
                Expanded(
                  child: _slotButton(
                    label: 'DRIVER',
                    selected: driver == null
                        ? null
                        : _SlotValue(
                            primary: driver.driverCode,
                            secondary: driver.driverName,
                            stripeColor: teamColor(driver.constructorId),
                          ),
                    enabled: !locked,
                    onTap: () async {
                      final pickedCode = await _pickDriver(d.drivers);
                      if (pickedCode == null) return;
                      await scope.preseason.setSinglePick(
                        cat,
                        driverCode: pickedCode,
                        constructorId: pick.constructorId,
                      );
                    },
                    onClear: pick.driverCode == null || locked
                        ? null
                        : () async {
                            if (pick.constructorId != null) {
                              await scope.preseason.setSinglePick(
                                cat,
                                driverCode: null,
                                constructorId: pick.constructorId,
                              );
                            } else {
                              await scope.preseason.deleteSinglePick(cat);
                            }
                          },
                    t: t,
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: _slotButton(
                    label: 'TEAM',
                    selected: team == null
                        ? null
                        : _SlotValue(
                            primary: team.constructorName,
                            secondary: null,
                            stripeColor: teamColor(team.constructorId),
                          ),
                    enabled: !locked,
                    onTap: () async {
                      final pickedId = await _pickConstructor(d.constructors);
                      if (pickedId == null) return;
                      await scope.preseason.setSinglePick(
                        cat,
                        driverCode: pick.driverCode,
                        constructorId: pickedId,
                      );
                    },
                    onClear: pick.constructorId == null || locked
                        ? null
                        : () async {
                            if (pick.driverCode != null) {
                              await scope.preseason.setSinglePick(
                                cat,
                                driverCode: pick.driverCode,
                                constructorId: null,
                              );
                            } else {
                              await scope.preseason.deleteSinglePick(cat);
                            }
                          },
                    t: t,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _slotButton({
    required String label,
    required _SlotValue? selected,
    required bool enabled,
    required VoidCallback onTap,
    required VoidCallback? onClear,
    required ThemeData t,
  }) {
    final filled = selected != null;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.fromLTRB(0, Spacing.sm, Spacing.sm, Spacing.sm),
        decoration: BoxDecoration(
          border: Border.all(color: t.strokeColor, width: 1.5),
          borderRadius: const BorderRadius.all(Radius.circular(10)),
        ),
        child: Row(
          children: [
            Container(
              width: 5,
              height: 36,
              color: filled ? selected.stripeColor : Colors.transparent,
            ),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label,
                      style: AppText.label(9,
                          color: t.colorScheme.onSurface.withOpacity(0.55))),
                  const SizedBox(height: 2),
                  if (filled) ...[
                    Text(selected.primary,
                        style: AppText.body(13, weight: FontWeight.w800)),
                    if (selected.secondary != null)
                      Text(selected.secondary!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.body(10,
                              color: t.colorScheme.onSurface
                                  .withOpacity(0.55))),
                  ] else
                    Text('Tap to pick',
                        style: AppText.body(12,
                                color: t.colorScheme.onSurface
                                    .withOpacity(0.4))
                            .copyWith(fontStyle: FontStyle.italic)),
                ],
              ),
            ),
            if (filled && enabled && onClear != null)
              GestureDetector(
                onTap: onClear,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close, size: 14),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---- standings drill-down ------------------------------------------------

  Widget _standingsCard(_PreData d, scope, bool locked, ThemeData t,
      BuildContext context) {
    final driverCount = scope.preseason.driverOrdering().length;
    final teamCount = scope.preseason.constructorOrdering().length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          Spacing.lg, Spacing.xs, Spacing.lg, Spacing.xs),
      child: AppCard(
        background: BrandColors.accent,
        padding: const EdgeInsets.fromLTRB(
            Spacing.lg, Spacing.md, Spacing.lg, Spacing.md),
        child: DefaultTextStyle.merge(
          style: const TextStyle(color: Colors.white),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    constraints: const BoxConstraints(minWidth: 32),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 4),
                    decoration: const BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.all(Radius.circular(6)),
                    ),
                    alignment: Alignment.center,
                    child: Text('1·N',
                        style:
                            AppText.display(13, color: Colors.white)),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: Text('COMPLETE CHAMPIONSHIP',
                        style: AppText.display(16, color: Colors.white)),
                  ),
                  Text(
                      '${d.drivers.length * preseasonPointsPerDriverSlot + d.constructors.length * preseasonPointsPerConstructorSlot} pts',
                      style: AppText.label(10,
                          color: Colors.white.withOpacity(0.85))),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Order all drivers and teams. $preseasonPointsPerDriverSlot pts per exact driver slot, $preseasonPointsPerConstructorSlot pts per team slot.',
                style: AppText.body(11,
                    color: Colors.white.withOpacity(0.85)),
              ),
              const SizedBox(height: Spacing.md),
              Row(
                children: [
                  Expanded(
                    child: _standingsButton(
                      label: 'DRIVERS',
                      filledCount: driverCount,
                      total: d.drivers.length,
                      onTap: () =>
                          context.push('/preseason/standings/drivers'),
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: _standingsButton(
                      label: 'TEAMS',
                      filledCount: teamCount,
                      total: d.constructors.length,
                      onTap: () =>
                          context.push('/preseason/standings/constructors'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _standingsButton({
    required String label,
    required int filledCount,
    required int total,
    required VoidCallback onTap,
  }) {
    final filled = filledCount > 0;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 10),
        decoration: BoxDecoration(
          color: filled ? Colors.black : Colors.transparent,
          border: Border.all(color: Colors.white, width: 1.5),
          borderRadius: const BorderRadius.all(Radius.circular(10)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: AppText.label(11, color: Colors.white)),
            ),
            Text(filled ? '$filledCount / $total' : 'ORDER ›',
                style: AppText.label(10, color: Colors.white)),
          ],
        ),
      ),
    );
  }

  // ---- pickers -------------------------------------------------------------

  Future<String?> _pickDriver(List<DriverStanding> drivers) async {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => _DriverPickerSheet(drivers: drivers),
    );
  }

  Future<String?> _pickConstructor(
      List<ConstructorStanding> constructors) async {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => _ConstructorPickerSheet(constructors: constructors),
    );
  }
}

class _SlotValue {
  final String primary;
  final String? secondary;
  final Color stripeColor;
  const _SlotValue({
    required this.primary,
    required this.secondary,
    required this.stripeColor,
  });
}

class _PreData {
  final List<DriverStanding> drivers;
  final List<ConstructorStanding> constructors;
  final DateTime? locksAt;
  final int seasonYear;
  _PreData({
    required this.drivers,
    required this.constructors,
    required this.locksAt,
    required this.seasonYear,
  });
}

class _DriverPickerSheet extends StatelessWidget {
  final List<DriverStanding> drivers;
  const _DriverPickerSheet({required this.drivers});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            Spacing.lg, Spacing.lg, Spacing.lg, Spacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('PICK A DRIVER', style: AppText.label(11)),
            const SizedBox(height: Spacing.sm),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.65,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: drivers.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  color: t.strokeColor.withOpacity(0.1),
                ),
                itemBuilder: (_, i) {
                  final d = drivers[i];
                  return InkWell(
                    onTap: () => Navigator.of(context).pop(d.driverCode),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 10),
                      child: Row(
                        children: [
                          Container(
                              width: 4,
                              height: 22,
                              color: teamColor(d.constructorId)),
                          const SizedBox(width: Spacing.sm),
                          SizedBox(
                            width: 44,
                            child: Text(d.driverCode,
                                style: AppText.body(13,
                                    weight: FontWeight.w800)),
                          ),
                          Expanded(
                            child: Text(d.driverName,
                                style: AppText.body(13,
                                    weight: FontWeight.w600)),
                          ),
                          Text('${d.position}',
                              style: AppText.label(10,
                                  color: t.colorScheme.onSurface
                                      .withOpacity(0.5))),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConstructorPickerSheet extends StatelessWidget {
  final List<ConstructorStanding> constructors;
  const _ConstructorPickerSheet({required this.constructors});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            Spacing.lg, Spacing.lg, Spacing.lg, Spacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('PICK A TEAM', style: AppText.label(11)),
            const SizedBox(height: Spacing.sm),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.65,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: constructors.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  color: t.strokeColor.withOpacity(0.1),
                ),
                itemBuilder: (_, i) {
                  final c = constructors[i];
                  return InkWell(
                    onTap: () => Navigator.of(context).pop(c.constructorId),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 12),
                      child: Row(
                        children: [
                          Container(
                              width: 4,
                              height: 22,
                              color: teamColor(c.constructorId)),
                          const SizedBox(width: Spacing.sm),
                          Expanded(
                            child: Text(c.constructorName,
                                style: AppText.body(13,
                                    weight: FontWeight.w700)),
                          ),
                          Text('${c.position}',
                              style: AppText.label(10,
                                  color: t.colorScheme.onSurface
                                      .withOpacity(0.5))),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
