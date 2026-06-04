// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

enum ChipState { idle, done, next, live }

class SessionChip extends StatelessWidget {
  final String label;
  final ChipState state;
  /// Optional tap handler. When provided the chip becomes an interactive
  /// target (used by the home hero to retarget the countdown at a specific
  /// session of the upcoming weekend).
  final VoidCallback? onTap;
  const SessionChip({
    super.key,
    required this.label,
    this.state = ChipState.idle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final (bg, fg, deco) = switch (state) {
      ChipState.idle => (Colors.black.withOpacity(0.25), Colors.white, TextDecoration.none),
      ChipState.done => (Colors.white.withOpacity(0.18), Colors.white.withOpacity(0.6), TextDecoration.lineThrough),
      ChipState.next => (Colors.black, Colors.white, TextDecoration.none),
      ChipState.live => (const Color(0xFFE10600), Colors.white, TextDecoration.none),
    };
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: Spacing.xxs),
      decoration: BoxDecoration(color: bg, borderRadius: const BorderRadius.all(Radius.circular(6))),
      child: Text(label, style: AppText.label(9, color: fg).copyWith(decoration: deco)),
    );
    if (onTap == null) return chip;
    return InkWell(
      onTap: onTap,
      borderRadius: const BorderRadius.all(Radius.circular(6)),
      child: chip,
    );
  }
}
