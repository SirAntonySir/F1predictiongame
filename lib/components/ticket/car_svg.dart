// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../state/app_state.dart';

/// Renders a constructor car SVG fetched from /api/constructors/:id/car-svg.
/// Returns an empty SizedBox when the SVG isn't stored or the fetch fails —
/// the ticket layout still works without it.
class CarSvg extends StatefulWidget {
  final String? constructorId;
  final String variant;
  final double? width;
  final double? height;
  final Color? color;
  const CarSvg({
    super.key,
    required this.constructorId,
    this.variant = 'outline',
    this.width,
    this.height,
    this.color,
  });

  @override
  State<CarSvg> createState() => _CarSvgState();
}

class _CarSvgState extends State<CarSvg> {
  Future<String?>? _svgFuture;
  String? _key;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant CarSvg old) {
    super.didUpdateWidget(old);
    if (old.constructorId != widget.constructorId || old.variant != widget.variant) {
      _resolve();
    }
  }

  void _resolve() {
    final id = widget.constructorId;
    if (id == null || id.isEmpty) {
      _svgFuture = Future.value(null);
      _key = null;
      return;
    }
    final next = '$id|${widget.variant}';
    if (next == _key) return;
    _key = next;
    _svgFuture = _load(id);
  }

  Future<String?> _load(String id) async {
    final scope = AppState.of(context);
    try {
      return await scope.api.constructorCarSvg(id, variant: widget.variant);
    } catch (_) {
      return null;
    }
  }

  /// Bundled silhouettes used when the backend doesn't have a stored car SVG
  /// for the constructor. Picking is deterministic on constructorId so the
  /// same team always gets the same shape — different teams get different
  /// shapes so the wall of tickets isn't a single repeated silhouette.
  static const _fallbackAssets = <String>[
    'assets/dev_car_outline.svg',
    'assets/dev_car_b.svg',
    'assets/dev_car_c.svg',
  ];

  String _fallbackAssetFor(String id) {
    var h = 0;
    for (final c in id.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return _fallbackAssets[h % _fallbackAssets.length];
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _svgFuture,
      builder: (_, snap) {
        final svg = snap.data;
        final colorFilter = widget.color == null
            ? null
            : ColorFilter.mode(widget.color!, BlendMode.srcIn);
        if (svg == null || svg.isEmpty) {
          final id = widget.constructorId;
          if (id == null || id.isEmpty) {
            return SizedBox(width: widget.width, height: widget.height);
          }
          return SvgPicture.asset(
            _fallbackAssetFor(id),
            width: widget.width,
            height: widget.height,
            fit: BoxFit.contain,
            colorFilter: colorFilter,
          );
        }
        return SvgPicture.string(
          svg,
          width: widget.width,
          height: widget.height,
          fit: BoxFit.contain,
          colorFilter: colorFilter,
        );
      },
    );
  }
}
