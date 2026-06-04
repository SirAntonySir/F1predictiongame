import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'app_card.dart';

class FactCard extends StatelessWidget {
  final FaIconData emblem;
  final String text;
  const FactCard({super.key, required this.emblem, required this.text});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.sm),
      child: Row(
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 42),
            padding: const EdgeInsets.symmetric(horizontal: Spacing.xxs, vertical: Spacing.xs),
            decoration: const BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.all(Radius.circular(6)),
            ),
            alignment: Alignment.center,
            child: FaIcon(emblem, size: 15, color: Colors.white),
          ),
          const SizedBox(width: Spacing.md),
          Expanded(child: Text(text, style: AppText.body(12))),
        ],
      ),
    );
  }
}
