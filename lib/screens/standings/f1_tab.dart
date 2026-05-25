// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import '../../api/models/standing.dart';
import '../../components/app_card.dart';
import '../../components/error_view.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../theme/team_colors.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';

class F1Tab extends StatefulWidget {
  const F1Tab({super.key});

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
    _drivers ??= api.driverStandings();
    _constructors ??= api.constructorStandings();
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
            return const SizedBox.shrink();
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
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: Spacing.md),
            children: [
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: snap.data!.map((d) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 10),
                    child: Row(
                      children: [
                        SizedBox(width: 24, child: Text('${d.position}', style: AppText.display(16))),
                        Container(width: 4, height: 22, color: teamColor(d.constructorId)),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 44,
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
                          width: 42,
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
                  )).toList(),
                ),
              ),
            ],
          );
        },
      );

  Widget _constructorList() => FutureBuilder<List<ConstructorStanding>>(
        future: _constructors,
        builder: (_, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const SizedBox.shrink();
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
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: Spacing.md),
            children: [
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: snap.data!.map((c) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 10),
                    child: Row(
                      children: [
                        SizedBox(width: 24, child: Text('${c.position}', style: AppText.display(16))),
                        Container(width: 4, height: 22, color: teamColor(c.constructorId)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            c.constructorName,
                            style: AppText.body(13, weight: FontWeight.w700),
                          ),
                        ),
                        Text('${c.points}', style: AppText.display(16)),
                      ],
                    ),
                  )).toList(),
                ),
              ),
            ],
          );
        },
      );
}
