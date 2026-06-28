// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../theme/typography.dart';

enum TrendDirection { up, down, equal }

class TrendBadge extends StatelessWidget {
  final TrendDirection direction;
  final String label;
  const TrendBadge({super.key, required this.direction, required this.label});

  @override
  Widget build(BuildContext context) {
    final (glyph, bg, fg) = switch (direction) {
      TrendDirection.up => ('▲', BrandColors.ok, Colors.black),
      TrendDirection.down => ('▼', Colors.black, Colors.white),
      TrendDirection.equal => ('━', Colors.transparent, Theme.of(context).colorScheme.onSurface.withOpacity(0.4)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: const BorderRadius.all(Radius.circular(4))),
      // In narrow slots (e.g. the league row's 22px trend column) the
      // glyph+number wraps so the number sits under the arrow — centre it so
      // it lines up beneath the glyph instead of hugging the left edge.
      child: Text('$glyph $label',
          textAlign: TextAlign.center, style: AppText.label(10, color: fg)),
    );
  }
}
