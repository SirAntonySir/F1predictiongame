// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../components/painted_splash.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

const _devEmail = 'rockenstein.anton@gmail.com';

class SplashScreen extends StatelessWidget {
  final Future<void> Function() onRetry;
  final Object? error;

  /// Boot is done: let the draw animation reach the fully painted artwork,
  /// then [onAnimationDone] fires so the owner can swap to the app.
  final bool ready;
  final VoidCallback? onAnimationDone;

  const SplashScreen({
    super.key,
    required this.onRetry,
    this.error,
    this.ready = false,
    this.onAnimationDone,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: _SplashBody(
        error: error,
        onRetry: onRetry,
        ready: ready,
        onAnimationDone: onAnimationDone,
      ),
    );
  }
}

class _SplashBody extends StatelessWidget {
  final Object? error;
  final Future<void> Function() onRetry;
  final bool ready;
  final VoidCallback? onAnimationDone;
  const _SplashBody({
    required this.error,
    required this.onRetry,
    required this.ready,
    required this.onAnimationDone,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      backgroundColor: t.colorScheme.surface,
      // Loading is full-bleed artwork; the error card keeps its safe area.
      body: error == null
          ? PaintedSplash(ready: ready, onFinished: onAnimationDone)
          : SafeArea(
              child: Center(
                child: _BootError(error: error!, onRetry: onRetry),
              ),
            ),
    );
  }
}

class _BootError extends StatelessWidget {
  final Object error;
  final Future<void> Function() onRetry;
  const _BootError({required this.error, required this.onRetry});

  String get _message {
    final s = error.toString();
    if (s.contains('SocketException') ||
        s.contains('ClientException') ||
        s.contains('HandshakeException')) {
      return "Can't reach the server. Check your connection and try again.";
    }
    if (s.contains('TimeoutException')) {
      return "The server is taking too long to respond. It may be waking up — try again in a moment.";
    }
    if (s.contains('401') || s.contains('Unauthorized')) {
      return "Your session expired. Sign in again to continue.";
    }
    return "We couldn't start the app. Try again, or send the details to the developer.";
  }

  Future<void> _report() async {
    String version = '?';
    String build = '?';
    try {
      final info = await PackageInfo.fromPlatform();
      version = info.version;
      build = info.buildNumber;
    } catch (_) {}
    final subject =
        Uri.encodeComponent('[Undercut] Boot failed: ${error.runtimeType}');
    final body = Uri.encodeComponent('''
What I was doing:
(launching the app — describe anything unusual if you can)

—

App version: $version+$build
Where: app boot (splash)
Error: $error
''');
    final uri = Uri.parse('mailto:$_devEmail?subject=$subject&body=$body');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: Spacing.xl, vertical: Spacing.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: Spacing.lg, vertical: Spacing.xl),
            decoration: BoxDecoration(
              color: t.mutedSurface,
              borderRadius: Radii.rLg,
              border: Border.all(
                  color: t.strokeColor.withOpacity(0.4),
                  width: Strokes.subtle),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: BrandColors.accent,
                    shape: BoxShape.circle,
                  ),
                  child: const Text('!',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 26)),
                ),
                const SizedBox(height: Spacing.md),
                Text('COULDN’T START', style: AppText.label(11)),
                const SizedBox(height: Spacing.sm),
                Text(
                  _message,
                  textAlign: TextAlign.center,
                  style: AppText.body(14, weight: FontWeight.w600),
                ),
                const SizedBox(height: Spacing.md),
                Container(
                  padding: const EdgeInsets.all(Spacing.sm),
                  decoration: BoxDecoration(
                    color: t.colorScheme.surface,
                    borderRadius: Radii.rSm,
                    border: Border.all(
                        color: t.strokeColor.withOpacity(0.4), width: 1),
                  ),
                  child: Text(
                    error.toString(),
                    textAlign: TextAlign.center,
                    style: AppText.body(11,
                        color: t.colorScheme.onSurface.withOpacity(0.7)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Spacing.md),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => onRetry(),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(vertical: Spacing.md),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: t.colorScheme.onSurface,
                      borderRadius: Radii.rMd,
                    ),
                    child: Text('TRY AGAIN',
                        style: AppText.label(12,
                            color: t.colorScheme.surface)),
                  ),
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: GestureDetector(
                  onTap: _report,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(vertical: Spacing.md),
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: BrandColors.accent,
                      borderRadius: Radii.rMd,
                    ),
                    child: Text('REPORT TO DEV',
                        style: AppText.label(12, color: Colors.white)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
