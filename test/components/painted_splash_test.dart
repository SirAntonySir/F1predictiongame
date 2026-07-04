import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/avatar/avatar_palette.dart';
import 'package:predictiongame/components/painted_splash.dart';
import 'package:predictiongame/screens/splash_screen.dart';
import 'package:predictiongame/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _frame(Widget c) => MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: c),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the artwork asset is bundled (pubspec assets entry)',
      (tester) async {
    // Guards the pubspec `assets:` list — `- assets/` alone does NOT include
    // subdirectories, so assets/avatar/ needs its own entry.
    for (final pose in AvatarPose.values) {
      final data = await tester.runAsync(() => rootBundle.load(pose.asset));
      expect(data!.lengthInBytes, greaterThan(0), reason: pose.asset);
    }
  });

  testWidgets('SplashArt.parse extracts the trace strokes and color fills',
      (tester) async {
    final text = await tester.runAsync(
        () => rootBundle.loadString('assets/avatar/pose1.svg'));
    final art = SplashArt.parse(text!);
    // Dimensions come from the SVG's own viewBox, not hardcoded values.
    expect(art.width, 1461);
    expect(art.height, 2153);
    // 994 stroke paths in the trace group; 450 fill paths.
    expect(art.strokes.length, greaterThan(900));
    expect(art.fills.length, greaterThan(400));
    // Stroke width picked up from the trace group's stroke-width="2.00".
    expect(art.strokes.first.width, 2.0);
    // Strokes carry measurable geometry for partial (dash-offset) drawing.
    expect(art.strokes.first.length, greaterThan(0));
    expect(art.strokes.first.metrics, isNotEmpty);
  });

  testWidgets('PaintedSplash plays once and rests on the full artwork',
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
    // Still animating mid-play…
    await tester.pump(const Duration(milliseconds: 1500));
    expect(tester.hasRunningAnimations, isTrue);
    // …but after the 3s one-shot it rests on the full image. No loop.
    await tester.pump(const Duration(milliseconds: 2000));
    expect(tester.hasRunningAnimations, isFalse);
    final (stroke, fill) = splashProgressAt(1.0);
    expect(stroke, 1.0);
    expect(fill, 1.0);
  });

  testWidgets('ready mid-draw waits for the full artwork, then onFinished',
      (tester) async {
    var finished = 0;
    await tester.pumpWidget(_frame(
        PaintedSplash(ready: false, onFinished: () => finished++)));
    // Mid-draw (0.8s into the 3s one-shot), boot completes.
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpWidget(_frame(
        PaintedSplash(ready: true, onFinished: () => finished++)));
    // Not yet — the play still has 2.2s to go.
    await tester.pump(const Duration(milliseconds: 1000));
    expect(finished, 0);
    await tester.pump(const Duration(milliseconds: 1400));
    expect(finished, 1);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('ready after the animation already ended fires immediately',
      (tester) async {
    var finished = 0;
    await tester.pumpWidget(_frame(
        PaintedSplash(ready: false, onFinished: () => finished++)));
    // One-shot done; splash resting on the full image.
    await tester.pump(const Duration(milliseconds: 3500));
    expect(finished, 0);
    await tester.pumpWidget(_frame(
        PaintedSplash(ready: true, onFinished: () => finished++)));
    await tester.pump();
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

  testWidgets('explicit ops recolor live without restarting the animation',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: PaintedSplash(ops: presetById('rosso').ops))));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)));
    await tester.pump(const Duration(milliseconds: 1000));
    expect(tester.hasRunningAnimations, isTrue);
    // Swap the livery mid-draw (builder color tweak): recolors in place,
    // animation keeps its position instead of starting over.
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: PaintedSplash(ops: presetById('silver').ops))));
    await tester.pump(const Duration(milliseconds: 2100));
    expect(tester.hasRunningAnimations, isFalse); // 3s one-shot ended
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('all poses share pose-1 figure framing (height-based scale)',
      (tester) async {
    final arts = <SplashArt>[];
    for (final pose in AvatarPose.values) {
      final text =
          await tester.runAsync(() => rootBundle.loadString(pose.asset));
      arts.add(SplashArt.parse(text!));
    }
    // The reference aspect IS pose 1's real figure — guards asset drift: if
    // pose1.svg is regenerated with different framing, update the constant.
    final p1 = arts.first.contentBounds;
    expect(p1.width / p1.height,
        closeTo(SplashArt.referenceFigureAspect, 0.01));
    for (final art in arts) {
      final f = art.poseFrame;
      // Every pose's frame has the same aspect → FittedBox's contain scale is
      // always driven by figure HEIGHT, never by how wide a pose happens to
      // be. Figure heights therefore match across poses on any screen.
      expect(f.width / f.height,
          closeTo(SplashArt.referenceFigureAspect, 1e-9));
      expect(f.height, art.contentBounds.height);
      expect(f.center.dx, closeTo(art.contentBounds.center.dx, 1e-6));
      expect(f.center.dy, closeTo(art.contentBounds.center.dy, 1e-6));
      // Clip budget: a pose wider than the reference frame gets its edges
      // shaved. Keep that under 2% of the width — beyond that the asset
      // needs regenerating to the reference framing, not a code change.
      final aspect = art.contentBounds.width / art.contentBounds.height;
      expect(aspect, lessThan(SplashArt.referenceFigureAspect * 1.02),
          reason: 'pose figure is too wide for the pose-1 reference frame');
    }
  });

  testWidgets('PaintedSplash lays pose 2 out in the pose-1-shaped frame',
      (tester) async {
    await tester.pumpWidget(_frame(const PaintedSplash(
      asset: 'assets/avatar/pose2.svg',
      ops: {},
    )));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)));
    await tester.pump();
    final box = tester.widget<SizedBox>(find
        .descendant(of: find.byType(FittedBox), matching: find.byType(SizedBox))
        .first);
    expect(box.width! / box.height!,
        closeTo(SplashArt.referenceFigureAspect, 1e-6));
  });

  testWidgets('SplashScreen shows the painted artwork while booting',
      (tester) async {
    await tester.pumpWidget(SplashScreen(onRetry: () async {}, error: null));
    expect(find.byType(PaintedSplash), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('SplashScreen honors the saved in-app theme mode (dark)',
      (tester) async {
    // The user's Settings theme choice must drive the splash background —
    // hardcoding ThemeMode.system flashes a light splash for dark-theme
    // users whose OS is set to light.
    await tester.pumpWidget(SplashScreen(
      onRetry: () async {},
      themeMode: ThemeMode.dark,
    ));
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, AppTheme.dark().colorScheme.surface);
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
        () => rootBundle.loadString('assets/avatar/pose1.svg'));
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

      await snap('draw', 0.30); // strokes sketching in
      await snap('fill', 0.65); // colors washing over the ink
      await snap('full', 1.0); // the resting frame
    });
  });
}
