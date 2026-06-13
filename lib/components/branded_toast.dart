// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

enum ToastTone { neutral, ok, error }

/// Brand-styled transient confirmation that drops from the top of the screen.
/// Drop-in replacement for `ScaffoldMessenger.showSnackBar` for short
/// single-line confirmations and errors.
///
///   BrandedToast.show(context, 'Picks locked', tone: ToastTone.ok);
class BrandedToast {
  static OverlayEntry? _current;
  static Timer? _timer;
  static _ToastState? _state;

  static void show(
    BuildContext context,
    String message, {
    ToastTone tone = ToastTone.neutral,
    Duration duration = const Duration(milliseconds: 2500),
  }) {
    _dismiss(immediate: true);
    final overlay = Overlay.of(context, rootOverlay: true);
    final key = GlobalKey<_ToastState>();
    final entry = OverlayEntry(
      builder: (_) => _Toast(key: key, message: message, tone: tone),
    );
    _current = entry;
    overlay.insert(entry);
    // Cache the state once it's mounted so we can drive the exit animation.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _state = key.currentState;
    });
    _timer = Timer(duration, () => _dismiss());
  }

  static void _dismiss({bool immediate = false}) {
    _timer?.cancel();
    _timer = null;
    final entry = _current;
    final state = _state;
    if (entry == null) return;
    if (immediate || state == null) {
      entry.remove();
      _current = null;
      _state = null;
      return;
    }
    state.hide();
    Future.delayed(_Toast.fade, () {
      if (_current == entry) {
        entry.remove();
        _current = null;
        _state = null;
      }
    });
  }
}

class _Toast extends StatefulWidget {
  static const fade = Duration(milliseconds: 180);
  final String message;
  final ToastTone tone;
  const _Toast({super.key, required this.message, required this.tone});

  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _visible = true);
    });
  }

  void hide() {
    if (!mounted) return;
    setState(() => _visible = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final dot = switch (widget.tone) {
      ToastTone.ok => BrandColors.ok,
      ToastTone.error => BrandColors.accent,
      ToastTone.neutral => t.colorScheme.onSurface,
    };
    final media = MediaQuery.of(context);
    return Positioned(
      top: media.padding.top + Spacing.sm,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: AnimatedSlide(
          duration: _Toast.fade,
          curve: Curves.easeOut,
          offset: _visible ? Offset.zero : const Offset(0, -0.5),
          child: AnimatedOpacity(
            duration: _Toast.fade,
            opacity: _visible ? 1 : 0,
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: media.size.width - Spacing.xxl * 2,
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: Spacing.lg, vertical: Spacing.sm),
                    decoration: BoxDecoration(
                      color: t.brightness == Brightness.dark
                          ? t.mutedSurface
                          : t.colorScheme.surface,
                      border:
                          Border.all(color: t.strokeColor, width: Strokes.subtle),
                      borderRadius: Radii.rPill,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(
                              t.brightness == Brightness.dark ? 0.5 : 0.08),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: dot,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: Spacing.sm),
                        Flexible(
                          child: Text(
                            widget.message.toUpperCase(),
                            style: AppText.label(11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
