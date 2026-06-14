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
  // Process-wide cache of resolved SVG strings, keyed by `id|detail|variant`.
  // Once a circuit is fetched the first time, every subsequent CircuitSvg
  // for the same (id, detail, variant) renders synchronously on the first
  // frame — no more empty SizedBox flash while the HTTP roundtrip is in
  // flight (which is what made the watermark look "lazy" on the home pick
  // ticket every time the cache rebuilt). The values are tiny SVG strings
  // (~2 KB each) and there are <30 circuits, so memory cost is negligible.
  static final Map<String, String?> _cache = {};
  // In-flight fetches keyed the same way, so two CircuitSvg widgets that
  // mount in the same frame share one network call instead of two.
  static final Map<String, Future<String?>> _inFlight = {};

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
    if (id == null) {
      _svgFuture = Future.value(null);
      return;
    }
    final key = '$id|${widget.detail}|${widget.variant}';
    final cached = _cache[key];
    if (cached != null) {
      // Already resolved — return a synchronous future so the FutureBuilder
      // paints the SVG on the very first frame.
      _svgFuture = Future.value(cached);
      return;
    }
    _svgFuture = _inFlight.putIfAbsent(key, () => _load(id, key));
  }

  Future<String?> _load(String id, String key) async {
    try {
      final scope = AppState.of(context);
      final svg = await scope.api.circuitSvg(id,
          detail: widget.detail, variant: widget.variant);
      if (svg != null && svg.isNotEmpty) _cache[key] = svg;
      return svg;
    } catch (_) {
      return null;
    } finally {
      _inFlight.remove(key);
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
