import 'dart:convert';

import 'package:flutter/material.dart';

import 'avatar_palette.dart';

/// The user's saved avatar: a preset plus optional per-region picked colors
/// layered on top, and the chosen app-icon variant (preset liveries only —
/// icons must be bundled at build time).
class AvatarConfig {
  /// The default launcher icon. The primary app icon (AppIcon.appiconset /
  /// mipmap ic_launcher) is baked from the same art, so selecting this
  /// variant resets to the primary icon instead of setting an alternate.
  static const defaultIcon = 'pose1_undercut';

  final String presetId;
  final Map<AvatarRegion, Color> overrides;
  final String iconVariant;
  final AvatarPose pose;

  const AvatarConfig({
    this.presetId = 'undercut',
    this.overrides = const {},
    this.iconVariant = defaultIcon,
    this.pose = AvatarPose.pose1,
  });

  /// Icon variant id for a pose/livery/background combination, e.g.
  /// `pose1_rosso` (dark #2E2C31 background) or `pose1_rosso_light` (ticket
  /// cream). These names are baked into the platform registrations
  /// (Info.plist, AndroidManifest) — change them only together with a
  /// re-bake (test/tools/bake_icons_test.dart holds the crop framing).
  static String iconId(AvatarPose pose, AvatarPreset preset,
          {bool light = false}) =>
      '${pose.name}_${preset.id}${light ? '_light' : ''}';

  /// Every selectable icon variant: baked pose × livery × background.
  /// Poses without baked icons (splash/builder-only) offer none.
  static List<String> get iconVariants => [
        for (final pose in AvatarPose.values)
          if (pose.hasBakedIcons)
            for (final preset in avatarPresets) ...[
              iconId(pose, preset),
              iconId(pose, preset, light: true),
            ],
      ];

  /// Valid icon variants: a baked pose × livery (± `_light`). Legacy ids
  /// migrate — bare preset ids (pre-pose era) to their pose-1 variant,
  /// everything else (including the retired 'classic' ticket icon and poses
  /// without baked icons) to the default.
  static String validIconVariant(String? id) {
    if (id == null) return defaultIcon;
    if (avatarPresets.any((p) => p.id == id)) return 'pose1_$id';
    var base = id;
    if (base.endsWith('_light')) {
      base = base.substring(0, base.length - '_light'.length);
    }
    final sep = base.indexOf('_');
    if (sep > 0) {
      final pose = base.substring(0, sep);
      final preset = base.substring(sep + 1);
      if (AvatarPose.values.any((p) => p.name == pose && p.hasBakedIcons) &&
          avatarPresets.any((p) => p.id == preset)) {
        return id;
      }
    }
    return defaultIcon;
  }

  bool get isCustom => overrides.isNotEmpty;

  /// The effective per-region ops: preset as the base, picked colors on top.
  Map<AvatarRegion, RegionOp> get ops => {
        ...presetById(presetId).ops,
        for (final e in overrides.entries) e.key: opForPickedColor(e.value),
      };

  AvatarConfig copyWith({
    String? presetId,
    Map<AvatarRegion, Color>? overrides,
    String? iconVariant,
    AvatarPose? pose,
  }) =>
      AvatarConfig(
        presetId: presetId ?? this.presetId,
        overrides: overrides ?? this.overrides,
        iconVariant: iconVariant ?? this.iconVariant,
        pose: pose ?? this.pose,
      );

  String toJson() => jsonEncode({
        'preset': presetId,
        'overrides': {
          for (final e in overrides.entries)
            e.key.name: e.value.toARGB32(),
        },
        'icon': iconVariant,
        'pose': pose.name,
      });

  /// Tolerant parse: unknown regions and malformed input fall back to
  /// defaults rather than breaking boot.
  static AvatarConfig fromJson(String? raw) {
    if (raw == null) return const AvatarConfig();
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final rawOverrides =
          (map['overrides'] as Map<String, dynamic>?) ?? const {};
      return AvatarConfig(
        presetId: presetById(map['preset'] as String?).id,
        overrides: {
          for (final e in rawOverrides.entries)
            for (final region in AvatarRegion.values)
              if (region.name == e.key && e.value is int)
                region: Color(e.value as int),
        },
        iconVariant: validIconVariant(map['icon'] as String?),
        pose: AvatarPose.byName(map['pose'] as String?),
      );
    } catch (_) {
      return const AvatarConfig();
    }
  }
}
