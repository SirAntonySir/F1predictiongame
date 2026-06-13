// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// Scoring rules reference. Stays in lock-step with the canonical backend
/// engine in `backend/src/scoring/{qualifying,sprintShootout,sprintRace,race}.ts`.
/// If those constants change, update [_rules] below.
class RulesScreen extends StatelessWidget {
  const RulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      backgroundColor: t.colorScheme.surface,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(Spacing.lg),
          children: [
            Row(children: [
              IconButton(
                onPressed: () => context.pop(),
                icon: const Icon(Icons.arrow_back_ios_new, size: 16),
              ),
              Text('Rules'.toUpperCase(), style: AppText.display(24)),
            ]),
            const SizedBox(height: Spacing.sm),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
              child: Text(
                'Score points by predicting how a session ends. Pick the right '
                'drivers in the right order. Exact spots pay the most.',
                style: AppText.body(13,
                    color: t.colorScheme.onSurface.withOpacity(0.7)),
              ),
            ),
            const SizedBox(height: Spacing.xl),

            // Points per session
            Text('POINTS PER SESSION', style: AppText.label(11)),
            const SizedBox(height: Spacing.sm),
            for (final r in _rules) ...[
              _SessionRuleCard(rule: r),
              const SizedBox(height: Spacing.sm),
            ],
            const SizedBox(height: Spacing.lg),

            // Term explainers
            Text('TERMS', style: AppText.label(11)),
            const SizedBox(height: Spacing.sm),
            _TermBox(
              t: t,
              icon: Icons.gps_fixed,
              title: 'Exact',
              body:
                  'Driver finished in the exact position you put them in. Full points.',
            ),
            const SizedBox(height: Spacing.sm),
            _TermBox(
              t: t,
              icon: Icons.swap_horiz,
              title: 'Wrong position',
              body:
                  'Driver finished inside your picked range, but in a different '
                  'slot than you predicted. Partial credit.',
            ),
            const SizedBox(height: Spacing.sm),
            _TermBox(
              t: t,
              icon: Icons.emoji_events_outlined,
              title: 'Team bonus',
              body:
                  'If the constructor of your P1 pick wins the session, you get '
                  "the team-bonus points, even if your P1 driver isn't the one "
                  'who took the top spot.',
            ),
            const SizedBox(height: Spacing.xl),

            // Joker
            Row(
              children: [
                Text('JOKER', style: AppText.label(11)),
                const SizedBox(width: Spacing.sm),
                _ComingSoonPill(t: t),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            _JokerCard(t: t),
            const SizedBox(height: Spacing.xxl),
          ],
        ),
      ),
    );
  }
}

// Rule data. Mirrors the four scoring modules in backend/src/scoring/.

class _SessionRule {
  final String name;
  final String picksLabel;     // e.g. "TOP 5"
  final int picks;
  final int exact;
  final int? wrongPos;         // null if the session has no wrong-pos credit
  final int teamBonus;
  const _SessionRule({
    required this.name,
    required this.picksLabel,
    required this.picks,
    required this.exact,
    required this.wrongPos,
    required this.teamBonus,
  });

  /// Best possible score: every pick exact + team bonus applied.
  int get maxPoints => picks * exact + teamBonus;
}

const _rules = <_SessionRule>[
  _SessionRule(
      name: 'Race',
      picksLabel: 'TOP 5',
      picks: 5,
      exact: 3,
      wrongPos: 1,
      teamBonus: 2),
  _SessionRule(
      name: 'Qualifying',
      picksLabel: 'TOP 2',
      picks: 2,
      exact: 3,
      wrongPos: 1,
      teamBonus: 1),
  _SessionRule(
      name: 'Sprint race',
      picksLabel: 'TOP 3',
      picks: 3,
      exact: 2,
      wrongPos: 1,
      teamBonus: 1),
  _SessionRule(
      name: 'Sprint shootout',
      picksLabel: 'TOP 1',
      picks: 1,
      exact: 1,
      wrongPos: null,
      teamBonus: 1),
];

class _SessionRuleCard extends StatelessWidget {
  final _SessionRule rule;
  const _SessionRuleCard({required this.rule});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        border: Border.all(color: t.strokeColor, width: Strokes.card),
        borderRadius: Radii.rLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(rule.name.toUpperCase(), style: AppText.display(20)),
              const SizedBox(width: Spacing.sm),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  rule.picksLabel,
                  style: AppText.label(10,
                      color: t.colorScheme.onSurface.withOpacity(0.55)),
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: RichText(
                  text: TextSpan(children: [
                    TextSpan(
                      text: 'MAX  ',
                      style: AppText.label(9,
                          color: t.colorScheme.onSurface.withOpacity(0.55)),
                    ),
                    TextSpan(
                      text: '${rule.maxPoints}',
                      style: AppText.display(16,
                          color: t.colorScheme.onSurface),
                    ),
                  ]),
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.md),
          Wrap(
            spacing: Spacing.xs,
            runSpacing: Spacing.xs,
            children: [
              _PointPill(t: t, label: 'EXACT',     value: '+${rule.exact}'),
              if (rule.wrongPos != null)
                _PointPill(t: t, label: 'WRONG POS', value: '+${rule.wrongPos}'),
              _PointPill(t: t, label: 'TEAM',      value: '+${rule.teamBonus}'),
            ],
          ),
        ],
      ),
    );
  }
}

