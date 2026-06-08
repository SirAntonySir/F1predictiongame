// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import '../../api/models/season.dart';
import '../../components/branded_sheet.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../theme/colors.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import 'f1_tab.dart';
import 'insights_tab.dart';
import 'league_tab.dart';
import 'preseason_tab.dart';

class StandingsScreen extends StatefulWidget {
  final String subTab;
  /// Forwarded to [LeagueTab.initialMetric] so the Home cards' `?sort=` query
  /// param picks the right view. Ignored for non-league sub-tabs.
  final String? leagueSort;
  const StandingsScreen({super.key, this.subTab = 'league', this.leagueSort});

  @override
  State<StandingsScreen> createState() => _StandingsScreenState();
}

class _StandingsScreenState extends State<StandingsScreen> {
  late String _subTab = widget.subTab;
  // null = the current season (no explicit ?season param). A non-null year
  // routes every tab's fetches to that past season.
  int? _selectedSeason;
  List<Season> _seasons = const [];
  bool _loadedSeasons = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loadedSeasons) return;
    _loadedSeasons = true;
    // ignore: discarded_futures
    AppState.of(context).api.seasons().then((s) {
      if (mounted) setState(() => _seasons = s);
    }).catchError((_) {/* leave empty → no switcher shown */});
  }

  int get _currentYear => _seasons.isEmpty
      ? 0
      : _seasons.firstWhere((s) => s.isCurrent, orElse: () => _seasons.first).year;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
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
                  if (_seasons.length > 1) _seasonSwitcher(),
                ],
              ),
            ),
            // Horizontally scrollable so the four pills stay readable on
            // narrow phones (iPhone SE, small Androids). On wider screens the
            // pills hug the left and the user just doesn't notice the scroll.
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(Spacing.xl, Spacing.md, Spacing.xl, Spacing.xs),
              child: Row(children: [
                _tab('league', 'LEAGUE'),
                const SizedBox(width: 6),
                _tab('f1', 'F1'),
                const SizedBox(width: 6),
                _tab('insights', 'INSIGHTS'),
                const SizedBox(width: 6),
                _tab('preseason', 'PRESEASON'),
              ]),
            ),
            Expanded(child: switch (_subTab) {
              'f1' => F1Tab(key: ValueKey(_selectedSeason), season: _selectedSeason),
              'insights' => InsightsTab(key: ValueKey(_selectedSeason), season: _selectedSeason),
              'preseason' => PreseasonTab(key: ValueKey(_selectedSeason), season: _selectedSeason),
              _ => LeagueTab(key: ValueKey(_selectedSeason), initialMetric: widget.leagueSort, season: _selectedSeason),
            }),
          ],
        ),
      ),
    );
  }

  Widget _seasonSwitcher() {
    final t = Theme.of(context);
    final selected = _selectedSeason ?? _currentYear;
    final past = _selectedSeason != null;
    return GestureDetector(
      onTap: _openSeasonSheet,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 5),
        decoration: BoxDecoration(
          // Tint the pill when viewing a past (non-current) season.
          color: past ? BrandColors.accent.withOpacity(0.15) : null,
          border: Border.all(color: past ? BrandColors.accent : t.strokeColor, width: 1.5),
          borderRadius: const BorderRadius.all(Radius.circular(999)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('$selected', style: AppText.label(11, color: t.colorScheme.onSurface)),
          const SizedBox(width: 3),
          Icon(Icons.expand_more, size: 14, color: t.colorScheme.onSurface),
        ]),
      ),
    );
  }

  Future<void> _openSeasonSheet() async {
    final picked = await showBrandedSheet<int>(
      context,
      builder: (ctx) {
        final t = Theme.of(ctx);
        final selected = _selectedSeason ?? _currentYear;
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.sm, Spacing.lg, Spacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: Spacing.md),
                    decoration: BoxDecoration(
                      color: t.colorScheme.onSurface.withOpacity(0.2),
                      borderRadius: const BorderRadius.all(Radius.circular(999)),
                    ),
                  ),
                ),
                Text('Season', style: AppText.display(24, color: t.colorScheme.onSurface)),
                const SizedBox(height: Spacing.md),
                for (final s in _seasons) ...[
                  _seasonOption(ctx, s, isSelected: s.year == selected),
                  const SizedBox(height: Spacing.sm),
                ],
              ],
            ),
          ),
        );
      },
    );
    if (picked != null && mounted) {
      setState(() => _selectedSeason = picked == _currentYear ? null : picked);
    }
  }

  Widget _seasonOption(BuildContext ctx, Season s, {required bool isSelected}) {
    final t = Theme.of(ctx);
    return GestureDetector(
      onTap: () => Navigator.of(ctx).pop(s.year),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? BrandColors.accent.withOpacity(0.12) : null,
          border: Border.all(color: isSelected ? BrandColors.accent : t.strokeColor, width: 1.5),
          borderRadius: const BorderRadius.all(Radius.circular(12)),
        ),
        child: Row(children: [
          Text('${s.year}', style: AppText.display(18, color: t.colorScheme.onSurface)),
          if (s.isCurrent) ...[
            const SizedBox(width: Spacing.sm),
            Text('CURRENT', style: AppText.label(9, color: t.colorScheme.onSurface.withOpacity(0.5))),
          ],
          const Spacer(),
          if (isSelected) const Icon(Icons.check, size: 18, color: BrandColors.accent),
        ]),
      ),
    );
  }

  Widget _tab(String id, String label) {
    final t = Theme.of(context);
    final on = _subTab == id;
    return GestureDetector(
      onTap: () => setState(() => _subTab = id),
      child: Container(
        // Horizontal padding gives each pill consistent thickness now that
        // they're no longer Expanded-stretched to even widths.
        padding: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: 7),
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
