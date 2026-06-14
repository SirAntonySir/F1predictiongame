import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import '../components/branded_sheet.dart';
import '../components/branded_field.dart';
import '../components/branded_time_picker.dart';
import '../components/branded_toast.dart';
import '../state/app_state.dart';
import '../state/notification_settings_controller.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

// Muted-color scale: text reads at 0.55, icons at 0.7.
const double _mutedText = 0.55;
const double _mutedIcon = 0.7;

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
            _SettingsCard(
              title: currentName,
              subtitle: currentEmail.isEmpty ? null : currentEmail,
              trailing: TextButton(
                onPressed: () async {
                  final confirmed = await BrandedSheet.confirm(
                    context,
                    title: 'Log out?',
                    primaryLabel: 'Log out',
                  );
                  if (confirmed && context.mounted) {
                    await AppState.of(context).auth.logout();
                  }
                },
                child: Text('Sign out',
                    style: AppText.body(13,
                        weight: FontWeight.w700, color: BrandColors.accent)),
              ),
            ),
            const SizedBox(height: Spacing.sm),
            _SettingsCard(
              title: 'Change password',
              subtitle: 'Update your sign-in password',
              trailing: _chevron(t),
              onTap: () {
                final qs = currentEmail.isEmpty
                    ? ''
                    : '?email=${Uri.encodeQueryComponent(currentEmail)}';
                context.push('/change-password$qs');
              },
            ),
            const SizedBox(height: Spacing.xl),
            Text('PRE-SEASON', style: AppText.label(11)),
            const SizedBox(height: Spacing.sm),
            _SettingsCard(
              title: 'Pre-season questionnaire',
              subtitle: 'Driver & team predictions for the season',
              trailing: _chevron(t),
              onTap: () => context.push('/preseason'),
            ),
            const SizedBox(height: Spacing.xl),
            Text('LEAGUE', style: AppText.label(11)),
            const SizedBox(height: Spacing.sm),
            _SettingsCard(
              title: league?.name ?? 'No league',
              subtitle: league == null
                  ? null
                  : league.hasPassword
                      ? '${league.members.length} members · Password-protected'
                      : '${league.members.length} members',
            ),
            if (league?.joinCode != null) ...[
              const SizedBox(height: Spacing.sm),
              _JoinCodeRow(code: league!.joinCode!),
            ],
            if (league != null && league.role == 'owner') ...[
              const SizedBox(height: Spacing.sm),
              _LeaguePasswordRow(
                hasPassword: league.hasPassword,
                leagueId: league.id,
              ),
            ],
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
            Text('GAME', style: AppText.label(11)),
            const SizedBox(height: Spacing.sm),
            _SettingsCard(
              title: 'Scoring rules',
              subtitle: 'How points are awarded',
              trailing: _chevron(t),
              onTap: () => context.push('/rules'),
            ),
            if (league != null && league.role == 'owner') ...[
              const SizedBox(height: Spacing.sm),
              _SettingsCard(
                title: 'Data import',
                subtitle: 'Bulk-import predictions from JSON',
                trailing: _chevron(t),
                onTap: () => context.push('/import'),
              ),
            ],
            if (kDebugMode) ...[
              const SizedBox(height: Spacing.xl),
              Text('DEBUG', style: AppText.label(11)),
              const SizedBox(height: Spacing.sm),
              _SettingsCard(
                title: 'Ticket preview',
                subtitle: 'All ticket variants × style presets',
                trailing: _chevron(t),
                onTap: () => context.push('/dev/tickets'),
              ),
            ],
            const SizedBox(height: Spacing.xl),
            Text('ABOUT', style: AppText.label(11)),
            const SizedBox(height: Spacing.sm),
            Text('F1 Prediction Game · v1.0.0',
                style: AppText.body(12,
                    color: t.colorScheme.onSurface
                        .withValues(alpha: _mutedText))),
          ],
        ),
      ),
    );
  }

  Widget _opt(BuildContext context, ThemeData t, String label, ThemeMode m,
      ThemeMode current) {
    final on = m == current;
    return Padding(
      padding: const EdgeInsets.only(right: Spacing.xs),
      child: GestureDetector(
        onTap: () => AppState.of(context).theme.setMode(m),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: Spacing.md, vertical: Spacing.xs),
          decoration: BoxDecoration(
            color: on ? BrandColors.accent : null,
            border: Border.all(color: t.strokeColor, width: Strokes.subtle),
            borderRadius: Radii.rSm,
          ),
          child: Text(label,
              style: AppText.label(11,
                  color: on ? Colors.white : t.colorScheme.onSurface)),
        ),
      ),
    );
  }
}

Widget _chevron(ThemeData t) => FaIcon(
      FontAwesomeIcons.chevronRight,
      size: 12,
      color: t.colorScheme.onSurface.withValues(alpha: _mutedIcon),
    );

