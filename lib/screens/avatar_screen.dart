import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../avatar/avatar_config.dart';
import '../avatar/avatar_palette.dart';
import '../components/branded_sheet.dart';
import '../components/branded_toast.dart';
import '../components/color_picker_sheet.dart';
import '../components/painted_splash.dart';
import '../components/save_pill.dart';
import '../state/app_state.dart';
import '../state/avatar_controller.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// Avatar builder: live preview of the driver artwork, team-preset chips,
/// and a per-region color picker. Edits happen on a local draft — nothing
/// persists until the user taps SAVE. The launcher icon has its own screen
/// (AppIconScreen).
class AvatarScreen extends StatefulWidget {
  /// Injectable for tests; the app resolves it from [AppState].
  final AvatarController? controller;
  const AvatarScreen({super.key, this.controller});

  @override
  State<AvatarScreen> createState() => _AvatarScreenState();
}

class _AvatarScreenState extends State<AvatarScreen> {
  AvatarController? _controller;
  late AvatarConfig _draft;

  AvatarController _resolve(BuildContext context) =>
      widget.controller ?? AppState.of(context).avatar;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller == null) {
      _controller = _resolve(context);
      _draft = _controller!.config;
    }
  }

  bool get _dirty => _draft.toJson() != _controller!.config.toJson();

  void _edit(AvatarConfig next) => setState(() => _draft = next);

  /// The color shown for a region: the user's raw pick when overridden — so
  /// the picker round-trips exactly (#000000 stays #000000) — otherwise the
  /// effective op's swatch.
  Color _regionColor(AvatarConfig config, AvatarRegion region) =>
      config.overrides[region] ?? region.swatchFor(config.ops);

  Future<void> _save() async {
    await _controller!.save(_draft);
    setState(() {});
    if (mounted) BrandedToast.show(context, 'Avatar saved.');
  }

  Future<void> _confirmLeave() async {
    if (!_dirty) {
      context.pop();
      return;
    }
    final discard = await BrandedSheet.confirm(
      context,
      title: 'Discard changes?',
      message: "Your avatar edits haven't been saved.",
      primaryLabel: 'Discard',
      secondaryLabel: 'Keep editing',
    );
    if (discard && mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final config = _draft;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        backgroundColor: t.colorScheme.surface,
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(Spacing.lg),
            children: [
              Row(children: [
                IconButton(
                  onPressed: _confirmLeave,
                  icon: const Icon(Icons.arrow_back_ios_new, size: 16),
                ),
                Text('AVATAR', style: AppText.display(24)),
                const Spacer(),
                SavePill(enabled: _dirty, onTap: _save),
              ]),
              const SizedBox(height: Spacing.sm),
              // Preview replays the sketch-draw animation when the preset or
              // pose changes (key swap); single-region tweaks recolor in
              // place without restarting (PaintedSplash.didUpdateWidget).
              SizedBox(
                height: 300,
                child: PaintedSplash(
                  key: ValueKey(
                      'avatar-preview-${config.presetId}-${config.pose.name}'),
                  asset: config.pose.asset,
                  ops: config.ops,
                  // Snappier than the boot splash: this replays on every
                  // preset/pose switch.
                  duration: const Duration(milliseconds: 1200),
                ),
              ),
              const SizedBox(height: Spacing.lg),
              Text('POSE', style: AppText.label(11)),
              const SizedBox(height: Spacing.sm),
              Row(children: [
                for (final pose in AvatarPose.values)
                  Padding(
                    padding: const EdgeInsets.only(right: Spacing.xs),
                    child: _PoseChip(
                      pose: pose,
                      selected: pose == config.pose,
                      onTap: () => _edit(config.copyWith(pose: pose)),
                    ),
                  ),
              ]),
              const SizedBox(height: Spacing.xl),
              Text('LIVERY', style: AppText.label(11)),
              const SizedBox(height: Spacing.sm),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                child: Row(children: [
                  for (final preset in avatarPresets)
                    Padding(
                      padding: const EdgeInsets.only(right: Spacing.xs),
                      child: _PresetChip(
                        preset: preset,
                        selected:
                            preset.id == config.presetId && !config.isCustom,
                        onTap: () => _edit(config.copyWith(
                            presetId: preset.id, overrides: const {})),
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: Spacing.xl),
              Row(children: [
                Expanded(child: Text('COLORS', style: AppText.label(11))),
                if (config.isCustom)
                  GestureDetector(
                    onTap: () => _edit(config.copyWith(overrides: const {})),
                    child: Text('RESET',
                        style: AppText.label(11, color: BrandColors.accent)),
                  ),
              ]),
              const SizedBox(height: Spacing.sm),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: t.strokeColor, width: Strokes.card),
                  borderRadius: Radii.rLg,
                ),
                child: Column(children: [
                  for (final region in AvatarRegion.values) ...[
                    if (region != AvatarRegion.values.first)
                      Divider(
                          height: 1,
                          thickness: Strokes.subtle,
                          color: t.strokeColor.withValues(alpha: 0.4)),
                    _RegionRow(
                      region: region,
                      color: _regionColor(config, region),
                      edited: config.overrides.containsKey(region),
                      onTap: () async {
                        final picked = await showColorPickerSheet(
                          context,
                          title: region.label,
                          initial: _regionColor(config, region),
                          // Every other region's current color, so the user
                          // can tap to match liveries across regions.
                          matchColors: [
                            for (final other in AvatarRegion.values)
                              if (other != region)
                                (
                                  label: other.label,
                                  color: _regionColor(config, other)
                                ),
                          ],
                        );
                        if (picked != null) {
                          _edit(config.copyWith(overrides: {
                            ...config.overrides,
                            region: picked
                          }));
                        }
                      },
                    ),
                  ],
                ]),
              ),
              const SizedBox(height: Spacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}

class _PoseChip extends StatelessWidget {
  final AvatarPose pose;
  final bool selected;
  final VoidCallback onTap;
  const _PoseChip(
      {required this.pose, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md, vertical: Spacing.xs),
        decoration: BoxDecoration(
          color: selected ? BrandColors.accent : null,
          border: Border.all(color: t.strokeColor, width: Strokes.subtle),
          borderRadius: Radii.rSm,
        ),
        child: Text(pose.label.toUpperCase(),
            style: AppText.label(11,
                color: selected ? Colors.white : t.colorScheme.onSurface)),
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  final AvatarPreset preset;
  final bool selected;
  final VoidCallback onTap;
  const _PresetChip(
      {required this.preset, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md, vertical: Spacing.sm),
        decoration: BoxDecoration(
          border: Border.all(
            color: selected ? t.colorScheme.onSurface : t.strokeColor,
            width: selected ? Strokes.card : Strokes.subtle,
          ),
          borderRadius: Radii.rMd,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: preset.swatch,
              shape: BoxShape.circle,
              border: Border.all(color: t.strokeColor, width: Strokes.subtle),
            ),
          ),
          const SizedBox(height: Spacing.xxs),
          Text(preset.name.toUpperCase(),
              style: AppText.label(9,
                  color: t.colorScheme.onSurface
                      .withValues(alpha: selected ? 1 : 0.6))),
        ]),
      ),
    );
  }
}

class _RegionRow extends StatelessWidget {
  final AvatarRegion region;
  final Color color;
  final bool edited;
  final VoidCallback onTap;
  const _RegionRow({
    required this.region,
    required this.color,
    required this.edited,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: Spacing.lg, vertical: Spacing.md),
        child: Row(children: [
          Expanded(
            child: Text(region.label,
                style: AppText.body(14, weight: FontWeight.w600)),
          ),
          if (edited)
            Padding(
              padding: const EdgeInsets.only(right: Spacing.sm),
              child: Text('EDITED',
                  style: AppText.label(9,
                      color: t.colorScheme.onSurface.withValues(alpha: 0.4))),
            ),
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: t.strokeColor, width: Strokes.subtle),
            ),
          ),
        ]),
      ),
    );
  }
}
