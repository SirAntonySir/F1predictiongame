import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

enum TicketOrnament { none, crossedFlags }

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
    switch (ornament) {
      case TicketOrnament.none:
        return const SizedBox.shrink();
      case TicketOrnament.crossedFlags:
        return SizedBox(
          height: size,
          child: SvgPicture.string(
            _crossedFlags,
            colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
          ),
        );
    }
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
