// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../api/models/session.dart';
import '../state/app_state.dart';
import '../theme/colors.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _seedDemoPicks(BuildContext context) async {
    final scope = AppState.of(context);
    final userId = scope.auth.currentUserId;
    if (userId == null) return;
    final events = await scope.api.events();
    int seededSessions = 0;
    for (final e in events) {
      final race = e.sessions.firstWhere(
        (s) => s.type == SessionType.race && s.status == SessionStatus.finished,
        orElse: () => Session(
          id: -1,
          type: SessionType.race,
          scheduledStart: DateTime.fromMillisecondsSinceEpoch(0),
          scheduledEnd: DateTime.fromMillisecondsSinceEpoch(0),
          status: SessionStatus.scheduled,
        ),
      );
      if (race.id < 0) continue;
      final existing =
          scope.predictions.picksFor(userId: userId, sessionId: race.id);
      if (existing.isNotEmpty) continue;
      try {
        final result = await scope.api.sessionResults(race.id);
        if (result.length < 5) continue;
        final sorted = [...result]
          ..sort((a, b) => a.position.compareTo(b.position));
        // Half-correct picks: P1 + P3 exact; P2/P4/P5 deliberately swapped.
        final picks = [
          sorted[0].driverCode,
          sorted[2].driverCode, // wrong-slot, in top-5
          sorted[1].driverCode, // wrong-slot, in top-5
          sorted[4].driverCode, // wrong-slot, in top-5
          sorted[3].driverCode, // wrong-slot, in top-5
        ];
        await scope.predictions
            .save(userId: userId, sessionId: race.id, picks: picks);
        await scope.predictions
            .lock(userId: userId, sessionId: race.id);
        seededSessions++;
      } catch (_) {
        // skip sessions without published results
      }
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Seeded picks for $seededSessions race(s)')),
      );
    }
  }

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
              IconButton(onPressed: () => context.pop(), icon: const Icon(Icons.arrow_back_ios_new, size: 16)),
              Text('Settings'.toUpperCase(), style: AppText.display(24)),
            ]),
            const SizedBox(height: Spacing.lg),
            Text('THEME', style: AppText.label(11)),
            const SizedBox(height: Spacing.sm),
            ListenableBuilder(
              listenable: scope.theme,
              builder: (_, __) => Row(children: [
                _opt(context, 'Light', ThemeMode.light, scope.theme.mode),
                _opt(context, 'Dark', ThemeMode.dark, scope.theme.mode),
                _opt(context, 'System', ThemeMode.system, scope.theme.mode),
              ]),
            ),
            const SizedBox(height: Spacing.xl),
            Text('ACCOUNT', style: AppText.label(11)),
            const SizedBox(height: Spacing.sm),
            Container(
              padding: const EdgeInsets.all(Spacing.lg),
              decoration: BoxDecoration(border: Border.all(color: Colors.black, width: 2), borderRadius: const BorderRadius.all(Radius.circular(14))),
              child: Row(children: [
                Expanded(child: Text(currentName, style: AppText.body(14, weight: FontWeight.w700))),
                TextButton(onPressed: () => scope.auth.logout(), child: const Text('Sign out')),
              ]),
            ),
            const SizedBox(height: Spacing.xl),
            Text('PRE-SEASON', style: AppText.label(11)),
            const SizedBox(height: Spacing.sm),
            InkWell(
              onTap: () => context.push('/preseason'),
              borderRadius: const BorderRadius.all(Radius.circular(14)),
              child: Container(
                padding: const EdgeInsets.all(Spacing.lg),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black, width: 2),
                  borderRadius: const BorderRadius.all(Radius.circular(14)),
                ),
                child: Row(children: [
                  Expanded(
                    child: Text('Pre-season questionnaire',
                        style: AppText.body(14, weight: FontWeight.w700)),
                  ),
                  const Text('›', style: TextStyle(fontSize: 20)),
                ]),
              ),
            ),
            const SizedBox(height: Spacing.xl),
            Text('LEAGUE', style: AppText.label(11)),
            const SizedBox(height: Spacing.sm),
            Container(
              padding: const EdgeInsets.all(Spacing.lg),
              decoration: BoxDecoration(border: Border.all(color: Colors.black, width: 2), borderRadius: const BorderRadius.all(Radius.circular(14))),
              child: Text(scope.league.league.name, style: AppText.body(14, weight: FontWeight.w700)),
            ),
            const SizedBox(height: Spacing.xl),
            Text('DEBUG', style: AppText.label(11)),
            const SizedBox(height: Spacing.sm),
            InkWell(
              onTap: () => _seedDemoPicks(context),
              borderRadius: const BorderRadius.all(Radius.circular(14)),
              child: Container(
                padding: const EdgeInsets.all(Spacing.lg),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black, width: 2),
                  borderRadius: const BorderRadius.all(Radius.circular(14)),
                ),
                child: Row(children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Seed demo picks',
                            style: AppText.body(14, weight: FontWeight.w700)),
                        Text(
                          'Fills locked Top-5 picks for every finished race so the hit/miss indicators have data to show.',
                          style: AppText.body(11,
                              color:
                                  t.colorScheme.onSurface.withOpacity(0.6)),
                        ),
                      ],
                    ),
                  ),
                  const Text('›', style: TextStyle(fontSize: 20)),
                ]),
              ),
            ),
            const SizedBox(height: Spacing.xl),
            Text('ABOUT', style: AppText.label(11)),
            const SizedBox(height: Spacing.sm),
            Text('F1 Prediction Game · v1.0.0', style: AppText.body(12, color: t.colorScheme.onSurface.withOpacity(0.6))),
          ],
        ),
      ),
    );
  }

  Widget _opt(BuildContext context, String label, ThemeMode m, ThemeMode current) {
    final on = m == current;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () => AppState.of(context).theme.setMode(m),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 7),
          decoration: BoxDecoration(
            color: on ? BrandColors.accent : null,
            border: Border.all(color: Colors.black, width: 1.5),
            borderRadius: const BorderRadius.all(Radius.circular(8)),
          ),
          child: Text(label, style: AppText.label(11, color: on ? Colors.white : Colors.black)),
        ),
      ),
    );
  }
}
