// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import '../api/models/reference_laps.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/team_colors.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// Single-line driver card for the predict screen reference list.
///
/// Shows the team-color stripe + driver code, three sector-dot groups (one per
/// reference session, chronological), and the driver's best lap time on the
/// right tinted by the highest tier any of their sectors achieved.
///
/// `referenceLaps` is parallel to the reference-sessions list returned by
/// /api/sessions/:id/reference-laps — each slot is the driver's lap in that
/// session, or null if the driver wasn't in it (or the session hasn't run yet).
class DriverSectorRow extends StatelessWidget {
  final String driverCode;
  final int? driverNumber;
  final String? constructorId;
  final String? teamColorHex;
  final List<ReferenceLap?> referenceLaps;
  /// When non-null, marks the chronological slot whose lap is the driver's
  /// fastest of the three. Drawn as a small star next to the time.
  final int? bestSlot;
  final VoidCallback? onTap;
  const DriverSectorRow({
    super.key,
    required this.driverCode,
    required this.driverNumber,
    required this.constructorId,
    required this.teamColorHex,
    required this.referenceLaps,
    required this.bestSlot,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final team = constructorId == null
        ? t.colorScheme.onSurface.withOpacity(0.3)
        : teamColor(constructorId!, fallbackHex: teamColorHex);

    // Time + tag come from the driver's fastest lap across the slots.
    ReferenceLap? best;
    for (var i = 0; i < referenceLaps.length; i++) {
      final l = referenceLaps[i];
      if (l == null) continue;
      if (best == null || l.lapMs < best.lapMs) best = l;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: Radii.rLg,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          border: Border.all(color: t.strokeColor, width: Strokes.card),
          borderRadius: Radii.rLg,
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            // Team color stripe — left edge.
            Container(width: 4, color: team),
            const SizedBox(width: Spacing.sm),
            // Driver code + number
            SizedBox(
              width: 62,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(driverCode, style: AppText.display(16)),
                  if (driverNumber != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('${driverNumber!}',
                          style: AppText.label(8,
                              color: t.colorScheme.onSurface.withOpacity(0.5))),
                    ),
                ],
              ),
            ),
            // Dot groups, evenly spaced.
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (var i = 0; i < referenceLaps.length; i++)
                    _SectorDotGroup(lap: referenceLaps[i]),
                ],
              ),
            ),
            // Best lap time + source tag
            Padding(
              padding: const EdgeInsets.only(right: Spacing.md),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    best == null ? '—' : _formatLap(best.lapMs),
                    style: AppText.display(14,
                        color: best == null
                            ? t.colorScheme.onSurface.withOpacity(0.4)
                            : _colorForTier(best.lapTier, t)),
                  ),
                  if (bestSlot != null && best != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star,
                              size: 9, color: BrandColors.violet),
                          const SizedBox(width: 2),
                          Text('FAST',
                              style: AppText.label(8,
                                  color: t.colorScheme.onSurface.withOpacity(0.55))),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectorDotGroup extends StatelessWidget {
  final ReferenceLap? lap;
  const _SectorDotGroup({required this.lap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    if (lap == null) {
      return Text('—',
          style: AppText.label(11,
              color: t.colorScheme.onSurface.withOpacity(0.25)));
    }
    final tiers = [lap!.s1Tier, lap!.s2Tier, lap!.s3Tier];
    final present = [lap!.s1Ms != null, lap!.s2Ms != null, lap!.s3Ms != null];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          _SectorDot(tier: present[i] ? tiers[i] : null),
        ],
      ],
    );
  }
}

class _SectorDot extends StatelessWidget {
  final SectorTier? tier;
  const _SectorDot({required this.tier});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final color = tier == null
        ? t.colorScheme.onSurface.withOpacity(0.15)
        : _colorForTier(tier!, t);
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}

Color _colorForTier(SectorTier tier, ThemeData t) => switch (tier) {
      SectorTier.sessionBest => BrandColors.violet,
      SectorTier.personalBest => BrandColors.ok,
      SectorTier.neutral => t.colorScheme.onSurface.withOpacity(0.55),
    };

String _formatLap(int ms) {
  final totalSec = ms ~/ 1000;
  final mins = totalSec ~/ 60;
  final secs = totalSec % 60;
  final millis = ms % 1000;
  final s = secs.toString().padLeft(2, '0');
  final m = millis.toString().padLeft(3, '0');
  if (mins == 0) return '$secs.$m';
  return '$mins:$s.$m';
}
