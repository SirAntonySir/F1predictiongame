// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import '../api/models/reference_laps.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/team_colors.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// Two-line driver card for the predict screen reference list.
///
/// Top row per column: lap time for that reference session (muted display).
/// Bottom row per column: three slim sector pills colored by tier.
///
/// The right-hand BEST column holds the driver's fastest lap across the
/// reference sessions in plain text (grey), with a P-badge underneath when
/// the driver is currently picked.
///
/// `referenceLaps` is parallel to the reference-sessions list returned by
/// /api/sessions/:id/reference-laps — each slot is the driver's lap in that
/// session, or null if they weren't in it (or the session hasn't run yet).
class DriverSectorRow extends StatelessWidget {
  final String driverCode;
  final String? constructorId;
  final String? teamColorHex;
  final List<ReferenceLap?> referenceLaps;
  /// 1-indexed pick slot (P1..P5) when this driver is currently picked.
  final int? pickedSlot;
  final VoidCallback? onTap;
  const DriverSectorRow({
    super.key,
    required this.driverCode,
    required this.constructorId,
    required this.teamColorHex,
    required this.referenceLaps,
    required this.pickedSlot,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final team = constructorId == null
        ? t.colorScheme.onSurface.withOpacity(0.3)
        : teamColor(constructorId!, fallbackHex: teamColorHex);

    ReferenceLap? best;
    for (final l in referenceLaps) {
      if (l == null) continue;
      if (best == null || l.lapMs < best.lapMs) best = l;
    }

    final picked = pickedSlot != null;

    return InkWell(
      onTap: onTap,
      borderRadius: Radii.rLg,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: Spacing.sm, vertical: Spacing.xs),
        decoration: BoxDecoration(
          color: picked ? BrandColors.accent.withOpacity(0.6) : null,
          border: Border.all(color: t.strokeColor, width: Strokes.card),
          borderRadius: Radii.rLg,
        ),
        child: Row(
          children: [
            // Inset team-color bar (matches the top P-slot anatomy).
            Container(
              width: 5,
              height: 28,
              decoration: BoxDecoration(
                color: team,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: Spacing.sm),
            // Driver code — fixed-width column so the session times line up
            // across rows.
            SizedBox(
              width: 48,
              child: Text(driverCode,
                  style: AppText.display(16,
                      color: picked ? Colors.white : t.colorScheme.onSurface)),
            ),
            // One column per reference session: lap time on top, 3 slim
            // sector pills below.
            for (final lap in referenceLaps)
              Expanded(child: _SessionColumn(lap: lap, picked: picked)),
            // BEST column.
            SizedBox(
              width: 64,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    best == null ? '—' : _formatLap(best.lapMs),
                    style: AppText.display(14,
                        color: picked
                            ? Colors.white
                            : t.colorScheme.onSurface.withOpacity(0.7)),
                  ),
                  if (picked) ...[
                    const SizedBox(height: 2),
                    _PickedBadge(slot: pickedSlot!),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionColumn extends StatelessWidget {
  final ReferenceLap? lap;
  final bool picked;
  const _SessionColumn({required this.lap, required this.picked});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = picked
        ? Colors.white.withOpacity(0.85)
        : t.colorScheme.onSurface.withOpacity(0.7);
    if (lap == null) {
      return Center(
        child: Text('—', style: AppText.body(13, color: muted)),
      );
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(_formatLap(lap!.lapMs),
            style: AppText.display(11, color: muted)),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            _SectorPill(tier: lap!.s1Ms == null ? null : lap!.s1Tier, picked: picked),
            const SizedBox(width: 2),
            _SectorPill(tier: lap!.s2Ms == null ? null : lap!.s2Tier, picked: picked),
            const SizedBox(width: 2),
            _SectorPill(tier: lap!.s3Ms == null ? null : lap!.s3Tier, picked: picked),
          ],
        ),
      ],
    );
  }
}

class _SectorPill extends StatelessWidget {
  final SectorTier? tier;
  final bool picked;
  const _SectorPill({required this.tier, required this.picked});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final color = tier == null
        ? (picked ? Colors.white.withOpacity(0.35) : t.colorScheme.onSurface.withOpacity(0.2))
        : _colorForTier(tier!, t, picked);
    return Container(
      width: 14,
      height: 5,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2.5),
      ),
    );
  }
}

class _PickedBadge extends StatelessWidget {
  final int slot;
  const _PickedBadge({required this.slot});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text('P$slot',
          style: AppText.label(9, color: BrandColors.accent)),
    );
  }
}

Color _colorForTier(SectorTier tier, ThemeData t, bool picked) {
  // On a picked (red 60%-opacity) background, the violet/green get drowned
  // out — bump to pure white-ish tones so they still read.
  if (picked) {
    return switch (tier) {
      SectorTier.sessionBest => Colors.white,
      SectorTier.personalBest => Colors.white.withOpacity(0.85),
      SectorTier.neutral => Colors.white.withOpacity(0.4),
    };
  }
  return switch (tier) {
    SectorTier.sessionBest => BrandColors.violet,
    SectorTier.personalBest => BrandColors.ok,
    SectorTier.neutral => t.colorScheme.onSurface.withOpacity(0.45),
  };
}

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
