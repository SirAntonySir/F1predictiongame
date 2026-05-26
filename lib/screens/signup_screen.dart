import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../api/api_client.dart';
import '../state/auth_controller.dart';

class SignupScreen extends StatefulWidget {
  final AuthController auth;
  const SignupScreen({super.key, required this.auth});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
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
    if (!_formKey.currentState!.validate()) return;
    setState(() { _busy = true; _error = null; });
    try {
      await widget.auth.signup(_email.text.trim(), _password.text, _displayName.text.trim());
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
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 40),
                Text('Sign up', style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 24),
                TextFormField(
                  key: const Key('signup.email'),
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('signup.password'),
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password (min 8 chars)'),
                  validator: (v) => (v == null || v.length < 8) ? 'Must be at least 8 characters' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('signup.displayName'),
                  controller: _displayName,
                  decoration: const InputDecoration(labelText: 'Display name'),
                  validator: (v) {
                    final s = v?.trim() ?? '';
                    if (s.isEmpty) return 'Required';
                    if (s.length > 40) return 'Max 40 chars';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                FilledButton(
                  key: const Key('signup.submit'),
                  onPressed: _busy ? null : _submit,
                  child: Text(_busy ? 'Creating...' : 'Create account'),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _busy ? null : () => context.go('/login'),
                  child: const Text('Already have an account? Log in'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
