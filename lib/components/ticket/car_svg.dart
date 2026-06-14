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

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _svgFuture,
      builder: (_, snap) {
        final svg = snap.data;
        if (svg == null || svg.isEmpty) {
          return SizedBox(width: widget.width, height: widget.height);
        }
        return SvgPicture.string(
          svg,
          width: widget.width,
          height: widget.height,
          fit: BoxFit.contain,
          colorFilter: widget.color == null
              ? null
              : ColorFilter.mode(widget.color!, BlendMode.srcIn),
        );
      },
    );
  }
}
