// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import '../api/models/event.dart';
import '../domain/race_phase.dart';
import '../theme/colors.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'app_card.dart';
import 'circuit_svg.dart';

// RaceState lives in the domain layer (so the calendar's pure classifier can
// produce it); re-exported here for existing importers of this component.
export '../domain/race_phase.dart' show RaceState;

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
  /// When set, a faint circuit map renders as a background watermark and the
  /// header line uses the flag emoji + country text rendered separately so
  /// the flag can be sized larger than the label text.
  final Event? event;
  final String? flag;

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
    this.event,
    this.flag,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    // Past races read as "done": the round + race-info column fade out so
    // the eye is drawn to the score in the right column (which stays full
    // opacity). Live / next / future tiles render at full strength.
    final pastDim = state == RaceState.past ? 0.45 : 1.0;
    return InkWell(
      onTap: onTap,
      borderRadius: Radii.rLg,
      child: AppCard(
        padding: EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: Radii.rLg,
          child: IntrinsicHeight(
            child: Stack(
              children: [
                if (event != null)
                  Positioned(
                    top: Spacing.sm,
                    right: Spacing.sm,
                    bottom: Spacing.sm,
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: state == RaceState.past ? 0.08 : 0.18,
                        // 'white' variant = single-color stroked paths.
                        // The 'black-outline' variant stacks black outline +
                        // white inner paths; combining that with the srcIn
                        // color filter collapses to an unrenderable silhouette
                        // for some circuits (catalunya was the one that
                        // dropped on device). Home screen uses black-outline
                        // because it passes no color filter.
                        child: CircuitSvg(
                          event: event!,
                          variant: 'white',
                          width: 90,
                          height: 90,
                          color: t.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(width: Spacing.lg),
              Expanded(
                child: Opacity(
                  opacity: pastDim,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: Spacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (flag != null) ...[
                              Text(flag!, style: const TextStyle(fontSize: 16, height: 1)),
                              const SizedBox(width: 6),
                            ],
                            Flexible(
                              child: Text(country.toUpperCase(),
                                  style: AppText.label(10, color: t.colorScheme.onSurface.withOpacity(0.55)),
                                  maxLines: 1, overflow: TextOverflow.fade, softWrap: false),
                            ),
                          ],
                        ),
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
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(0, Spacing.md, Spacing.lg, Spacing.md),
                child: Align(alignment: Alignment.center, child: _rightSide(t)),
              ),
            ],
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
        mainAxisSize: MainAxisSize.min,
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
