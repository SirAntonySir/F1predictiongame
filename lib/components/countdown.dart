import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/tokens.dart' as tokens;
import '../theme/typography.dart';

class Countdown extends StatefulWidget {
  final DateTime target;
  final double size;
  const Countdown({super.key, required this.target, this.size = 30});

  @override
  State<Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<Countdown> {
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(tokens.Durations.tick, (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final diff = widget.target.difference(DateTime.now());
    final d = diff.isNegative ? 0 : diff.inDays;
    final h = diff.isNegative ? 0 : diff.inHours.remainder(24);
    final m = diff.isNegative ? 0 : diff.inMinutes.remainder(60);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _unit(d, 'd'),
        const SizedBox(width: tokens.Spacing.lg),
        _unit(h, 'h'),
        const SizedBox(width: tokens.Spacing.lg),
        _unit(m, 'm'),
      ],
    );
  }

  Widget _unit(int v, String u) => Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(v.toString().padLeft(2, '0'), style: AppText.display(widget.size)),
          const SizedBox(width: 2),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(u, style: AppText.label(9)),
          ),
        ],
      );
}
