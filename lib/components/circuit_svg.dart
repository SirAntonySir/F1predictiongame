// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../api/models/event.dart';
import '../state/app_state.dart';
import '../theme/circuit_slugs.dart';

/// Renders a circuit SVG fetched from /api/circuits/:id/svg via the app's
/// authenticated API client. Renders nothing (a zero-size SizedBox) when:
///   - the event maps to no known circuit id,
///   - the SVG isn't stored for that circuit,
///   - the fetch errors out.
/// All three are non-fatal — the hero card should still look fine without it.
class CircuitSvg extends StatefulWidget {
  final Event event;
  /// SVG variant. Defaults to detailed/white — works on the red hero card.
  final String detail;
  final String variant;
  final double? width;
  final double? height;
  final Color? color;
  const CircuitSvg({
    super.key,
    required this.event,
    this.detail = 'detailed',
    this.variant = 'white',
    this.width,
    this.height,
    this.color,
  });

  @override
  State<CircuitSvg> createState() => _CircuitSvgState();
}

class _CircuitSvgState extends State<CircuitSvg> {
  Future<String?>? _svgFuture;
  String? _circuitId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant CircuitSvg old) {
    super.didUpdateWidget(old);
    if (old.event.round != widget.event.round ||
        old.detail != widget.detail ||
        old.variant != widget.variant) {
      _resolve();
    }
  }

  void _resolve() {
    final id = circuitIdForEvent(
      name: widget.event.name,
      country: widget.event.country,
      circuitName: widget.event.circuitName,
    );
    if (id == _circuitId && _svgFuture != null) return;
    _circuitId = id;
    // Plain assignment — didChangeDependencies/didUpdateWidget already runs
    // inside the framework's build cycle; FutureBuilder picks up the new
    // future on the next build.
    _svgFuture = id == null ? Future.value(null) : _load(id);
  }

  Future<String?> _load(String id) async {
    final scope = AppState.of(context);
    try {
      return await scope.api.circuitSvg(id,
          detail: widget.detail, variant: widget.variant);
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