/// Unified settings card anatomy: title · subtitle · optional trailing widget.
/// Wrap in InkWell when [onTap] is set; otherwise it's static.
class _SettingsCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingsCard({
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final container = Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        border: Border.all(color: t.strokeColor, width: Strokes.card),
        borderRadius: Radii.rLg,
      ),
      child: Row(children: [
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: AppText.body(14, weight: FontWeight.w700)),
              if (subtitle != null) ...[
                const SizedBox(height: Spacing.xxs),
                Text(subtitle!,
                    style: AppText.body(11,
                        color: t.colorScheme.onSurface
                            .withValues(alpha: _mutedText))),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: Spacing.sm),
          trailing!,
        ],
      ]),
    );
    if (onTap == null) return container;
    return InkWell(
      onTap: onTap,
      borderRadius: Radii.rLg,
      child: container,
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
        _SettingsCard(
          title: 'Pick reminders',
          subtitle:
              "5h, 1h, and 10 min before lock, only if you haven't picked.",
          trailing: Switch.adaptive(
            value: controller.enabled,
            onChanged: controller.setEnabled,
            activeThumbColor: BrandColors.accent,
          ),
        ),
        const SizedBox(height: Spacing.sm),
        Opacity(
          opacity: controller.enabled ? 1 : 0.4,
          child: IgnorePointer(
            ignoring: !controller.enabled,
            child: Column(
              children: [
                _SettingsCard(
                  title: 'Quiet hours',
                  subtitle: 'No reminders during this window.',
                  trailing: Switch.adaptive(
                    value: controller.quietHoursEnabled,
                    onChanged: controller.setQuietHoursEnabled,
                    activeThumbColor: BrandColors.accent,
                  ),
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
        final picked = await showBrandedTimePicker(
          context,
          initial: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
        );
        if (picked == null) return;
        onPick(picked.hour * 60 + picked.minute);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md, vertical: Spacing.sm),
        decoration: BoxDecoration(
          border: Border.all(color: t.strokeColor, width: Strokes.subtle),
          borderRadius: Radii.rSm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(),
                style: AppText.label(9,
                    color: t.colorScheme.onSurface
                        .withValues(alpha: _mutedText))),
            const SizedBox(height: Spacing.xxs),
            Text('$h:$m', style: AppText.display(18)),
          ],
        ),
      ),
    );
  }
}

/// Card row showing the league join code. Tap copies; toast confirms.
class _JoinCodeRow extends StatelessWidget {
  final String code;
  const _JoinCodeRow({required this.code});

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!context.mounted) return;
    BrandedToast.show(context, 'Code copied', tone: ToastTone.ok);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return _SettingsCard(
      title: 'Join code',
      subtitle: code,
      trailing: FaIcon(FontAwesomeIcons.copy,
          size: 14,
          color: t.colorScheme.onSurface.withValues(alpha: _mutedIcon)),
      onTap: () => _copy(context),
    );
  }
}

/// Owner-only row in the LEAGUE section. Opens a dialog to set, change, or
/// clear the league join password.
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
    final result = await showBrandedSheet<_PwResult>(
      context,
      builder: (_) => _LeaguePasswordDialog(hasPassword: widget.hasPassword),
    );
    if (result == null || !mounted) return;
    final scope = AppState.of(context);
    setState(() => _busy = true);
    try {
      // Empty string = clear; non-empty = set.
      await scope.api.updateLeague(widget.leagueId, password: result.value);
      await scope.league.load(widget.leagueId);
      if (!mounted) return;
      BrandedToast.show(
        context,
        result.value.isEmpty
            ? 'League password removed'
            : 'League password updated',
        tone: ToastTone.ok,
      );
    } catch (_) {
      if (mounted) {
        BrandedToast.show(context, "Couldn't update password",
            tone: ToastTone.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return _SettingsCard(
      title: widget.hasPassword ? 'Change password' : 'Set password',
      subtitle: widget.hasPassword
          ? 'Update the league join password'
          : 'Require a password to join this league',
      trailing: _chevron(t),
      onTap: _busy ? null : _open,
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
  void initState() {
    super.initState();
    // Keep the primary action label (Save/Remove) in sync as the user types.
    _ctrl.addListener(() => setState(() {}));
  }

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
    final t = Theme.of(context);
    final remove = widget.hasPassword && _ctrl.text.isEmpty;
    return BrandedSheet(
      title:
          widget.hasPassword ? 'Change league password' : 'Set league password',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BrandedField(
            label: 'NEW PASSWORD',
            controller: _ctrl,
            obscure: true,
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            'Leave empty and confirm to remove the password.',
            style: AppText.body(11,
                color: t.colorScheme.onSurface
                    .withValues(alpha: _mutedText)),
          ),
          if (_err != null) ...[
            const SizedBox(height: Spacing.xs),
            Text(_err!, style: AppText.body(11, color: t.colorScheme.error)),
          ],
        ],
      ),
      primaryLabel: remove ? 'Remove' : 'Save',
      onPrimary: _submit,
      onSecondary: () => Navigator.of(context).pop(),
    );
  }
}
