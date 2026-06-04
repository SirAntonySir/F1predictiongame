// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api/api_client.dart';
import '../components/app_card.dart';
import '../components/big_pill.dart';
import '../components/branded_field.dart';
import '../components/racing_stripes.dart';
import '../state/auth_controller.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// First-run screen for users without a league. Two stark choices:
/// claim a ticket (join an existing league) or print one (create your own).
///
/// Visual language mirrors the home screen — cream tickets for the join
/// flow + brand-red striped pavilion for the create flow — so the user
/// sees the app's actual aesthetic before they ever touch the home tab.
class LeagueOnboardingScreen extends StatefulWidget {
  final AuthController auth;
  const LeagueOnboardingScreen({super.key, required this.auth});

  @override
  State<LeagueOnboardingScreen> createState() => _LeagueOnboardingScreenState();
}

class _LeagueOnboardingScreenState extends State<LeagueOnboardingScreen> {
  final _joinCode = TextEditingController();
  final _joinPassword = TextEditingController();
  final _createName = TextEditingController();
  final _createPassword = TextEditingController();
  String? _joinError;
  String? _createError;
  bool _busy = false;

  @override
  void dispose() {
    _joinCode.dispose();
    _joinPassword.dispose();
    _createName.dispose();
    _createPassword.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    if (_busy) return;
    final code = _joinCode.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() => _joinError = 'Enter a join code');
      return;
    }
    setState(() {
      _busy = true;
      _joinError = null;
    });
    try {
      await widget.auth.api.joinLeague(
        code: code,
        password: _joinPassword.text.isEmpty ? null : _joinPassword.text,
      );
      await widget.auth.refreshMe();
    } on NotFoundException {
      setState(() => _joinError = 'Unknown join code.');
    } on ForbiddenException catch (e) {
      // Password gate failures (missing or wrong) surface as FORBIDDEN
      // so the auth session isn't wiped; surface the message verbatim.
      setState(() => _joinError = e.message);
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
    final pwInput = _createPassword.text;
    if (pwInput.isNotEmpty && pwInput.length < 4) {
      setState(() => _createError =
          'Password must be at least 4 characters (or leave empty)');
      return;
    }
    setState(() {
      _busy = true;
      _createError = null;
    });
    try {
      await widget.auth.api.createLeague(
        name: name,
        password: pwInput.isEmpty ? null : pwInput,
      );
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
    final t = Theme.of(context);
    return Scaffold(
      backgroundColor: t.colorScheme.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: Spacing.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _topbar(t),
              const SizedBox(height: Spacing.lg),
              _displayHeader(t),
              const SizedBox(height: Spacing.lg),
              // Stacked on phones, side-by-side on iPad. The cards have
              // intentionally different colour weights — cream vs brand
              // red — so the choice reads at a glance.
              LayoutBuilder(builder: (ctx, constraints) {
                final twoCol = constraints.maxWidth >= 700;
                final join = _JoinCard(
                  code: _joinCode,
                  password: _joinPassword,
                  error: _joinError,
                  busy: _busy,
                  onSubmit: _join,
                );
                final create = _CreateCard(
                  name: _createName,
                  password: _createPassword,
                  error: _createError,
                  busy: _busy,
                  onSubmit: _create,
                );
                if (!twoCol) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                            Spacing.lg, 0, Spacing.lg, Spacing.lg),
                        child: join,
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                            Spacing.lg, 0, Spacing.lg, Spacing.lg),
                        child: create,
                      ),
                    ],
                  );
                }
                return Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.lg),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: join),
                        const SizedBox(width: Spacing.md),
                        Expanded(child: create),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topbar(ThemeData t) => Padding(
        padding: const EdgeInsets.fromLTRB(
            Spacing.xl, Spacing.lg, Spacing.xl, 0),
        child: Row(
          children: [
            // F1 PG monogram — same plate used on home so the user
            // immediately recognises the brand on first launch.
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              color: t.colorScheme.onSurface,
              child: Text('F1',
                  style: AppText.display(14, color: t.colorScheme.surface)),
            ),
            const SizedBox(width: 4),
            Text('PG', style: AppText.display(14)),
            const Spacer(),
            // Sign out as an outlined pill so it reads as a secondary
            // affordance instead of stealing focus from the two cards.
            InkWell(
              key: const Key('onboarding.signOut'),
              onTap: _busy ? null : () => widget.auth.logout(),
              borderRadius: const BorderRadius.all(Radius.circular(999)),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.md, vertical: 5),
                decoration: BoxDecoration(
                  border: Border.all(color: t.strokeColor, width: 1.5),
                  borderRadius:
                      const BorderRadius.all(Radius.circular(999)),
                ),
                child: Text('SIGN OUT', style: AppText.label(11)),
              ),
            ),
          ],
        ),
      );

  Widget _displayHeader(ThemeData t) => Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: Spacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ENTER THE PADDOCK', style: AppText.display(28)),
            const SizedBox(height: 4),
            Text(
              'Join an existing league — or start your own.',
              style: AppText.body(13,
                  color: t.colorScheme.onSurface.withOpacity(0.6)),
            ),
          ],
        ),
      );
}

