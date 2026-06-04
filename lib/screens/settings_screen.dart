// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../state/app_state.dart';
import '../state/notification_settings_controller.dart';
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
                    if (league.role == 'owner') ...[
                      const SizedBox(height: Spacing.sm),
                      _LeaguePasswordRow(
                        hasPassword: league.hasPassword,
                        leagueId: league.id,
                      ),
                    ] else if (league.hasPassword) ...[
                      const SizedBox(height: Spacing.sm),
                      Row(
                        children: [
                          Icon(Icons.lock_outline, size: 12,
                              color: t.colorScheme.onSurface.withOpacity(0.5)),
                          const SizedBox(width: 4),
                          Text('Password-protected',
                              style: AppText.body(11,
                                  color: t.colorScheme.onSurface.withOpacity(0.5))),
                        ],
                      ),
                    ],
                  ],
                ],
              ),
            ),
            const SizedBox(height: Spacing.xl),
            Text('NOTIFICATIONS', style: AppText.label(11)),
            const SizedBox(height: Spacing.sm),
            ListenableBuilder(
              listenable: scope.notifications,
              builder: (_, __) => _NotificationsSection(
                controller: scope.notifications,
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

/// Notifications section: master toggle for pick reminders + optional
/// quiet-hours window. Master defaults ON (the user opted in by installing
/// the feature); quiet hours default OFF.
class _NotificationsSection extends StatelessWidget {
  final NotificationSettingsController controller;
  const _NotificationsSection({required this.controller});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _toggleRow(
          context: context,
          t: t,
          title: 'Pick reminders',
          subtitle: "5h, 1h, and 10 min before lock — only if you haven't picked.",
          value: controller.enabled,
          onChanged: controller.setEnabled,
        ),
        const SizedBox(height: Spacing.sm),
        Opacity(
          opacity: controller.enabled ? 1 : 0.4,
          child: IgnorePointer(
            ignoring: !controller.enabled,
            child: Column(
              children: [
                _toggleRow(
                  context: context,
                  t: t,
                  title: 'Quiet hours',
                  subtitle: 'No reminders during this window.',
                  value: controller.quietHoursEnabled,
                  onChanged: controller.setQuietHoursEnabled,
                ),
                if (controller.quietHoursEnabled) ...[
                  const SizedBox(height: Spacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: _timeButton(
                          context: context,
                          t: t,
                          label: 'From',
                          minutes: controller.quietStartMin,
                          onPick: (m) => controller.setQuietWindow(
                            startMin: m,
                            endMin: controller.quietEndMin,
                          ),
                        ),
                      ),
                      const SizedBox(width: Spacing.sm),
                      Expanded(
                        child: _timeButton(
                          context: context,
                          t: t,
                          label: 'Until',
                          minutes: controller.quietEndMin,
                          onPick: (m) => controller.setQuietWindow(
                            startMin: controller.quietStartMin,
                            endMin: m,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _toggleRow({
    required BuildContext context,
    required ThemeData t,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        border: Border.all(color: t.strokeColor, width: 2),
        borderRadius: const BorderRadius.all(Radius.circular(14)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.body(14, weight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: AppText.body(11,
                        color: t.colorScheme.onSurface.withOpacity(0.6))),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: BrandColors.accent,
          ),
        ],
      ),
    );
  }

  Widget _timeButton({
    required BuildContext context,
    required ThemeData t,
    required String label,
    required int minutes,
    required ValueChanged<int> onPick,
  }) {
    final h = (minutes ~/ 60).toString().padLeft(2, '0');
    final m = (minutes % 60).toString().padLeft(2, '0');
    return GestureDetector(
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
        );
        if (picked == null) return;
        onPick(picked.hour * 60 + picked.minute);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md, vertical: Spacing.sm),
        decoration: BoxDecoration(
          border: Border.all(color: t.strokeColor, width: 1.5),
          borderRadius: const BorderRadius.all(Radius.circular(10)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(),
                style: AppText.label(9,
                    color: t.colorScheme.onSurface.withOpacity(0.55))),
            const SizedBox(height: 4),
            Text('$h:$m', style: AppText.display(18)),
          ],
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

/// Owner-only row in the LEAGUE settings card. Opens a dialog to set,
/// change, or clear the league join password.
class _LeaguePasswordRow extends StatefulWidget {
  final bool hasPassword;
  final String leagueId;
  const _LeaguePasswordRow({
    required this.hasPassword,
    required this.leagueId,
  });

  @override
  State<_LeaguePasswordRow> createState() => _LeaguePasswordRowState();
}

class _LeaguePasswordRowState extends State<_LeaguePasswordRow> {
  bool _busy = false;

  Future<void> _open() async {
    final result = await showDialog<_PwResult>(
      context: context,
      builder: (_) => _LeaguePasswordDialog(hasPassword: widget.hasPassword),
    );
    if (result == null || !mounted) return;
    final scope = AppState.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      // Empty string = clear; non-empty = set.
      await scope.api.updateLeague(widget.leagueId, password: result.value);
      await scope.league.load(widget.leagueId);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(result.value.isEmpty
            ? 'League password removed.'
            : 'League password updated.'),
      ));
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(const SnackBar(
          content: Text("Couldn't update the league password."),
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final label = widget.hasPassword ? 'Change password' : 'Set password';
    return InkWell(
      onTap: _busy ? null : _open,
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
            Icon(
              widget.hasPassword ? Icons.lock : Icons.lock_open_outlined,
              size: 14,
              color: t.colorScheme.onSurface,
            ),
            const SizedBox(width: Spacing.sm),
            Text(label.toUpperCase(),
                style: AppText.label(10, color: t.colorScheme.onSurface)),
          ],
        ),
      ),
    );
  }
}

/// Dialog result. Empty string `value` means "clear the password".
class _PwResult {
  final String value;
  const _PwResult(this.value);
}

class _LeaguePasswordDialog extends StatefulWidget {
  final bool hasPassword;
  const _LeaguePasswordDialog({required this.hasPassword});

  @override
  State<_LeaguePasswordDialog> createState() => _LeaguePasswordDialogState();
}

class _LeaguePasswordDialogState extends State<_LeaguePasswordDialog> {
  final _ctrl = TextEditingController();
  String? _err;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _ctrl.text;
    if (v.isNotEmpty && v.length < 4) {
      setState(() => _err = 'At least 4 characters (or leave empty to remove)');
      return;
    }
    Navigator.of(context).pop(_PwResult(v));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.hasPassword ? 'Change league password' : 'Set league password'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _ctrl,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'New password',
              helperText: 'Leave empty and confirm to remove the password',
            ),
          ),
          if (_err != null) Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_err!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.hasPassword && _ctrl.text.isEmpty ? 'Remove' : 'Save'),
        ),
      ],
    );
  }
}
