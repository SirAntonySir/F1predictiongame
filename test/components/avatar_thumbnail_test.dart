import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/avatar/avatar_config.dart';
import 'package:predictiongame/avatar/avatar_palette.dart';
import 'package:predictiongame/components/avatar_thumbnail.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

/// Transforms under [AvatarBust] whose matrix negates the x-axis — i.e. a
/// left-right (horizontal) flip.
Iterable<Transform> _horizontalFlips(WidgetTester tester) => tester
    .widgetList<Transform>(find.descendant(
        of: find.byType(AvatarBust), matching: find.byType(Transform)))
    .where((x) => x.transform.entry(0, 0) == -1.0);

void main() {
  testWidgets('renders the figure once the raster resolves (boxed)',
      (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(_host(
        AvatarThumbnail(configJson: const AvatarConfig(presetId: 'bolt').toJson()),
      ));
      // Let the async head-crop render resolve, then rebuild.
      await Future.delayed(const Duration(milliseconds: 50));
      await tester.pump();
    });
    expect(find.byType(RawImage), findsOneWidget);
  });

  testWidgets('mirror: true flips the bust horizontally (left-right)',
      (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(_host(SizedBox(
        width: 120,
        height: 120,
        child: AvatarBust(
          configJson: const AvatarConfig(presetId: 'bolt').toJson(),
          bottomFade: false,
          mirror: true,
        ),
      )));
      await Future.delayed(const Duration(milliseconds: 60));
      await tester.pump();
    });
    expect(find.byType(RawImage), findsOneWidget);
    final flips = _horizontalFlips(tester);
    expect(flips, hasLength(1));
    // x negated, y preserved → horizontal flip, not vertical (upside-down).
    expect(flips.first.transform.entry(1, 1), 1.0);
  });

  testWidgets('mirror defaults to false (no flip)', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(_host(SizedBox(
        width: 120,
        height: 120,
        child: AvatarBust(
          configJson: const AvatarConfig(presetId: 'bolt').toJson(),
          bottomFade: false,
        ),
      )));
      await Future.delayed(const Duration(milliseconds: 60));
      await tester.pump();
    });
    expect(_horizontalFlips(tester), isEmpty);
  });

  testWidgets('forcePose renders regardless of the config pose', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(_host(SizedBox(
        width: 120,
        height: 120,
        child: AvatarBust(
          // Saved as pose1, forced to pose2 for this bust.
          configJson:
              const AvatarConfig(presetId: 'bolt', pose: AvatarPose.pose1)
                  .toJson(),
          bottomFade: false,
          forcePose: AvatarPose.pose2,
        ),
      )));
      await Future.delayed(const Duration(milliseconds: 60));
      await tester.pump();
    });
    expect(find.byType(RawImage), findsOneWidget);
  });

  testWidgets('transparent mode has no disc container', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(_host(
        const AvatarThumbnail(configJson: null, size: 28, background: false),
      ));
      await Future.delayed(const Duration(milliseconds: 50));
      await tester.pump();
    });
    // Renders the image with no BoxDecoration disc behind it.
    expect(find.byType(RawImage), findsOneWidget);
    final decos = tester
        .widgetList<Container>(find.descendant(
            of: find.byType(AvatarThumbnail), matching: find.byType(Container)))
        .where((c) => c.decoration is BoxDecoration);
    expect(decos, isEmpty);
  });

  testWidgets('boxed mode paints a disc container', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(_host(
        const AvatarThumbnail(configJson: null, size: 32),
      ));
      await Future.delayed(const Duration(milliseconds: 50));
      await tester.pump();
    });
    final decos = tester
        .widgetList<Container>(find.descendant(
            of: find.byType(AvatarThumbnail), matching: find.byType(Container)))
        .where((c) => c.decoration is BoxDecoration &&
            (c.decoration as BoxDecoration).shape == BoxShape.circle);
    expect(decos, isNotEmpty);
  });
}
