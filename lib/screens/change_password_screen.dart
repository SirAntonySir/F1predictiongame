// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../api/api_client.dart';
import '../state/app_state.dart';

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
  final _formKey = GlobalKey<FormState>();
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
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final api = AppState.of(context).api;
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    try {
      await api.changePassword(
        email: _email.text.trim(),
        currentPassword: _current.text,
        newPassword: _next.text,
      );
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Password updated.')),
      );
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
      appBar: AppBar(title: const Text('Change password')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const Key('changepw.email'),
                  controller: _email,
                  readOnly: emailLocked,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('changepw.current'),
                  controller: _current,
                  obscureText: true,
                  decoration:
                      const InputDecoration(labelText: 'Current password'),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('changepw.next'),
                  controller: _next,
                  obscureText: true,
                  decoration:
                      const InputDecoration(labelText: 'New password'),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    if (v.length < 8) return 'At least 8 characters';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('changepw.confirm'),
                  controller: _confirm,
                  obscureText: true,
                  decoration:
                      const InputDecoration(labelText: 'Confirm new password'),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    if (v != _next.text) return "Doesn't match";
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      _error!,
                      style: TextStyle(color: t.colorScheme.error),
                    ),
                  ),
                FilledButton(
                  key: const Key('changepw.submit'),
                  onPressed: _busy ? null : _submit,
                  child: Text(_busy ? 'Updating…' : 'Update password'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
