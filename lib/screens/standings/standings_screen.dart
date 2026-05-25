// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../theme/colors.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import 'f1_tab.dart';
import 'insights_tab.dart';
import 'league_tab.dart';

class StandingsScreen extends StatefulWidget {
  final String subTab;
  const StandingsScreen({super.key, this.subTab = 'league'});

  @override
  State<StandingsScreen> createState() => _StandingsScreenState();
}

class _StandingsScreenState extends State<StandingsScreen> {
  late String _subTab = widget.subTab;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final scope = AppState.of(context);
    return Scaffold(
      backgroundColor: t.colorScheme.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Spacing.xl, Spacing.lg, Spacing.xl, Spacing.xs),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Standings'.toUpperCase(), style: AppText.display(28)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 5),
                    decoration: BoxDecoration(
                      border: Border.all(color: t.strokeColor, width: 1.5),
                      borderRadius: const BorderRadius.all(Radius.circular(999)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(color: BrandColors.accent, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${scope.league.league.name} · ${scope.league.league.players.length}',
                        style: AppText.label(11, color: t.colorScheme.onSurface),
                      ),
                    ]),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Spacing.xl, Spacing.md, Spacing.xl, Spacing.xs),
              child: Row(children: [
                Expanded(child: _tab('league', 'LEAGUE')),
                const SizedBox(width: 6),
                Expanded(child: _tab('f1', 'F1')),
                const SizedBox(width: 6),
                Expanded(child: _tab('insights', 'INSIGHTS')),
              ]),
            ),
            Expanded(child: switch (_subTab) {
              'f1' => const F1Tab(),
              'insights' => const InsightsTab(),
              _ => const LeagueTab(),
            }),
          ],
        ),
      ),
    );
  }

  Widget _tab(String id, String label) {
    final t = Theme.of(context);
    final on = _subTab == id;
    return GestureDetector(
      onTap: () => setState(() => _subTab = id),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: on ? t.colorScheme.onSurface : Colors.transparent,
          border: Border.all(color: t.strokeColor, width: 1.5),
          borderRadius: const BorderRadius.all(Radius.circular(8)),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: AppText.label(
            10,
            color: on ? t.colorScheme.surface : t.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}
