import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../api/api_client.dart';
import '../state/auth_controller.dart';

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
    setState(() { _busy = true; _error = null; });
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
                Text('Log in', style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 24),
                TextFormField(
                  key: const Key('login.email'),
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('login.password'),
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password'),
                  validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                FilledButton(
                  key: const Key('login.submit'),
                  onPressed: _busy ? null : _submit,
                  child: Text(_busy ? 'Logging in...' : 'Log in'),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _busy ? null : () => context.go('/signup'),
                  child: const Text('No account? Sign up'),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => context.push('/change-password'),
                  child: const Text('Change password'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
