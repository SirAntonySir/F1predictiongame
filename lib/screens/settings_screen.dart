// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
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
    final currentName = scope.league.league.players
        .firstWhere((p) => p.id == scope.auth.currentUserId,
            orElse: () => scope.league.league.players.first)
        .displayName;
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
                  child: Text(currentName,
                      style: AppText.body(14, weight: FontWeight.w700)),
                ),
                TextButton(
                  onPressed: () => scope.auth.logout(),
                  child: Text('Sign out',
                      style: AppText.body(13,
                          weight: FontWeight.w700,
                          color: BrandColors.accent)),
                ),
              ]),
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
              child: Text(scope.league.league.name,
                  style: AppText.body(14, weight: FontWeight.w700)),
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
