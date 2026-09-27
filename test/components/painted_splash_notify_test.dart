import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/components/painted_splash.dart';

/// Mirrors the boot overlay: a parent whose build delivers `ready` to the
/// splash and whose onFinished setStates on itself (an ancestor). When
/// `ready` flips AFTER the one-shot animation already completed — boot
/// outlasting the artwork — onFinished must not fire synchronously inside
/// didUpdateWidget (setState-during-build → the splash never lifts).
class _Host extends StatefulWidget {
  const _Host({super.key});
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  bool ready = false;
  bool finished = false;

  void makeReady() => setState(() => ready = true);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: PaintedSplash(
        ready: ready,
        asset: 'assets/dev_car_outline.svg',
        ops: const {},
        duration: const Duration(milliseconds: 100),
        onFinished: () => setState(() => finished = true),
      ),
    );
  }
}

void main() {
  testWidgets('ready flipping after the artwork completed defers onFinished '
      'past the current build', (tester) async {
    final key = GlobalKey<_HostState>();
    await tester.pumpWidget(_Host(key: key));
    // Let the one-shot animation (100ms) finish and the art load.
    await tester.pump(const Duration(milliseconds: 250));

    key.currentState!.makeReady();
    await tester.pump();
    // Pre-fix this throws "setState() called during build" out of
    // didUpdateWidget and the finished flag would never propagate cleanly.
    expect(tester.takeException(), isNull);

    await tester.pump();
    expect(key.currentState!.finished, isTrue);
  });

  testWidgets('ready before the artwork completes still fires onFinished '
      'when the animation ends', (tester) async {
    final key = GlobalKey<_HostState>();
    await tester.pumpWidget(_Host(key: key));
    key.currentState!.makeReady(); // ready while still painting
    await tester.pump();
    expect(key.currentState!.finished, isFalse);

    await tester.pump(const Duration(milliseconds: 250)); // animation ends
    await tester.pump();
    expect(key.currentState!.finished, isTrue);
    expect(tester.takeException(), isNull);
  });
}
