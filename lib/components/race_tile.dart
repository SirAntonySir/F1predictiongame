// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'app_card.dart';

enum RaceState { past, next, live, future }

class RaceTile extends StatelessWidget {
  final int round;
  final String country;
  final String name;
  final String when;
  final RaceState state;
  final int? pointsScored;
  final List<bool>? pickHits;
  final bool sprint;
  final String? distanceFromNow;
  final VoidCallback? onTap;

  const RaceTile({
    super.key,
    required this.round,
    required this.country,
    required this.name,
    required this.when,
    required this.state,
    this.pointsScored,
    this.pickHits,
    this.sprint = false,
    this.distanceFromNow,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final stripeColor = state == RaceState.live ? BrandColors.live : null;
    return InkWell(
      onTap: onTap,
      borderRadius: Radii.rLg,
      child: AppCard(
        padding: EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: Radii.rLg,
          child: IntrinsicHeight(
            child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (stripeColor != null)
                Container(width: 5, color: stripeColor),
              Padding(
                padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.md, Spacing.lg, Spacing.md),
                child: Text(
                  round.toString().padLeft(2, '0'),
                  style: AppText.display(28),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Spacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(country.toUpperCase(),
                          style: AppText.label(10, color: t.colorScheme.onSurface.withOpacity(0.55))),
                      const SizedBox(height: Spacing.xxs),
                      Text(
                        name.toUpperCase(),
                        style: AppText.display(16).copyWith(
                          decoration: state == RaceState.past ? TextDecoration.lineThrough : null,
                          decorationColor: Colors.black26,
                        ),
                      ),
                      const SizedBox(height: Spacing.xxs),
                      Text(when, style: AppText.body(11, color: t.colorScheme.onSurface.withOpacity(0.7))),
                      if (pickHits != null) ...[
                        const SizedBox(height: 5),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: pickHits!
                              .map((hit) => Container(
                                    margin: const EdgeInsets.only(right: 3),
                                    width: 7,
                                    height: 7,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: hit ? BrandColors.ok : BrandColors.accent,
                                    ),
                                  ))
                              .toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(0, Spacing.md, Spacing.lg, Spacing.md),
                child: _rightSide(t),
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }

  Widget _rightSide(ThemeData t) {
    if (state == RaceState.next) {
      return _badge('NEXT', Colors.black, Colors.white);
    }
    if (state == RaceState.live) {
      return _badge('LIVE', BrandColors.live, Colors.white);
    }
    if (pointsScored != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('+$pointsScored', style: AppText.display(18)),
          Text('pts', style: AppText.label(9, color: t.colorScheme.onSurface.withOpacity(0.6))),
        ],
      );
    }
    if (distanceFromNow != null) {
      return Text(distanceFromNow!, style: AppText.body(11, color: t.colorScheme.onSurface.withOpacity(0.5)));
    }
    return const SizedBox.shrink();
  }

  Widget _badge(String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: Spacing.xxs),
        decoration: BoxDecoration(color: bg, borderRadius: const BorderRadius.all(Radius.circular(6))),
        child: Text(text, style: AppText.label(10, color: fg)),
      );
}
