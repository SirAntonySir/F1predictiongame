// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../api/api_client.dart';
import '../components/big_pill.dart';
import '../components/branded_field.dart';
import '../state/auth_controller.dart';
import '../theme/colors.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

class LoginScreen extends StatefulWidget {
  final AuthController auth;
  const LoginScreen({super.key, required this.auth});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;
  bool _sessionExpiredShown = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_sessionExpiredShown && widget.auth.consumeSessionExpiredFlag()) {
      _sessionExpiredShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Session expired, please log in again.')),
        );
      });
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Enter your email and password');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.auth.login(_email.text.trim(), _password.text);
    } on UnauthorizedException {
      setState(() => _error = 'Invalid email or password');
    } on ValidationException catch (e) {
      setState(() => _error = e.message);
    } catch (e, st) {
      // ignore: avoid_print
      print('LOGIN_ERR: ${e.runtimeType} :: $e\n$st');
      setState(() => _error = "Couldn't reach the server");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      backgroundColor: t.colorScheme.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: Spacing.xxl),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _AuthTopbar(busy: _busy),
                const SizedBox(height: Spacing.xxl),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('LOG IN', style: AppText.display(34)),
                      const SizedBox(height: 4),
                      Text(
                        'Back to the paddock.',
                        style: AppText.body(13,
                            color: t.colorScheme.onSurface.withOpacity(0.6)),
                      ),
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
                        fieldKey: const Key('login.email'),
                        label: 'EMAIL',
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        hint: 'you@example.com',
                      ),
                      const SizedBox(height: Spacing.md),
                      BrandedField(
                        fieldKey: const Key('login.password'),
                        label: 'PASSWORD',
                        controller: _password,
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
                        key: const Key('login.submit'),
                        label: _busy ? 'LOGGING IN…' : 'LOG IN',
                        trailing: Icons.arrow_forward,
                        background: BrandColors.accent,
                        foreground: Colors.white,
                        onTap: _busy ? null : _submit,
                      ),
                      const SizedBox(height: Spacing.lg),
                      _SecondaryLink(
                        label: 'No account? SIGN UP',
                        onTap: _busy ? null : () => context.go('/signup'),
                      ),
                      const SizedBox(height: Spacing.sm),
                      _SecondaryLink(
                        label: 'CHANGE PASSWORD',
                        onTap: _busy
                            ? null
                            : () => context.push('/change-password'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Branded F1 PG logo row that sits atop every auth / onboarding
/// screen. Mirrors the home screen's topbar so the user sees the same
/// brand before and after sign-in.
class _AuthTopbar extends StatelessWidget {
  final bool busy;
  const _AuthTopbar({required this.busy});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.xl, Spacing.lg, Spacing.xl, 0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            color: t.colorScheme.onSurface,
            child: Text('F1',
                style: AppText.display(14, color: t.colorScheme.surface)),
          ),
          const SizedBox(width: 4),
          Text('PG', style: AppText.display(14)),
        ],
      ),
    );
  }
}

/// Small caps text-button used for the SIGN UP / CHANGE PASSWORD
/// secondary actions. Matches the app's pill-label aesthetic without
/// pulling visual weight away from the primary BigPill.
class _SecondaryLink extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const _SecondaryLink({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Center(
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.all(Radius.circular(6)),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: Spacing.md, vertical: 6),
          child: Text(label,
              style: AppText.label(11,
                  color: t.colorScheme.onSurface.withOpacity(0.65))),
        ),
      ),
    );
  }
}
