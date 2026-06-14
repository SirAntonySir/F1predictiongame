import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

enum TicketOrnament {
  none,
  crossedFlags,
  trophy,
  car,
  checkeredFlag,
  crown,
}

/// Renders the ornament for the hero block. Returns SizedBox.shrink for [none].
class TicketOrnamentWidget extends StatelessWidget {
  final TicketOrnament ornament;
  final Color color;
  final double size;
  const TicketOrnamentWidget({
    super.key,
    required this.ornament,
    required this.color,
    this.size = 18,
  });

  @override
  Widget build(BuildContext context) {
    if (ornament == TicketOrnament.none) return const SizedBox.shrink();
    final filter = ColorFilter.mode(color, BlendMode.srcIn);
    // crossedFlags + trophy stay inline (small, hand-authored, no asset
    // round-trip). car / checkered / crown ship as real SVG assets because
    // they're detailed enough that authoring them inline would be unwieldy.
    final inline = switch (ornament) {
      TicketOrnament.crossedFlags => _crossedFlags,
      TicketOrnament.trophy       => _trophy,
      _                            => null,
    };
    if (inline != null) {
      return SizedBox(
        height: size,
        child: SvgPicture.string(inline, colorFilter: filter),
      );
    }
    final asset = switch (ornament) {
      TicketOrnament.car           => 'assets/ornament_car.svg',
      TicketOrnament.checkeredFlag => 'assets/ornament_checkered.svg',
      TicketOrnament.crown         => 'assets/ornament_crown.svg',
      _ => null,
    };
    if (asset == null) return const SizedBox.shrink();
    return SizedBox(
      height: size,
      child: SvgPicture.asset(asset, colorFilter: filter),
    );
  }
}

const _crossedFlags = '''
<svg viewBox="0 0 100 36" xmlns="http://www.w3.org/2000/svg" fill="currentColor">
  <rect x="46" y="2" width="2" height="32"/>
  <rect x="52" y="2" width="2" height="32"/>
  <path d="M28 4 L48 4 L48 18 L28 22 Z"/>
  <path d="M52 4 L72 8 L72 22 L52 18 Z"/>
</svg>
''';

// Vintage cup with two looped handles + tiered base. Centered around x=50 so
// it pairs cleanly with the standard 18px ornament slot. No user-provided
// asset for this one — kept inline.
const _trophy = '''
<svg viewBox="0 0 100 36" xmlns="http://www.w3.org/2000/svg" fill="currentColor">
  <path d="M38 2 L62 2 L60 18 Q60 26 50 28 Q50 30 52 31 L52 33 L48 33 L48 31 Q50 30 50 28 Q40 26 40 18 Z"/>
  <path d="M34 6 Q26 8 28 17 Q31 22 40 21 L40 19 Q34 19 33 14 Q35 11 38 11 Z"/>
  <path d="M66 6 Q74 8 72 17 Q69 22 60 21 L60 19 Q66 19 67 14 Q65 11 62 11 Z"/>
  <rect x="44" y="33" width="12" height="2"/>
  <rect x="41" y="34" width="18" height="2"/>
</svg>
''';