/// Outlined point chip. Label stays muted, only the +N number takes the
/// brand accent, so the cards read calmly at a glance.
class _PointPill extends StatelessWidget {
  final ThemeData t;
  final String label;
  final String value;
  const _PointPill({
    required this.t,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md, vertical: Spacing.xs),
      decoration: BoxDecoration(
        border: Border.all(color: t.strokeColor, width: 1.5),
        borderRadius: Radii.rSm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: AppText.label(10,
                  color: t.colorScheme.onSurface.withOpacity(0.7))),
          const SizedBox(width: Spacing.sm),
          Text(value,
              style: AppText.display(14, color: BrandColors.accent)),
        ],
      ),
    );
  }
}

class _TermBox extends StatelessWidget {
  final ThemeData t;
  final IconData icon;
  final String title;
  final String body;
  const _TermBox({
    required this.t,
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        border: Border.all(color: t.strokeColor, width: Strokes.card),
        borderRadius: Radii.rLg,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon,
                size: 18, color: t.colorScheme.onSurface.withOpacity(0.75)),
          ),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title.toUpperCase(), style: AppText.label(11)),
                const SizedBox(height: Spacing.xxs),
                Text(body,
                    style: AppText.body(13,
                        color: t.colorScheme.onSurface.withOpacity(0.75))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ComingSoonPill extends StatelessWidget {
  final ThemeData t;
  const _ComingSoonPill({required this.t});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: Spacing.sm, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: t.strokeColor, width: 1),
        borderRadius: Radii.rPill,
      ),
      child: Text('COMING SOON',
          style: AppText.label(9,
              color: t.colorScheme.onSurface.withOpacity(0.65))),
    );
  }
}

class _JokerCard extends StatelessWidget {
  final ThemeData t;
  const _JokerCard({required this.t});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        border: Border.all(color: t.strokeColor, width: Strokes.card),
        borderRadius: Radii.rLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.star_outline,
                  size: 18, color: t.colorScheme.onSurface),
              const SizedBox(width: Spacing.sm),
              Text('JOKER', style: AppText.display(18)),
              const Spacer(),
              Text('3 / SEASON',
                  style: AppText.label(10,
                      color: t.colorScheme.onSurface.withOpacity(0.55))),
            ],
          ),
          const SizedBox(height: Spacing.md),
          Text(
            'A safety net for races you miss.',
            style: AppText.body(14, weight: FontWeight.w700),
          ),
          const SizedBox(height: Spacing.xs),
          Text(
            'You have up to 3 jokers per season to spend on race sessions. '
            'A joker copies your picks from the previous race into the current '
            'one, so you still score instead of taking a zero.',
            style: AppText.body(13,
                color: t.colorScheme.onSurface.withOpacity(0.75)),
          ),
          const SizedBox(height: Spacing.lg),
          _JokerRule(
            t: t,
            icon: Icons.bolt,
            title: 'Auto-activates at lock',
            body:
                "If you haven't locked any picks for a race when the lock "
                'closes, one of your remaining jokers is spent automatically.',
          ),
          const SizedBox(height: Spacing.md),
          _JokerRule(
            t: t,
            icon: Icons.refresh,
            title: 'Reuses last race',
            body:
                'The joker fills your race picks with whatever you locked in '
                'for the previous race weekend.',
          ),
          const SizedBox(height: Spacing.md),
          _JokerRule(
            t: t,
            icon: Icons.flag_outlined,
            title: 'Race sessions only',
            body:
                "Jokers don't apply to qualifying, sprint shootout, or sprint "
                'races. Only the main Grand Prix.',
          ),
        ],
      ),
    );
  }
}

class _JokerRule extends StatelessWidget {
  final ThemeData t;
  final IconData icon;
  final String title;
  final String body;
  const _JokerRule({
    required this.t,
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon,
              size: 16, color: t.colorScheme.onSurface.withOpacity(0.7)),
        ),
        const SizedBox(width: Spacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: AppText.body(13, weight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(body,
                  style: AppText.body(12,
                      color: t.colorScheme.onSurface.withOpacity(0.7))),
            ],
          ),
        ),
      ],
    );
  }
}
