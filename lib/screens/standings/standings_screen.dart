// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import '../../api/models/season.dart';
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
    final scope = AppState.of(context);
    final league = scope.league.league;
    final leagueLabel = league == null
        ? 'No league'
        : '${league.name} · ${league.members.length}';
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
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    if (_seasons.length > 1) ...[_seasonSwitcher(), const SizedBox(width: 8)],
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
                          leagueLabel,
                          style: AppText.label(11, color: t.colorScheme.onSurface),
                        ),
                      ]),
                    ),
                  ]),
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
    return PopupMenuButton<int>(
      tooltip: 'Season',
      position: PopupMenuPosition.under,
      onSelected: (year) =>
          setState(() => _selectedSeason = year == _currentYear ? null : year),
      itemBuilder: (_) => [
        for (final s in _seasons)
          PopupMenuItem<int>(
            value: s.year,
            child: Text(
              s.isCurrent ? '${s.year} · current' : '${s.year}',
              style: AppText.body(13,
                  weight: s.year == selected ? FontWeight.w800 : FontWeight.w500),
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 5),
        decoration: BoxDecoration(
          // Tint the pill when viewing a past (non-current) season.
          color: _selectedSeason != null ? BrandColors.accent.withOpacity(0.15) : null,
          border: Border.all(color: t.strokeColor, width: 1.5),
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
