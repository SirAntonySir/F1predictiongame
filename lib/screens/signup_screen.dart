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

class SignupScreen extends StatefulWidget {
  final AuthController auth;
  const SignupScreen({super.key, required this.auth});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _displayName = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _displayName.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final pw = _password.text;
    final name = _displayName.text.trim();
    if (email.isEmpty || pw.isEmpty || name.isEmpty) {
      setState(() => _error = 'Email, password and display name are required');
      return;
    }
    if (pw.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters');
      return;
    }
    if (name.length > 40) {
      setState(() => _error = 'Display name max 40 chars');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.auth.signup(email, pw, name);
    } on ConflictException catch (e) {
      setState(() => _error = e.message);
    } on ValidationException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = "Couldn't create account");
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    Spacing.xl, Spacing.lg, Spacing.xl, 0),
                child: Row(
                  children: [
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      color: t.colorScheme.onSurface,
                      child: Text('UNDER',
                          style:
                              AppText.display(14, color: t.colorScheme.surface)),
                    ),
                    const SizedBox(width: 4),
                    Text('CUT', style: AppText.display(14)),
                  ],
                ),
              ),
              const SizedBox(height: Spacing.xxl),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('SIGN UP', style: AppText.display(34)),
                    const SizedBox(height: 4),
                    Text(
                      'Get a paddock pass — picks, scores, gossip.',
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
                      fieldKey: const Key('signup.email'),
                      label: 'EMAIL',
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      hint: 'you@example.com',
                    ),
                    const SizedBox(height: Spacing.md),
                    BrandedField(
                      fieldKey: const Key('signup.displayName'),
                      label: 'DISPLAY NAME',
                      controller: _displayName,
                      hint: 'How others see you',
                    ),
                    const SizedBox(height: Spacing.md),
                    BrandedField(
                      fieldKey: const Key('signup.password'),
                      label: 'PASSWORD',
                      controller: _password,
                      obscure: true,
                      hint: 'At least 8 characters',
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
                      key: const Key('signup.submit'),
                      label: _busy ? 'CREATING…' : 'CREATE ACCOUNT',
                      trailing: Icons.arrow_forward,
                      background: BrandColors.accent,
                      foreground: Colors.white,
                      onTap: _busy ? null : _submit,
                    ),
                    const SizedBox(height: Spacing.lg),
                    Center(
                      child: InkWell(
                        onTap: _busy ? null : () => context.go('/login'),
                        borderRadius: const BorderRadius.all(Radius.circular(6)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: Spacing.md, vertical: 6),
                          child: Text('Already in? LOG IN',
                              style: AppText.label(11,
                                  color: t.colorScheme.onSurface.withOpacity(0.65))),
                        ),
                      ),
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