/// Cream "ticket" card that hosts the join form. Visual language
/// matches the home screen's pick card so a returning user instantly
/// recognises the surface.
class _JoinCard extends StatelessWidget {
  final TextEditingController code;
  final TextEditingController password;
  final String? error;
  final bool busy;
  final VoidCallback onSubmit;
  const _JoinCard({
    required this.code,
    required this.password,
    required this.error,
    required this.busy,
    required this.onSubmit,
  });

  static const _bg = Color(0xFFFFF1B8);

  @override
  Widget build(BuildContext context) {
    return AppCard(
      background: _bg,
      padding: const EdgeInsets.fromLTRB(
          Spacing.xl, Spacing.xl, Spacing.xl, Spacing.xl),
      // Force a dark default text colour: the cream stock stays cream in
      // both themes, so the body's onSurface would render white-on-cream
      // in dark mode otherwise.
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: Colors.black),
        child: IconTheme.merge(
          data: const IconThemeData(color: Colors.black),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('JOIN AN EXISTING LEAGUE',
                  style: AppText.label(10,
                      color: Colors.black.withOpacity(0.55))),
              const SizedBox(height: Spacing.sm),
              Text('GOT A CODE?',
                  style: AppText.display(26, color: Colors.black)),
              const SizedBox(height: 6),
              Text(
                'Drop the code your league owner sent you, plus the password if they set one.',
                style: AppText.body(12,
                    color: Colors.black.withOpacity(0.7)),
              ),
              const SizedBox(height: Spacing.lg),
              BrandedField(
                fieldKey: const Key('onboarding.joinCode'),
                label: 'JOIN CODE',
                controller: code,
                onDark: false,
                hint: 'e.g. ABCD1234',
                inputFormatters: [
                  TextInputFormatter.withFunction(
                      (old, n) => n.copyWith(text: n.text.toUpperCase())),
                ],
              ),
              const SizedBox(height: Spacing.md),
              BrandedField(
                fieldKey: const Key('onboarding.joinPassword'),
                label: 'PASSWORD',
                controller: password,
                onDark: false,
                obscure: true,
                hint: 'Only if your league has one',
              ),
              if (error != null) ...[
                const SizedBox(height: Spacing.md),
                Text(error!,
                    style: AppText.body(12,
                        color: BrandColors.accent,
                        weight: FontWeight.w700)),
              ],
              const SizedBox(height: Spacing.lg),
              BigPill(
                key: const Key('onboarding.joinSubmit'),
                label: busy ? 'JOINING…' : 'JOIN LEAGUE',
                trailing: Icons.arrow_forward,
                background: Colors.black,
                foreground: Colors.white,
                onTap: busy ? null : onSubmit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Red, racing-striped pavilion that hosts the create form. Echoes the
/// home hero so the create choice feels "louder" than join — being the
/// owner is the bigger commitment.
class _CreateCard extends StatelessWidget {
  final TextEditingController name;
  final TextEditingController password;
  final String? error;
  final bool busy;
  final VoidCallback onSubmit;
  const _CreateCard({
    required this.name,
    required this.password,
    required this.error,
    required this.busy,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      background: BrandColors.accent,
      padding: EdgeInsets.zero,
      child: Stack(
        children: [
          const Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: RacingStripesPainter()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Spacing.xl, Spacing.xl, Spacing.xl, Spacing.xl),
            child: DefaultTextStyle.merge(
              style: const TextStyle(color: Colors.white),
              child: IconTheme.merge(
                data: const IconThemeData(color: Colors.white),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('CREATE YOUR OWN',
                        style: AppText.label(10,
                            color: Colors.white.withOpacity(0.85))),
                    const SizedBox(height: Spacing.sm),
                    Text('RUN THE SHOW',
                        style: AppText.display(26, color: Colors.white)),
                    const SizedBox(height: 6),
                    Text(
                      'Up to 3 mates free. Upgrade later for bigger leagues.',
                      style: AppText.body(12,
                          color: Colors.white.withOpacity(0.9)),
                    ),
                    const SizedBox(height: Spacing.lg),
                    BrandedField(
                      fieldKey: const Key('onboarding.createName'),
                      label: 'LEAGUE NAME',
                      controller: name,
                      onDark: true,
                      hint: 'The Box, Pit Crew, …',
                    ),
                    const SizedBox(height: Spacing.md),
                    BrandedField(
                      fieldKey: const Key('onboarding.createPassword'),
                      label: 'PASSWORD (OPTIONAL)',
                      controller: password,
                      onDark: true,
                      obscure: true,
                      hint: 'Leave empty for an open league',
                    ),
                    if (error != null) ...[
                      const SizedBox(height: Spacing.md),
                      Text(error!,
                          style: AppText.body(12,
                              color: Colors.white, weight: FontWeight.w700)),
                    ],
                    const SizedBox(height: Spacing.lg),
                    BigPill(
                      key: const Key('onboarding.createSubmit'),
                      label: busy ? 'CREATING…' : 'CREATE LEAGUE',
                      trailing: Icons.arrow_forward,
                      background: Colors.white,
                      foreground: Colors.black,
                      onTap: busy ? null : onSubmit,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

