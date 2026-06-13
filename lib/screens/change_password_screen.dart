// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../api/api_client.dart';
import '../components/big_pill.dart';
import '../components/branded_field.dart';
import '../components/branded_toast.dart';
import '../state/app_state.dart';
import '../theme/colors.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// Knows-current-password change flow. Reachable from:
///   - the login screen (`/change-password`), where the user types their email
///   - the settings screen, where the user's email is pre-filled and locked
///
/// Backend endpoint is unauthenticated: it verifies identity via the email +
/// current password pair, so the same screen serves both contexts.
class ChangePasswordScreen extends StatefulWidget {
  /// If non-null, pre-fills and locks the email field. Used when launched
  /// from settings where we already know who's logged in.
  final String? prefilledEmail;
  const ChangePasswordScreen({super.key, this.prefilledEmail});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  late final TextEditingController _email =
      TextEditingController(text: widget.prefilledEmail ?? '');
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Email is required');
      return;
    }
    if (_current.text.isEmpty) {
      setState(() => _error = 'Enter your current password');
      return;
    }
    if (_next.text.length < 8) {
      setState(() => _error = 'New password must be at least 8 characters');
      return;
    }
    if (_next.text != _confirm.text) {
      setState(() => _error = "New password and confirmation don't match");
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final api = AppState.of(context).api;
    final router = GoRouter.of(context);
    try {
      await api.changePassword(
        email: email,
        currentPassword: _current.text,
        newPassword: _next.text,
      );
      if (!mounted) return;
      BrandedToast.show(context, 'Password updated', tone: ToastTone.ok);
      router.pop();
    } on UnauthorizedException {
      setState(() => _error = 'Email or current password is wrong');
    } on ValidationException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = "Couldn't reach the server");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final emailLocked = widget.prefilledEmail != null;
    return Scaffold(
      backgroundColor: t.colorScheme.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: Spacing.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    Spacing.xl, Spacing.lg, Spacing.xl, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _busy ? null : () => context.pop(),
                      icon: const Icon(Icons.arrow_back_ios_new, size: 16),
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(width: 4),
                    Text('CHANGE PASSWORD', style: AppText.display(20)),
                  ],
                ),
              ),
              const SizedBox(height: Spacing.xl),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    BrandedField(
                      fieldKey: const Key('changepw.email'),
                      label: 'EMAIL',
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      readOnly: emailLocked,
                      hint: 'you@example.com',
                    ),
                    const SizedBox(height: Spacing.md),
                    BrandedField(
                      fieldKey: const Key('changepw.current'),
                      label: 'CURRENT PASSWORD',
                      controller: _current,
                      obscure: true,
                    ),
                    const SizedBox(height: Spacing.md),
                    BrandedField(
                      fieldKey: const Key('changepw.next'),
                      label: 'NEW PASSWORD',
                      controller: _next,
                      obscure: true,
                      hint: 'At least 8 characters',
                    ),
                    const SizedBox(height: Spacing.md),
                    BrandedField(
                      fieldKey: const Key('changepw.confirm'),
                      label: 'CONFIRM NEW PASSWORD',
                      controller: _confirm,
                      obscure: true,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: Spacing.md),
                      Text(_error!,
                          style: AppText.body(12,
                              color: BrandColors.accent,
                              weight: FontWeight.w700)),
                    ],
                    const SizedBox(height: Spacing.lg),
                    BigPill(
                      key: const Key('changepw.submit'),
                      label: _busy ? 'UPDATING…' : 'UPDATE PASSWORD',
                      trailing: Icons.arrow_forward,
                      background: BrandColors.accent,
                      foreground: Colors.white,
                      onTap: _busy ? null : _submit,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
