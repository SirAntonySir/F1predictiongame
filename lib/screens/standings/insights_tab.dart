// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import '../../components/app_card.dart';
import '../../components/fact_card.dart';
import '../../components/trajectory_chart.dart';
import '../../theme/colors.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';

class InsightsTab extends StatelessWidget {
  const InsightsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.only(bottom: Spacing.xxl),
      children: [
        _h('YOUR SEASON'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(child: _stat(t, 'TOTAL POINTS', '148', '3rd of 5', accent: true)),
                  const SizedBox(width: 6),
                  Expanded(child: _stat(t, 'AVERAGE / ROUND', '21.1', 'league avg 19.6')),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(child: _stat(t, 'HIT RATE', '62%', '22 of 35 picks')),
                  const SizedBox(width: 6),
                  Expanded(child: _stat(t, 'BEST ROUND', '+24', 'Imola · R7')),
                ],
              ),
            ],
          ),
        ),
        _h('TRAJECTORY'),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: Spacing.lg),
          child: AppCard(
            child: TrajectoryChart(
              series: [
                ChartSeries(
                  label: 'Lukas',
                  color: Colors.black,
                  points: [0, 25, 50, 75, 100, 125, 150, 167],
                ),
                ChartSeries(
                  label: 'You',
                  color: BrandColors.accent,
                  points: [0, 18, 40, 56, 72, 90, 114, 148],
                ),
                ChartSeries(
                  label: 'Avg',
                  color: Color(0xFFBBBBBB),
                  points: [0, 12, 25, 40, 55, 75, 100, 120],
                ),
              ],
              xLabels: ['R1', 'R2', 'R3', 'R4', 'R5', 'R6', 'R7', 'R8'],
            ),
          ),
        ),
        _h('LEAGUE GOSSIP'),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: Spacing.lg),
          child: Column(children: [
            FactCard(emblem: '★', text: 'Lukas has won 4 of 7 rounds — runaway form.'),
            SizedBox(height: 6),
            FactCard(emblem: '!?', text: "Paul missed last week's pick — first zero of the season."),
            SizedBox(height: 6),
            FactCard(emblem: '≈', text: 'Imola was the closest round: 4-point spread between top 4.'),
          ]),
        ),
      ],
    );
  }

  Widget _h(String s) => Padding(
        padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.lg, Spacing.lg, Spacing.xs),
        child: Text(s, style: AppText.label(11)),
      );

  Widget _stat(ThemeData t, String label, String value, String extra, {bool accent = false}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(Spacing.md, Spacing.sm, Spacing.md, Spacing.sm),
      decoration: BoxDecoration(
        color: accent ? BrandColors.accent : null,
        border: Border.all(color: Colors.black, width: 2),
        borderRadius: const BorderRadius.all(Radius.circular(12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppText.label(
              9,
              color: accent
                  ? Colors.white.withOpacity(0.9)
                  : t.colorScheme.onSurface.withOpacity(0.55),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: AppText.display(24, color: accent ? Colors.white : t.colorScheme.onSurface),
          ),
          Text(
            extra,
            style: AppText.body(
              10,
              color: accent
                  ? Colors.white.withOpacity(0.85)
                  : t.colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }
}
