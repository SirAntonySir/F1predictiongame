// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import '../../avatar/avatar_config.dart';
import '../../avatar/avatar_palette.dart';
import '../../avatar/avatar_render.dart';
import '../../theme/typography.dart';
import '../avatar_thumbnail.dart';
import 'podium_data.dart';

// Medal tints — local to the podium (not part of the brand scale).
const _gold = Color(0xFFF2B33A);
const _silver = Color(0xFFC9D2DA);
const _bronze = Color(0xFFD07A44);

/// The three-bust results podium stage.
///
/// Winner ([AvatarPose.pose1]) stands front-and-centre at full scale; the
/// runner-up ([AvatarPose.pose2]) sits to the left and the third-place figure
/// (pose2 mirrored) to the right — both scaled down and tucked behind the
/// winner so they read as a stepped podium. A bottom gradient scrim carries
/// each figure's medal, name, and points.
class ResultsPodium extends StatelessWidget {
  final PodiumData data;
  const ResultsPodium({super.key, required this.data});

  PodiumEntry? _byRank(int rank) {
    for (final e in data.entries) {
      if (e.rank == rank) return e;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final first = _byRank(1);
    final second = _byRank(2);
    final third = _byRank(3);

    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      const stageH = 340.0;
      const labelZone = 74.0;
      const figureH = stageH - labelZone;
      const sideH = figureH * 0.8;
      final firstW = w * 0.52;
      final sideW = w * 0.46;
      // The winner's chest (livery) colour drives the spotlight glow.
      final glowColor = first == null
          ? _gold
          : AvatarRegion.chest
              .swatchFor(AvatarConfig.fromJson(first.avatarConfig).ops);

      // Full-body figure. bottomFade off so boots stay visible — the stage
      // scrim below handles grounding the figures into the labels.
      Widget bust(PodiumEntry e,
              {required double width,
              required double height,
              required AvatarPose pose,
              required bool mirror,
              required bool winner}) =>
          SizedBox(
            width: width,
            height: height,
            child: AvatarBust(
              configJson: e.avatarConfig,
              forcePose: pose,
              mirror: mirror,
              crop: AvatarCrop.full,
              bottomFade: false,
              resolution: winner ? 340 : 260,
            ),
          );

      return SizedBox(
        width: w,
        height: stageH,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            // Intense spotlight behind the winner, in their livery colour.
            Positioned(
              top: -stageH * 0.2,
              child: IgnorePointer(
                child: Container(
                  width: firstW * 2.0,
                  height: firstW * 2.0,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        glowColor.withOpacity(0.55),
                        glowColor.withOpacity(0.25),
                        glowColor.withOpacity(0.0),
                      ],
                      stops: const [0.0, 0.15, 0.78],
                    ),
                  ),
                ),
              ),
            ),

            // 2nd — left, tucked inward + behind. Opacity (not a darkening
            // filter) so it recedes toward the sheet surface in BOTH light and
            // dark themes — a fixed darken would make it stand out on white.
            if (second != null)
              Positioned(
                left: w * 0.03,
                bottom: labelZone,
                child: Opacity(
                  opacity: _sideOpacity,
                  child: bust(second,
                      width: sideW,
                      height: sideH,
                      pose: AvatarPose.pose2,
                      mirror: true,
                      winner: false),
                ),
              ),

            // 3rd — right, tucked inward + behind, mirrored.
            if (third != null)
              Positioned(
                right: w * 0.03,
                bottom: labelZone,
                child: Opacity(
                  opacity: _sideOpacity,
                  child: bust(third,
                      width: sideW,
                      height: sideH,
                      pose: AvatarPose.pose2,
                      mirror: false,
                      winner: false),
                ),
              ),

            // 1st — front and centre, full scale.
            if (first != null)
              Positioned(
                bottom: labelZone,
                child: bust(first,
                    width: firstW,
                    height: figureH,
                    pose: AvatarPose.pose1,
                    mirror: false,
                    winner: true),
              ),

            // Bottom scrim: fades the figures' shoes into the sheet surface so
            // they ground into the labels instead of hard-cutting. Rises high
            // enough to reach the feet (which sit at ~labelZone). Fades to the
            // theme surface, so it works in light mode too.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: labelZone + 72,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        t.colorScheme.surface.withOpacity(0.0),
                        t.colorScheme.surface,
                      ],
                      stops: const [0.0, 0.5],
                    ),
                  ),
                ),
              ),
            ),

            // Labels — grouped together and centred under the winner (2 · 1 · 3),
            // not spread to the edges. Each is width-capped so long names clip
            // rather than push the group apart.
            Positioned(
              left: 0,
              right: 0,
              bottom: 4,
              height: labelZone,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _Label(entry: second, tint: _silver, maxWidth: w * 0.26),
                  SizedBox(width: w * 0.17),
                  _Label(
                      entry: first,
                      tint: _gold,
                      winner: true,
                      maxWidth: w * 0.30),
                  SizedBox(width: w * 0.17),
                  _Label(entry: third, tint: _bronze, maxWidth: w * 0.26),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }

  // Runner-up / third figures sit at reduced opacity so they recede toward the
  // sheet surface (works in both light and dark themes).
  static const _sideOpacity = 0.7;
}

class _Label extends StatelessWidget {
  final PodiumEntry? entry;
  final Color tint;
  final bool winner;

  /// Caps the label width so a long name clips (fade) instead of pushing the
  /// centred group apart.
  final double maxWidth;
  const _Label({
    required this.entry,
    required this.tint,
    this.maxWidth = 120,
    this.winner = false,
  });

  @override
  Widget build(BuildContext context) {
    final e = entry;
    if (e == null) return const SizedBox.shrink();
    final t = Theme.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: winner ? 24 : 20,
            height: winner ? 24 : 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tint,
              shape: BoxShape.circle,
              boxShadow: winner
                  ? [BoxShadow(color: tint.withOpacity(0.5), blurRadius: 12)]
                  : null,
            ),
            child: Text('${e.rank}',
                style: AppText.display(winner ? 13 : 11,
                    color: const Color(0xFF14151A))),
          ),
          const SizedBox(height: 3),
          Text(
            e.displayName.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.fade,
            softWrap: false,
            textAlign: TextAlign.center,
            style: AppText.display(winner ? 15 : 12,
                color: t.colorScheme.onSurface),
          ),
          Text('+${e.points}',
              style: AppText.label(winner ? 12 : 10, color: tint)),
        ],
      ),
    );
  }
}
