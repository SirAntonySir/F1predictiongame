import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api/api_client.dart';
import '../state/auth_controller.dart';

class LeagueOnboardingScreen extends StatefulWidget {
  final AuthController auth;
  const LeagueOnboardingScreen({super.key, required this.auth});

  @override
  State<LeagueOnboardingScreen> createState() => _LeagueOnboardingScreenState();
}

class _LeagueOnboardingScreenState extends State<LeagueOnboardingScreen> {
  final _joinCode = TextEditingController();
  final _createName = TextEditingController();
  String? _joinError;
  String? _createError;
  bool _busy = false;

  @override
  void dispose() {
    _joinCode.dispose();
    _createName.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    if (_busy) return;
    final code = _joinCode.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() => _joinError = 'Enter a join code');
      return;
    }
    setState(() { _busy = true; _joinError = null; });
    try {
      await widget.auth.api.joinLeague(code: code);
      await widget.auth.refreshMe();
    } on NotFoundException {
      setState(() => _joinError = 'Unknown join code.');
    } on ConflictException catch (e) {
      setState(() => _joinError = e.message);
    } catch (_) {
      setState(() => _joinError = "Couldn't reach the server");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    if (_busy) return;
    final name = _createName.text.trim();
    if (name.isEmpty) {
      setState(() => _createError = 'Enter a league name');
      return;
    }
    if (name.length > 40) {
      setState(() => _createError = 'Max 40 chars');
      return;
    }
    setState(() { _busy = true; _createError = null; });
    try {
      await widget.auth.api.createLeague(name: name);
      await widget.auth.refreshMe();
    } on ConflictException catch (e) {
      setState(() => _createError = e.message);
    } on ValidationException catch (e) {
      setState(() => _createError = e.message);
    } catch (_) {
      setState(() => _createError = "Couldn't reach the server");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Join or create a league')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('Join a league', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('onboarding.joinCode'),
                    controller: _joinCode,
                    decoration: const InputDecoration(labelText: 'Join code'),
                    inputFormatters: [
                      TextInputFormatter.withFunction((old, n) => n.copyWith(text: n.text.toUpperCase())),
                    ],
                  ),
                  if (_joinError != null) Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_joinError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    key: const Key('onboarding.joinSubmit'),
                    onPressed: _busy ? null : _join,
                    child: const Text('Join'),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('Create your own', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('onboarding.createName'),
                    controller: _createName,
                    decoration: const InputDecoration(labelText: 'League name'),
                  ),
                  if (_createError != null) Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_createError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    key: const Key('onboarding.createSubmit'),
                    onPressed: _busy ? null : _create,
                    child: const Text('Create'),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
