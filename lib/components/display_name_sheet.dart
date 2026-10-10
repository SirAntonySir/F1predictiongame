import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../state/auth_controller.dart';
import '../theme/colors.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'branded_field.dart';
import 'branded_sheet.dart';

/// Rename yourself. Saves through [auth] so the signed-in user picks up the
/// new name; resolves true once it's saved. A clash with a league mate (the
/// backend's 409) stays in the sheet as an inline error so the user can try
/// another name — it's also the way out when joining a league fails on one.
Future<bool> showDisplayNameSheet(BuildContext context, AuthController auth) async {
  final saved = await showBrandedSheet<bool>(
    context,
    builder: (_) => _DisplayNameSheet(auth: auth),
  );
  return saved ?? false;
}

class _DisplayNameSheet extends StatefulWidget {
  final AuthController auth;
  const _DisplayNameSheet({required this.auth});

  @override
  State<_DisplayNameSheet> createState() => _DisplayNameSheetState();
}

class _DisplayNameSheetState extends State<_DisplayNameSheet> {
  late final _ctrl = TextEditingController(text: widget.auth.user?.displayName ?? '');
  bool _busy = false;
  String? _err;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _ctrl.text.trim();
    if (name.isEmpty) {
      setState(() => _err = 'Enter a name');
      return;
    }
    if (name == widget.auth.user?.displayName) {
      Navigator.of(context).pop(false);
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await widget.auth.api.patchMe(displayName: name);
      await widget.auth.refreshMe();
      if (mounted) Navigator.of(context).pop(true);
    } on ConflictException catch (e) {
      if (mounted) setState(() => _err = e.message);
    } on ValidationException catch (e) {
      if (mounted) setState(() => _err = e.message);
    } catch (_) {
      if (mounted) setState(() => _err = "Couldn't reach the server");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return BrandedSheet(
      title: 'Display name',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BrandedField(label: 'NAME', controller: _ctrl),
          const SizedBox(height: Spacing.sm),
          Text(
            'Shown to everyone in your league — it has to be unique there.',
            style: AppText.body(11,
                color: t.colorScheme.onSurface.withValues(alpha: 0.7)),
          ),
          if (_err != null) ...[
            const SizedBox(height: Spacing.xs),
            Text(_err!,
                style: AppText.body(12,
                    color: BrandColors.accent, weight: FontWeight.w700)),
          ],
        ],
      ),
      primaryLabel: _busy ? 'Saving…' : 'Save',
      onPrimary: _busy ? null : _submit,
      onSecondary: () => Navigator.of(context).pop(false),
    );
  }
}
