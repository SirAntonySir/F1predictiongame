import 'package:flutter/material.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppState.of(context);
    final league = scope.league.league;
    final t = Theme.of(context);
    return Scaffold(
      backgroundColor: t.colorScheme.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.xl, Spacing.xxl, Spacing.xl, Spacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    color: Colors.black,
                    child: Text('F1', style: AppText.display(14, color: Colors.white)),
                  ),
                  const SizedBox(width: 4),
                  Text('PG', style: AppText.display(14)),
                ],
              ),
              const SizedBox(height: Spacing.xxl),
              Text('Who are you?', style: AppText.display(28)),
              const SizedBox(height: Spacing.sm),
              Text(
                'Pick yourself to enter ${league.name}',
                // ignore: deprecated_member_use
                style: AppText.body(13, color: t.colorScheme.onSurface.withOpacity(0.6)),
              ),
              const SizedBox(height: Spacing.xl),
              Expanded(
                child: ListView.separated(
                  itemCount: league.players.length,
                  separatorBuilder: (_, __) => const SizedBox(height: Spacing.sm),
                  itemBuilder: (_, i) {
                    final p = league.players[i];
                    return InkWell(
                      onTap: () => scope.auth.login(p.id),
                      borderRadius: const BorderRadius.all(Radius.circular(14)),
                      child: Container(
                        padding: const EdgeInsets.all(Spacing.lg),
                        decoration: BoxDecoration(
                          border: Border.all(color: t.strokeColor, width: Strokes.card),
                          borderRadius: const BorderRadius.all(Radius.circular(14)),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: const Color(0xFFEEEEEE),
                              child: Text(p.initials, style: AppText.display(14)),
                            ),
                            const SizedBox(width: Spacing.md),
                            Expanded(child: Text(p.displayName, style: AppText.body(15, weight: FontWeight.w700))),
                            const Text('›', style: TextStyle(fontSize: 22)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              Center(child: Text(league.name, style: AppText.label(10, color: BrandColors.accent))),
            ],
          ),
        ),
      ),
    );
  }
}
