import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/components/painted_splash.dart';
import 'package:predictiongame/screens/splash_screen.dart';
import 'package:predictiongame/theme/app_theme.dart';

Widget _frame(Widget c) => MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: c),
    );

void main() {
  testWidgets('the artwork asset is bundled (pubspec assets entry)',
      (tester) async {
    // Guards the pubspec `assets:` list — `- assets/` alone does NOT include
    // subdirectories, so assets/loading/ needs its own entry.
    final data = await tester.runAsync(
        () => rootBundle.load('assets/loading/loading.svg'));
    expect(data!.lengthInBytes, greaterThan(0));
  });

  testWidgets('SplashArt.parse extracts the trace strokes and color fills',
      (tester) async {
    final text = await tester.runAsync(
        () => rootBundle.loadString('assets/loading/loading.svg'));
    final art = SplashArt.parse(text!);
    // Dimensions come from the SVG's own viewBox, not hardcoded values.
    expect(art.width, 735);
    expect(art.height, 1063);
    // 493 stroke paths in the trace group; 280 fill paths + 30 shapes.
    expect(art.strokes.length, greaterThan(450));
    expect(art.fills.length, greaterThan(280));
    // Stroke width picked up from the trace group's stroke-width="2.00".
    expect(art.strokes.first.width, 2.0);
    // Strokes carry measurable geometry for partial (dash-offset) drawing.
    expect(art.strokes.first.length, greaterThan(0));
    expect(art.strokes.first.metrics, isNotEmpty);
  });

  testWidgets('PaintedSplash mounts, parses the art, and loops',
      (tester) async {
    // Plain MaterialApp: AppTheme's google_fonts kicks off a real font load
    // that would throw inside the runAsync window below.
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: PaintedSplash())));
    // Let the async asset load + parse complete for real.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)));
    await tester.pump();
    expect(find.byType(CustomPaint), findsWidgets);
    // Survives a full cycle (draw → fill → hold → erase) and keeps looping.
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump(const Duration(milliseconds: 1500));
    expect(tester.hasRunningAnimations, isTrue);
  });

  testWidgets('ready=true plays to the full artwork then fires onFinished once',
      (tester) async {
    var finished = 0;
    await tester.pumpWidget(_frame(
        PaintedSplash(ready: false, onFinished: () => finished++)));
    // Mid-draw (0.8s into the 4s cycle = v 0.2), boot completes.
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpWidget(_frame(
        PaintedSplash(ready: true, onFinished: () => finished++)));
    // Remaining path to the fully-painted moment: (0.76-0.2)*4s = 2.24s.
    await tester.pump(const Duration(milliseconds: 1000));
    expect(finished, 0);
    await tester.pump(const Duration(milliseconds: 1400));
    expect(finished, 1);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('ready during the erase phase finishes the cycle, repaints, '
      'then fires onFinished', (tester) async {
    var finished = 0;
    await tester.pumpWidget(_frame(
        PaintedSplash(ready: false, onFinished: () => finished++)));
    // Deep in the erase phase: v = 0.9 (3.6s of the 4s cycle).
    await tester.pump(const Duration(milliseconds: 3600));
    await tester.pumpWidget(_frame(
        PaintedSplash(ready: true, onFinished: () => finished++)));
    // Erase out: 0.1*4s = 0.4s. Fake-async pumps jump the clock in one step,
    // so give segment 1 its own frame before the long repaint segment.
    await tester.pump(const Duration(milliseconds: 500));
    expect(finished, 0);
    // Repaint to 0.76 takes 3.04s from here.
    await tester.pump(const Duration(milliseconds: 3200));
    expect(finished, 1);
  });

  testWidgets('disposal mid-handoff neither fires onFinished nor throws',
      (tester) async {
    var finished = 0;
    await tester.pumpWidget(_frame(
        PaintedSplash(ready: true, onFinished: () => finished++)));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(_frame(const SizedBox()));
    await tester.pump(const Duration(milliseconds: 4000));
    expect(finished, 0);
  });

  testWidgets('SplashScreen shows the painted artwork while booting',
      (tester) async {
    await tester.pumpWidget(SplashScreen(onRetry: () async {}, error: null));
    expect(find.byType(PaintedSplash), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('SplashScreen error state keeps the retry card, no artwork',
      (tester) async {
    await tester.pumpWidget(
        SplashScreen(onRetry: () async {}, error: Exception('boom')));
    expect(find.byType(PaintedSplash), findsNothing);
    expect(find.textContaining('again', findRichText: true), findsWidgets);
  });

  testWidgets('renders full artwork + key animation frames to /tmp for review',
      (tester) async {
    final text = await tester.runAsync(
        () => rootBundle.loadString('assets/loading/loading.svg'));
    final art = SplashArt.parse(text!);
    await tester.runAsync(() async {
      Future<void> snap(String name, double v) async {
        final (stroke, fill) = splashProgressAt(v);
        final rec = ui.PictureRecorder();
        final canvas = Canvas(rec);
        canvas.drawRect(Rect.fromLTWH(0, 0, art.width, art.height),
            Paint()..color = Colors.white);
        debugPaintSplashArt(canvas, art, stroke, fill);
        final img = await rec
            .endRecording()
            .toImage(art.width.toInt(), art.height.toInt());
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        File('/tmp/splash_$name.png').writeAsBytesSync(
            bytes!.buffer.asUint8List());
      }

      await snap('draw', 0.25); // strokes sketching in
      await snap('fill', 0.55); // colors washing over the ink
      await snap('full', 0.76); // the handoff frame
    });
  });
}
