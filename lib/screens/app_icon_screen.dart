import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dynamic_icon_plus/flutter_dynamic_icon_plus.dart';
import 'package:go_router/go_router.dart';

import '../avatar/avatar_config.dart';
import '../avatar/avatar_palette.dart';
import '../components/branded_sheet.dart';
import '../components/branded_toast.dart';
import '../components/save_pill.dart';
import '../state/app_state.dart';
import '../state/avatar_controller.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// App-icon gallery: one baked launcher icon per pose × livery, in a dark
/// (#2E2C31) and a light (ticket cream) background set. Tapping a tile only
/// stages the choice (like the avatar builder) — SAVE persists it and
/// switches the OS icon (iOS shows its mandatory system alert).
class AppIconScreen extends StatefulWidget {
  /// Injectable for tests; the app resolves it from [AppState].
  final AvatarController? controller;
  const AppIconScreen({super.key, this.controller});

  @override
  State<AppIconScreen> createState() => _AppIconScreenState();
}

class _AppIconScreenState extends State<AppIconScreen> {
  /// Which background set the gallery shows. Seeded from the saved variant
  /// so reopening the screen lands on the set the user picked from.
  bool? _light;

  /// Unsaved tile pick; null = follow the saved config.
  String? _draft;

  AvatarController _avatar(BuildContext context) =>
      widget.controller ?? AppState.of(context).avatar;

  bool _dirty(AvatarController avatar) =>
      _draft != null && _draft != avatar.config.iconVariant;

  Future<void> _save(BuildContext context, AvatarController avatar) async {
    final id = _draft!;
    await avatar.setIconVariant(id);
    if (!context.mounted) return;
    String? problem;
    try {
      if (await FlutterDynamicIconPlus.supportsAlternateIcons) {
        // The default variant is the primary icon's own art — reset to
        // primary rather than switching to its (identical) alternate.
        await FlutterDynamicIconPlus.setAlternateIconName(
          iconName: id == AvatarConfig.defaultIcon ? null : id,
        );
        if (context.mounted) BrandedToast.show(context, 'App icon saved.');
        return;
      }
      problem = "Saved — but this device can't switch app icons.";
    } on MissingPluginException {
      // Running binary predates the icon plugin — a hot reload can't add it.
      problem = 'Saved — rebuild the app to enable icon switching.';
    } catch (e) {
      // Typically: this build doesn't have the tapped variant registered.
      debugPrint('setAlternateIconName($id) failed: $e');
      problem = "Saved — couldn't switch the icon on this build.";
    }
    if (context.mounted) BrandedToast.show(context, problem);
  }

