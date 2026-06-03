// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final scope = AppState.of(context);
    final user = scope.auth.user;
    final currentName = user?.displayName ?? 'Unknown';
    final currentEmail = user?.email ?? '';
    final league = scope.league.league;
    return Scaffold(
      backgroundColor: t.colorScheme.surface,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(Spacing.lg),
          children: [
            Row(children: [
              IconButton(
                onPressed: () => context.pop(),
                icon: const Icon(Icons.arrow_back_ios_new, size: 16),
              ),
              Text('Settings'.toUpperCase(), style: AppText.display(24)),
            ]),
            const SizedBox(height: Spacing.lg),
            Text('THEME', style: AppText.label(11)),
            const SizedBox(height: Spacing.sm),
            ListenableBuilder(
              listenable: scope.theme,
              builder: (_, __) => Row(children: [
                _opt(context, t, 'Light', ThemeMode.light, scope.theme.mode),
                _opt(context, t, 'Dark', ThemeMode.dark, scope.theme.mode),
                _opt(context, t, 'System', ThemeMode.system, scope.theme.mode),
              ]),
            ),
            const SizedBox(height: Spacing.xl),
            Text('ACCOUNT', style: AppText.label(11)),
            const SizedBox(height: Spacing.sm),
            _boxed(
              t,
              child: Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(currentName,
                          style: AppText.body(14, weight: FontWeight.w700)),
                      if (currentEmail.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(currentEmail,
                              style: AppText.body(11,
                                  color: t.colorScheme.onSurface
                                      .withOpacity(0.6))),
                        ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Log out?'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              child: const Text('Cancel')),
                          FilledButton(
                              onPressed: () => Navigator.of(context).pop(true),
                              child: const Text('Log out')),
                        ],
                      ),
                    );
                    if (confirmed == true && context.mounted) {
                      await AppState.of(context).auth.logout();
                    }
                  },
                  child: Text('Sign out',
                      style: AppText.body(13,
                          weight: FontWeight.w700,
                          color: BrandColors.accent)),
                ),
              ]),
            ),
            const SizedBox(height: Spacing.sm),
            InkWell(
              onTap: () {
                final qs = currentEmail.isEmpty
                    ? ''
                    : '?email=${Uri.encodeQueryComponent(currentEmail)}';
                context.push('/change-password$qs');
              },
              borderRadius: const BorderRadius.all(Radius.circular(14)),
              child: _boxed(
                t,
                child: Row(children: [
                  Expanded(
                    child: Text('Change password',
                        style: AppText.body(14, weight: FontWeight.w700)),
                  ),
                  Text('›',
                      style: TextStyle(
                          fontSize: 20, color: t.colorScheme.onSurface)),
                ]),
              ),
            ),
            const SizedBox(height: Spacing.xl),
            Text('PRE-SEASON', style: AppText.label(11)),
            const SizedBox(height: Spacing.sm),
            InkWell(
              onTap: () => context.push('/preseason'),
              borderRadius: const BorderRadius.all(Radius.circular(14)),
              child: _boxed(
                t,
                child: Row(children: [
                  Expanded(
                    child: Text('Pre-season questionnaire',
                        style: AppText.body(14, weight: FontWeight.w700)),
                  ),
                  Text('›',
                      style: TextStyle(
                          fontSize: 20, color: t.colorScheme.onSurface)),
                ]),
              ),
            ),
            const SizedBox(height: Spacing.xl),
            Text('LEAGUE', style: AppText.label(11)),
            const SizedBox(height: Spacing.sm),
            _boxed(
              t,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(league?.name ?? 'No league',
                      style: AppText.body(14, weight: FontWeight.w700)),
                  if (league != null) ...[
                    const SizedBox(height: 4),
                    Text('${league.members.length} members',
                        style: AppText.body(11,
                            color: t.colorScheme.onSurface.withOpacity(0.6))),
                    if (league.joinCode != null) ...[
                      const SizedBox(height: Spacing.sm),
                      _JoinCodeRow(code: league.joinCode!),
                    ],
                  ],
                ],
              ),
            ),
            const SizedBox(height: Spacing.xl),
            Text('ABOUT', style: AppText.label(11)),
            const SizedBox(height: Spacing.sm),
            Text('F1 Prediction Game · v1.0.0',
                style: AppText.body(12,
                    color: t.colorScheme.onSurface.withOpacity(0.6))),
          ],
        ),
      ),
    );
  }

  Widget _boxed(ThemeData t, {required Widget child}) => Container(
        padding: const EdgeInsets.all(Spacing.lg),
        decoration: BoxDecoration(
          border: Border.all(color: t.strokeColor, width: 2),
          borderRadius: const BorderRadius.all(Radius.circular(14)),
        ),
        child: child,
      );

  Widget _opt(BuildContext context, ThemeData t, String label, ThemeMode m,
      ThemeMode current) {
    final on = m == current;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () => AppState.of(context).theme.setMode(m),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: Spacing.md, vertical: 7),
          decoration: BoxDecoration(
            color: on ? BrandColors.accent : null,
            border: Border.all(color: t.strokeColor, width: 1.5),
            borderRadius: const BorderRadius.all(Radius.circular(8)),
          ),
          child: Text(label,
              style: AppText.label(11,
                  color: on ? Colors.white : t.colorScheme.onSurface)),
        ),
      ),
    );
  }
}

/// Inline pill showing the league join code with a copy-to-clipboard tap
/// target. Snackbar feedback confirms the copy without leaving the screen.
class _JoinCodeRow extends StatelessWidget {
  final String code;
  const _JoinCodeRow({required this.code});

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied "$code"'), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return InkWell(
      onTap: () => _copy(context),
      borderRadius: const BorderRadius.all(Radius.circular(8)),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md, vertical: 7),
        decoration: BoxDecoration(
          color: t.mutedSurface,
          border: Border.all(color: t.strokeColor, width: 1.5),
          borderRadius: const BorderRadius.all(Radius.circular(8)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('JOIN CODE',
                style: AppText.label(9,
                    color: t.colorScheme.onSurface.withOpacity(0.55))),
            const SizedBox(width: Spacing.sm),
            Text(code,
                style: AppText.display(14, color: t.colorScheme.onSurface)),
            const SizedBox(width: Spacing.sm),
            Icon(Icons.copy, size: 14, color: t.colorScheme.onSurface.withOpacity(0.7)),
          ],
        ),
      ),
    );
  }
}
