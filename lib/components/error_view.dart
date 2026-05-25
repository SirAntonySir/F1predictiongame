// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'app_card.dart';

const _devEmail = 'rockenstein.anton@gmail.com';

class ErrorView extends StatelessWidget {
  final Object error;
  final StackTrace? stack;
  final String? where;
  final VoidCallback? onRetry;

  const ErrorView({
    super.key,
    required this.error,
    this.stack,
    this.where,
    this.onRetry,
  });

  Future<void> _report() async {
    final info = await PackageInfo.fromPlatform();
    final subject = Uri.encodeComponent(
        '[F1PG] ${error.runtimeType} in ${where ?? 'app'}');
    final body = Uri.encodeComponent('''
What I was doing:
(describe what you tapped before this screen showed)

—

App version: ${info.version}+${info.buildNumber}
Where: ${where ?? '(unknown)'}
Error: $error
Stack:
${stack ?? '(no stack)'}
''');
    final uri = Uri.parse('mailto:$_devEmail?subject=$subject&body=$body');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final message = _humanMessage(error);
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: Spacing.lg, vertical: Spacing.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            background: t.mutedSurface,
            padding: const EdgeInsets.symmetric(
                horizontal: Spacing.lg, vertical: Spacing.xl),
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
                Text('SOMETHING WENT WRONG', style: AppText.label(11)),
                const SizedBox(height: Spacing.sm),
                Text(message,
                    textAlign: TextAlign.center,
                    style: AppText.body(14, weight: FontWeight.w600)),
                const SizedBox(height: Spacing.md),
                Container(
                  padding: const EdgeInsets.all(Spacing.sm),
                  decoration: BoxDecoration(
                    color: t.colorScheme.surface,
                    borderRadius: const BorderRadius.all(Radius.circular(8)),
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
              if (onRetry != null) ...[
                Expanded(
                  child: GestureDetector(
                    onTap: onRetry,
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(vertical: Spacing.md),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: t.colorScheme.onSurface,
                        borderRadius:
                            const BorderRadius.all(Radius.circular(12)),
                      ),
                      child: Text('TRY AGAIN',
                          style: AppText.label(12,
                              color: t.colorScheme.surface)),
                    ),
                  ),
                ),
                const SizedBox(width: Spacing.sm),
              ],
              Expanded(
                child: GestureDetector(
                  onTap: _report,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: Spacing.md),
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: BrandColors.accent,
                      borderRadius: BorderRadius.all(Radius.circular(12)),
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

  String _humanMessage(Object e) {
    final s = e.toString();
    if (s.contains('NotFoundException')) {
      return "We couldn't find what we were looking for. The backend may not be fully populated yet.";
    }
    if (s.contains('UpstreamException')) {
      return "The backend hit a problem. It might be down or overloaded — try again in a bit.";
    }
    if (s.contains('SocketException') || s.contains('ClientException')) {
      return "Can't reach the backend. Check your connection or that the server is running.";
    }
    return "An unexpected error stopped this screen from loading.";
  }
}