  Future<void> _confirmLeave(AvatarController avatar) async {
    if (!_dirty(avatar)) {
      context.pop();
      return;
    }
    final discard = await BrandedSheet.confirm(
      context,
      title: 'Discard changes?',
      message: "Your app icon choice hasn't been saved.",
      primaryLabel: 'Discard',
      secondaryLabel: 'Keep editing',
    );
    if (discard && mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final avatar = _avatar(context);
    return PopScope(
      canPop: !_dirty(avatar),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave(avatar);
      },
      child: Scaffold(
        backgroundColor: t.colorScheme.surface,
        body: SafeArea(
          child: ListenableBuilder(
            listenable: avatar,
            builder: (context, _) {
              final selected = _draft ?? avatar.config.iconVariant;
              final light = _light ?? selected.endsWith('_light');
              return ListView(
                padding: const EdgeInsets.all(Spacing.lg),
                children: [
                  Row(children: [
                    IconButton(
                      onPressed: () => _confirmLeave(avatar),
                      icon: const Icon(Icons.arrow_back_ios_new, size: 16),
                    ),
                    Text('APP ICON', style: AppText.display(24)),
                    const Spacer(),
                    SavePill(
                      enabled: _dirty(avatar),
                      onTap: () => _save(context, avatar),
                    ),
                  ]),
                  const SizedBox(height: Spacing.sm),
                  Text(
                    'Your helmet, one per livery — icons are baked into the app.',
                    style: AppText.body(11,
                        color: t.colorScheme.onSurface.withValues(alpha: 0.55)),
                  ),
                  const SizedBox(height: Spacing.md),
                  Row(children: [
                    _BgPill(
                      label: 'DARK',
                      on: !light,
                      onTap: () => setState(() => _light = false),
                    ),
                    const SizedBox(width: 6),
                    _BgPill(
                      label: 'LIGHT',
                      on: light,
                      onTap: () => setState(() => _light = true),
                    ),
                  ]),
                  LayoutBuilder(builder: (context, constraints) {
                    // 4 tiles per row, sized to fill the content width.
                    // Floored so float rounding never pushes the 4th to a new row.
                    const cols = 4;
                    final tile =
                        ((constraints.maxWidth - Spacing.sm * (cols - 1)) /
                                cols)
                            .floorToDouble();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Baked poses only — a pose without bundled icon PNGs
                        // (and native registrations) has nothing to offer here.
                        // With the helmet-only set that's a single group, so the
                        // pose section header is dropped when there's just one.
                        for (final pose in AvatarPose.values
                            .where((p) => p.hasBakedIcons)) ...[
                          const SizedBox(height: Spacing.lg),
                          if (AvatarPose.values
                                  .where((p) => p.hasBakedIcons)
                                  .length >
                              1) ...[
                            Text(pose.label.toUpperCase(),
                                style: AppText.label(9,
                                    color: t.colorScheme.onSurface
                                        .withValues(alpha: 0.45))),
                            const SizedBox(height: Spacing.sm),
                          ],
                          Wrap(
                            spacing: Spacing.sm,
                            runSpacing: Spacing.md,
                            children: [
                              for (final preset in avatarPresets)
                                _IconTile(
                                  size: tile,
                                  label: preset.name,
                                  variant: AvatarConfig.iconId(pose, preset,
                                      light: light),
                                  selected: selected ==
                                      AvatarConfig.iconId(pose, preset,
                                          light: light),
                                  onTap: () => setState(() => _draft =
                                      AvatarConfig.iconId(pose, preset,
                                          light: light)),
                                ),
                            ],
                          ),
                        ],
                      ],
                    );
                  }),
                  const SizedBox(height: Spacing.xl),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// DARK / LIGHT background-set selector pill.
class _BgPill extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback onTap;
  const _BgPill({required this.label, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: 7),
        decoration: BoxDecoration(
          color: on ? t.colorScheme.onSurface : Colors.transparent,
          border: Border.all(color: t.strokeColor, width: 1.5),
          borderRadius: const BorderRadius.all(Radius.circular(8)),
        ),
        child: Text(label,
            style: AppText.label(10,
                color: on ? t.colorScheme.surface : t.colorScheme.onSurface)),
      ),
    );
  }
}

/// A real preview of a baked launcher icon (from assets/avatar/icons/),
/// with the variant name below.
class _IconTile extends StatelessWidget {
  final double size;
  final String label;
  final String variant;
  final bool selected;
  final VoidCallback onTap;
  const _IconTile({
    required this.size,
    required this.label,
    required this.variant,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: size,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              borderRadius: Radii.rMd,
              border: Border.all(
                color: selected ? BrandColors.accent : t.strokeColor,
                width: selected ? 2 : Strokes.subtle,
              ),
            ),
            child: ClipRRect(
              borderRadius: Radii.rMd,
              child: Image.asset(
                'assets/avatar/icons/$variant.png',
                fit: BoxFit.cover,
                // A variant registered natively but whose PNG isn't bundled
                // (bake out of sync, or a just-added file the running build
                // predates) degrades to a neutral placeholder instead of a
                // red error box.
                errorBuilder: (context, _, __) => ColoredBox(
                  color: t.mutedSurface,
                  child: Center(
                    child: Icon(
                      Icons.image_not_supported_outlined,
                      size: size * 0.3,
                      color: t.colorScheme.onSurface.withValues(alpha: 0.3),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: Spacing.xs),
          Text(label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppText.label(9,
                  color: t.colorScheme.onSurface
                      .withValues(alpha: selected ? 1 : 0.6))),
        ]),
      ),
    );
  }
}
