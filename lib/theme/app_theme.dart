import 'package:flutter/material.dart';
import 'colors.dart';
import 'typography.dart';

class AppTheme {
  static ThemeData light() => _build(
        brightness: Brightness.light,
        surface: LightPalette.surface,
        surfaceMuted: LightPalette.surfaceMuted,
        stroke: LightPalette.stroke,
        onSurface: LightPalette.onSurface,
        highlight: LightPalette.highlight,
      );

  static ThemeData dark() => _build(
        brightness: Brightness.dark,
        surface: DarkPalette.surface,
        surfaceMuted: DarkPalette.surfaceMuted,
        stroke: DarkPalette.stroke,
        onSurface: DarkPalette.onSurface,
        highlight: DarkPalette.highlight,
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color surface,
    required Color surfaceMuted,
    required Color stroke,
    required Color onSurface,
    required Color highlight,
  }) {
    final base = brightness == Brightness.light
        ? ThemeData.light(useMaterial3: true)
        : ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: surface,
      colorScheme: base.colorScheme.copyWith(
        primary: BrandColors.accent,
        surface: surface,
        onSurface: onSurface,
        outline: stroke,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: onSurface,
        displayColor: onSurface,
        fontFamily: AppText.body(14).fontFamily,
      ),
      extensions: <ThemeExtension<dynamic>>[
        _AppSurfaces(muted: surfaceMuted, stroke: stroke, highlight: highlight),
      ],
    );
  }
}

class _AppSurfaces extends ThemeExtension<_AppSurfaces> {
  final Color muted;
  final Color stroke;
  final Color highlight;
  const _AppSurfaces({required this.muted, required this.stroke, required this.highlight});

  @override
  _AppSurfaces copyWith({Color? muted, Color? stroke, Color? highlight}) => _AppSurfaces(
        muted: muted ?? this.muted,
        stroke: stroke ?? this.stroke,
        highlight: highlight ?? this.highlight,
      );

  @override
  _AppSurfaces lerp(ThemeExtension<_AppSurfaces>? other, double t) {
    if (other is! _AppSurfaces) return this;
    return _AppSurfaces(
      muted: Color.lerp(muted, other.muted, t)!,
      stroke: Color.lerp(stroke, other.stroke, t)!,
      highlight: Color.lerp(highlight, other.highlight, t)!,
    );
  }
}

extension AppSurfacesX on ThemeData {
  Color get mutedSurface => extension<_AppSurfaces>()?.muted ?? LightPalette.surfaceMuted;
  Color get strokeColor => extension<_AppSurfaces>()?.stroke ?? LightPalette.stroke;
  Color get rowHighlight => extension<_AppSurfaces>()?.highlight ?? LightPalette.highlight;
}
