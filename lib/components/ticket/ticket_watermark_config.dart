import 'package:flutter/material.dart';

import 'ticket_style.dart';

/// One place to tune every watermark knob on the ticket. PickTicket /
/// SouvenirTicket forward null for their illustration params so this config
/// wins by default. Hot-reload these values to see them everywhere — home
/// pick card, souvenir, dev preview, shared PNGs.
///
/// Semantics:
/// - `alignment`: where the watermark anchors inside the ticket. Also the
///   origin of the `Transform.scale`, so bumping `scale` past 1 grows the
///   silhouette outward from this corner.
/// - `scale`: post-fit multiplier. >1 means the watermark bleeds past the
///   ticket bounds (clipped by `ClipRect`); <1 leaves visible margin.
/// - `boxW` / `boxH`: aspect ratio of the watermark "frame" that the outer
///   FittedBox fits into the parent. Choosing aspect matters because under
///   `BoxFit.cover` the axis that *isn't* the constraining axis becomes the
///   slack that `alignment` can consume — a square frame in a wide body
///   means cover height-overflows, so `bottomRight` actually crops the top.
/// - `fit`: cover bleeds, contain stays fully visible.
/// - `opacityCream` / `opacityDark`: per-paper opacity so dark presets can
///   show a bolder watermark without overpowering text.
class TicketWatermarkConfig {
  final Alignment alignment;
  final double scale;
  final double boxW;
  final double boxH;
  final BoxFit fit;
  final double opacityCream;
  final double opacityDark;

  const TicketWatermarkConfig({
    required this.alignment,
    required this.scale,
    required this.boxW,
    required this.boxH,
    required this.fit,
    required this.opacityCream,
    required this.opacityDark,
  });
}

const TicketWatermarkConfig kPrimaryWatermark = TicketWatermarkConfig(
  alignment: Alignment(0.0, 1.0),
  scale: 1.5,
  boxW: 280,
  boxH: 280,
  fit: BoxFit.contain,
  opacityCream: 0.1,
  opacityDark: 0.22,
);

const TicketWatermarkConfig kSecondaryWatermark = TicketWatermarkConfig(
  alignment: Alignment.centerRight,
  scale: 0.6,
  boxW: 400,
  boxH: 180,
  fit: BoxFit.contain,
  // Circuit lines are thinner than a car silhouette so they read at higher
  // opacity without overpowering the text.
  opacityCream: 0.4,
  opacityDark: 0.18,
);

/// Deterministic round-based rotation through the paper variants. Every
/// player in the league sees the same variant for the same event (keyed by
/// `Event.round`), and consecutive rounds never share a variant — round
/// 1 → list[0], 2 → list[1], 3 → list[2], 4 → list[0], …
///
/// Edit this list to:
///   - re-order which variant lands on which round,
///   - reduce the rotation to a single entry to lock every event to one
///     style (e.g. `[TicketStyle.posterSprint]`),
///   - extend it with future variants without touching `styleForEvent`.
///
/// `styleForEvent` reads this list directly, so changes hot-reload across
/// the home pick card, souvenir, dev preview, and shared PNGs.
const List<TicketStyle> kTicketStyleRotation = <TicketStyle>[
  TicketStyle.posterSprint,
  TicketStyle.nightCarbon,
  TicketStyle.vintageStencil,
  TicketStyle.vintageMustardCityCup,
  TicketStyle.pitWallTelemetry,
  TicketStyle.vintageSageGrandPrix,
  TicketStyle.vintageOliveStateCup,
  TicketStyle.asphaltStencil,
  TicketStyle.vintageRoseChampionship,
];
