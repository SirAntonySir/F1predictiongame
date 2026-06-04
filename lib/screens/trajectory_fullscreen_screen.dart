// ignore_for_file: deprecated_member_use
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../api/models/session_leaderboard_row.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// Interactive full-screen trajectory of cumulative league points over time.
///
/// Design notes worth knowing for future edits:
///   - Pan + pinch-zoom are **data-aware**, not Transform-based. We capture
///     scale gestures, recompute fl_chart's minX/maxX (and the visible-window
///     maxY), and let the chart re-render at the new viewport. So axes stay
///     crisp, gridlines reflow, and labels reposition — unlike an
///     InteractiveViewer, which just stretches a bitmap.
///   - All chip controls (preset buckets + per-player selection + add) live
///     behind a single "PLAYERS · n/10" button that opens a bottom sheet —
///     keeps the screen uncluttered when the league has hundreds of members.
///   - Selection is stored in a process-lifetime singleton (`_SelectionStore`)
///     so closing → re-opening the fullscreen restores what you had pinned.
class TrajectoryFullscreenScreen extends StatefulWidget {
  final List<SessionLeaderboardRow> sessions;
  const TrajectoryFullscreenScreen({super.key, required this.sessions});

  @override
  State<TrajectoryFullscreenScreen> createState() =>
      _TrajectoryFullscreenScreenState();
}

const int _maxSelected = 10;

enum _Preset { neighbours, top10, aroundMe, bottom10 }

extension on _Preset {
  String get label => switch (this) {
        _Preset.neighbours => 'Neighbours',
        _Preset.top10 => 'Top 10',
        _Preset.aroundMe => 'Around me ±5',
        _Preset.bottom10 => 'Bottom 10',
      };
}

class _TrajectoryFullscreenScreenState
    extends State<TrajectoryFullscreenScreen> {
  late final List<_Series> _all;
  late final List<_Series> _byCurrentRank;
  late Set<String> _selected;
  _Preset? _activePreset;

  // Viewport into the X domain (session index). When the user pinch-zooms or
  // pans, we update these and the chart redraws at the new window.
  late double _xMin;
  late double _xMax;
  // Captured at gesture start so subsequent ScaleUpdate events can compute the
  // new range from the initial state (not the previous frame).
  double _xMinAtStart = 0;
  double _xMaxAtStart = 0;
  Offset _focalAtStart = Offset.zero;
  // Width of the chart's drawing area, captured from LayoutBuilder so we can
  // map pixel deltas into data deltas during pan/zoom.
  double _chartWidth = 0;

  @override
  void initState() {
    super.initState();
    _all = _buildAllSeries(widget.sessions, null);
    _byCurrentRank = [..._all]
      ..sort((a, b) {
        final ap = a.points.isEmpty ? 0.0 : a.points.last;
        final bp = b.points.isEmpty ? 0.0 : b.points.last;
        return bp.compareTo(ap);
      });
    _selected = <String>{};
    final n = widget.sessions.length;
    _xMin = 0;
    _xMax = (n - 1).clamp(1, 1000000).toDouble();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final me = AppState.of(context).auth.currentUserId;
    if (me != null) {
      for (final s in _all) {
        if (s.userId == me) s.label = 'You';
      }
    }
    if (_selected.isEmpty) {
      final stored = _SelectionStore.read();
      if (stored != null && stored.selected.isNotEmpty) {
        _selected = stored.selected.toSet();
        _activePreset = stored.preset;
      } else {
        _selected = _applyPreset(_Preset.neighbours, me);
        _activePreset = _Preset.neighbours;
        _SelectionStore.write(_selected, _activePreset);
      }
    }
  }

  String? get _me => AppState.of(context).auth.currentUserId;

  Set<String> _applyPreset(_Preset preset, String? me) {
    final selected = <String>{};
    if (me != null) selected.add(me);
    switch (preset) {
      case _Preset.neighbours:
        for (var i = 0; i < _byCurrentRank.length && i < 3; i++) {
          selected.add(_byCurrentRank[i].userId);
        }
        if (me != null) {
          final myIdx = _byCurrentRank.indexWhere((s) => s.userId == me);
          if (myIdx >= 3) {
            if (myIdx - 1 >= 0) selected.add(_byCurrentRank[myIdx - 1].userId);
            if (myIdx + 1 < _byCurrentRank.length) {
              selected.add(_byCurrentRank[myIdx + 1].userId);
            }
          }
        }
      case _Preset.top10:
        for (var i = 0; i < _byCurrentRank.length && i < _maxSelected; i++) {
          selected.add(_byCurrentRank[i].userId);
        }
      case _Preset.aroundMe:
        if (me == null) {
          for (var i = 0; i < _byCurrentRank.length && i < _maxSelected; i++) {
            selected.add(_byCurrentRank[i].userId);
          }
        } else {
          final myIdx = _byCurrentRank.indexWhere((s) => s.userId == me);
          if (myIdx >= 0) {
            final lo = (myIdx - 5).clamp(0, _byCurrentRank.length - 1);
            final hi = (myIdx + 5).clamp(0, _byCurrentRank.length - 1);
            for (var i = lo; i <= hi; i++) {
              selected.add(_byCurrentRank[i].userId);
            }
          }
        }
      case _Preset.bottom10:
        final start = (_byCurrentRank.length - _maxSelected).clamp(0, _byCurrentRank.length);
        for (var i = start; i < _byCurrentRank.length; i++) {
          selected.add(_byCurrentRank[i].userId);
        }
    }
    if (selected.length > _maxSelected) {
      final ordered = [
        if (me != null && selected.contains(me)) me,
        ..._byCurrentRank
            .map((s) => s.userId)
            .where((id) => selected.contains(id) && id != me),
      ];
      return ordered.take(_maxSelected).toSet();
    }
    return selected;
  }

  void _setPreset(_Preset preset) {
    setState(() {
      _selected = _applyPreset(preset, _me);
      _activePreset = preset;
      _SelectionStore.write(_selected, _activePreset);
    });
  }

  void _toggleOne(String userId, {bool allowOverflow = false}) {
    setState(() {
      if (_selected.contains(userId)) {
        _selected.remove(userId);
      } else {
        if (!allowOverflow && _selected.length >= _maxSelected) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Max $_maxSelected players. Remove one first.'),
              duration: Duration(seconds: 2),
            ),
          );
          return;
        }
        _selected.add(userId);
      }
      _activePreset = null;
      _SelectionStore.write(_selected, _activePreset);
    });
  }

  Future<void> _openPlayersSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (sheetCtx) {
        // StatefulBuilder so internal sheet state (search query) can repaint
        // without rebuilding the whole screen, while toggle callbacks still
        // mutate parent state via setState on the outer Screen.
        return StatefulBuilder(
          builder: (_, setSheet) {
            return _PlayersSheet(
              all: _all,
              byCurrentRank: _byCurrentRank,
              selected: _selected,
              activePreset: _activePreset,
              onPreset: (p) {
                _setPreset(p);
                setSheet(() {});
              },
              onToggle: (id) {
                _toggleOne(id);
                setSheet(() {});
              },
            );
          },
        );
      },
    );
  }

  void _resetView() {
    setState(() {
      _xMin = 0;
      _xMax = (widget.sessions.length - 1).clamp(1, 1000000).toDouble();
    });
  }

  void _onScaleStart(ScaleStartDetails d) {
    _xMinAtStart = _xMin;
    _xMaxAtStart = _xMax;
    _focalAtStart = d.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (_chartWidth <= 0) return;
    final fullMax = (widget.sessions.length - 1).toDouble();
    if (fullMax <= 0) return;

    // Pan: how far has the focal point moved (in pixels) since the gesture
    // started, converted into data units (negative because dragging right
    // moves the world left — viewport shifts left to "follow" the finger).
    final pxDelta = d.localFocalPoint.dx - _focalAtStart.dx;
    final rangeAtStart = _xMaxAtStart - _xMinAtStart;
    final dataPan = -pxDelta / _chartWidth * rangeAtStart;

    // Zoom around the focal point so pinching feels anchored where the fingers
    // started, not at the middle.
    final focalRatio = _focalAtStart.dx / _chartWidth;
    final focalDataX = _xMinAtStart + focalRatio * rangeAtStart;
    final newRange = (rangeAtStart / d.scale).clamp(1.0, fullMax);
    var newMin = focalDataX - focalRatio * newRange + dataPan;
    var newMax = newMin + newRange;

    // Clamp into [0, fullMax] while preserving the chosen window size.
    if (newMin < 0) {
      newMax -= newMin;
      newMin = 0;
    }
    if (newMax > fullMax) {
      newMin -= newMax - fullMax;
      newMax = fullMax;
    }
    if (newMin < 0) newMin = 0;
    if (newMax > fullMax) newMax = fullMax;
    if (newMax - newMin < 1) newMax = (newMin + 1).clamp(0, fullMax);

    setState(() {
      _xMin = newMin;
      _xMax = newMax;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final hasData = _all.isNotEmpty && _all.first.points.isNotEmpty;
    final sessions = _orderedSessions();
    final visibleSeries =
        _all.where((s) => _selected.contains(s.userId)).toList();
    return Scaffold(
      backgroundColor: t.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: t.colorScheme.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.canPop()
              ? context.pop()
              : context.go('/standings/insights'),
        ),
        title: Text('TRAJECTORY', style: AppText.display(18)),
        actions: [
          if (hasData)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
              child: Center(
                child: _PillButton(
                  label: 'PLAYERS · ${_selected.length}/$_maxSelected',
                  onTap: _openPlayersSheet,
                ),
              ),
            ),
        ],
      ),
      body: !hasData
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(Spacing.lg),
                child: Text(
                  'No scored sessions yet.',
                  style: AppText.body(13,
                      color: t.colorScheme.onSurface.withOpacity(0.6)),
                ),
              ),
            )
          : Column(
              children: [
                _hintRow(t, sessions),
                _legendStrip(t, visibleSeries),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                        Spacing.md, 0, Spacing.lg, Spacing.lg),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onScaleStart: _onScaleStart,
                      onScaleUpdate: _onScaleUpdate,
                      child: LayoutBuilder(
                        builder: (ctx, c) {
                          // Subtract the y-axis reserved width from the chart-width
                          // measurement; otherwise pixel → data conversion lags
                          // by ~34 px and pans feel sticky on the left.
                          _chartWidth = (c.maxWidth - 34).clamp(1, 100000);
                          return _LineChart(
                            series: visibleSeries,
                            sessions: sessions,
                            theme: t,
                            xMin: _xMin,
                            xMax: _xMax,
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _hintRow(ThemeData t, List<SessionLeaderboardRow> sessions) {
    final n = sessions.length;
    final atFullExtent =
        _xMin <= 0.001 && _xMax >= (n - 1).toDouble() - 0.001;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          Spacing.lg, Spacing.xs, Spacing.lg, Spacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              atFullExtent
                  ? 'Pinch to zoom · drag to pan'
                  : 'Window: ${_xMin.toInt() + 1}–${_xMax.toInt() + 1} of $n',
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: AppText.label(9,
                  color: t.colorScheme.onSurface.withOpacity(0.5)),
            ),
          ),
          if (!atFullExtent)
            TextButton(
              onPressed: _resetView,
              child: Text('Reset view',
                  style: AppText.label(10,
                      color: t.colorScheme.onSurface.withOpacity(0.7))),
            ),
        ],
      ),
    );
  }

  /// Compact legend below the hint row — gives an at-a-glance map from each
  /// line's colour to its player. Wraps onto multiple lines so nothing gets
  /// clipped (a horizontal scroller hid the rightmost players because users
  /// don't always realise they can swipe).
  Widget _legendStrip(ThemeData t, List<_Series> visibleSeries) {
    if (visibleSeries.isEmpty) return const SizedBox.shrink();
    final me = _me;
    // You first (anchor), then everyone else by current rank descending so the
    // legend reads like a mini-leaderboard.
    final ordered = [
      if (me != null) ...visibleSeries.where((s) => s.userId == me),
      ..._byCurrentRank
          .where((s) => visibleSeries.contains(s) && s.userId != me),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          Spacing.lg, 0, Spacing.lg, Spacing.sm),
      child: Wrap(
        spacing: 10,
        runSpacing: 4,
        children: [
          for (final s in ordered)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 3,
                  decoration: BoxDecoration(
                    color: s.color,
                    borderRadius: const BorderRadius.all(Radius.circular(2)),
                  ),
                ),
                const SizedBox(width: 5),
                Text(s.label, style: AppText.label(10)),
                const SizedBox(width: 4),
                Text(
                  '${s.points.isEmpty ? 0 : s.points.last.toInt()}',
                  style: AppText.label(10,
                      color: t.colorScheme.onSurface.withOpacity(0.55)),
                ),
              ],
            ),
        ],
      ),
    );
  }

  List<SessionLeaderboardRow> _orderedSessions() {
    final s = [...widget.sessions]
      ..sort((a, b) => a.scheduledStart.compareTo(b.scheduledStart));
    return s;
  }
}

/// Process-lifetime selection store. Survives across fullscreen closes within
/// the same app session; deliberately not persisted to disk.
class _SelectionStore {
  static Set<String> _selected = const <String>{};
  static _Preset? _preset;

  static ({Set<String> selected, _Preset? preset})? read() {
    if (_selected.isEmpty) return null;
    return (selected: Set.from(_selected), preset: _preset);
  }

  static void write(Set<String> selected, _Preset? preset) {
    _selected = Set.from(selected);
    _preset = preset;
  }
}

class _Series {
  final String userId;
  String label;
  final Color color;
  final List<double> points;
  _Series({
    required this.userId,
    required this.label,
    required this.color,
    required this.points,
  });
}

List<_Series> _buildAllSeries(
    List<SessionLeaderboardRow> sessions, String? me) {
  if (sessions.isEmpty) return const [];
  final asc = [...sessions]
    ..sort((a, b) => a.scheduledStart.compareTo(b.scheduledStart));
  final perSession = <Map<String, int>>[
    for (final s in asc) {for (final m in s.members) m.userId: m.pointsTotal},
  ];
  final names = <String, String>{};
  for (final s in asc) {
    for (final m in s.members) {
      names.putIfAbsent(m.userId, () => m.displayName);
    }
  }
  final orderedIds = names.keys.toList()..sort();
  if (me != null) {
    orderedIds.removeWhere((id) => id == me);
    orderedIds.insert(0, me);
  }
  return [
    for (var i = 0; i < orderedIds.length; i++)
      _Series(
        userId: orderedIds[i],
        label: orderedIds[i] == me ? 'You' : (names[orderedIds[i]] ?? '—'),
        color: _palette[i % _palette.length],
        points: _cumulative(perSession, orderedIds[i]),
      ),
  ];
}

List<double> _cumulative(List<Map<String, int>> perSession, String userId) {
  var cum = 0.0;
  return [
    for (final m in perSession) (cum += (m[userId] ?? 0).toDouble()),
  ];
}

const List<Color> _palette = [
  BrandColors.accent,
  Color(0xFF6B6F76),
  Color(0xFFB58A3A),
  Color(0xFF4A7B8C),
  Color(0xFF8E5A7B),
  Color(0xFF5C8C4A),
  Color(0xFF8C5A4A),
  Color(0xFF3D5A80),
  Color(0xFF8A8A24),
  Color(0xFF7A4A8C),
  Color(0xFF2E8B57),
  Color(0xFFCC7722),
];

class _PillButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PillButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: t.strokeColor, width: 1.5),
          borderRadius: const BorderRadius.all(Radius.circular(999)),
        ),
        child: Text(label,
            style: AppText.label(10, color: t.colorScheme.onSurface)),
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _PresetChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final bg = active ? t.colorScheme.onSurface : Colors.transparent;
    final fg = active ? t.colorScheme.surface : t.colorScheme.onSurface;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 7),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: t.strokeColor, width: 1.5),
          borderRadius: const BorderRadius.all(Radius.circular(8)),
        ),
        child: Text(label.toUpperCase(), style: AppText.label(10, color: fg)),
      ),
    );
  }
}

class _SelectedChip extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onRemove;
  const _SelectedChip({
    required this.label,
    required this.color,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
      decoration: BoxDecoration(
        border: Border.all(color: t.strokeColor, width: 1),
        borderRadius: const BorderRadius.all(Radius.circular(999)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 3,
            decoration: BoxDecoration(
              color: color,
              borderRadius: const BorderRadius.all(Radius.circular(2)),
            ),
          ),
          const SizedBox(width: 6),
          Text(label, style: AppText.body(11, weight: FontWeight.w700)),
          const SizedBox(width: 2),
          GestureDetector(
            onTap: onRemove,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.close,
                  size: 12,
                  color: t.colorScheme.onSurface.withOpacity(0.6)),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayersSheet extends StatefulWidget {
  final List<_Series> all;
  final List<_Series> byCurrentRank;
  final Set<String> selected;
  final _Preset? activePreset;
  final ValueChanged<_Preset> onPreset;
  final ValueChanged<String> onToggle;
  const _PlayersSheet({
    required this.all,
    required this.byCurrentRank,
    required this.selected,
    required this.activePreset,
    required this.onPreset,
    required this.onToggle,
  });

  @override
  State<_PlayersSheet> createState() => _PlayersSheetState();
}

class _PlayersSheetState extends State<_PlayersSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final selectedSeries =
        widget.all.where((s) => widget.selected.contains(s.userId)).toList();
    final candidates =
        widget.byCurrentRank.where((s) => !widget.selected.contains(s.userId));
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? candidates.toList()
        : candidates.where((s) => s.label.toLowerCase().contains(q)).toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (_, scrollCtrl) => Padding(
        padding: EdgeInsets.fromLTRB(Spacing.lg, Spacing.md, Spacing.lg,
            MediaQuery.of(context).viewInsets.bottom + Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: t.colorScheme.onSurface.withOpacity(0.15),
                  borderRadius: const BorderRadius.all(Radius.circular(2)),
                ),
              ),
            ),
            const SizedBox(height: Spacing.md),
            Row(
              children: [
                Expanded(
                  child: Text('PLAYERS', style: AppText.display(18)),
                ),
                Text(
                  '${widget.selected.length}/$_maxSelected',
                  style: AppText.label(11,
                      color: t.colorScheme.onSurface.withOpacity(0.6)),
                ),
              ],
            ),
            const SizedBox(height: Spacing.md),
            // Presets
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final p in _Preset.values) ...[
                    _PresetChip(
                      label: p.label,
                      active: widget.activePreset == p,
                      onTap: () => widget.onPreset(p),
                    ),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
            const SizedBox(height: Spacing.md),
            // Selected
            if (selectedSeries.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
                child: Text(
                  'No players selected. Pick a preset or add manually below.',
                  style: AppText.body(12,
                      color: t.colorScheme.onSurface.withOpacity(0.6)),
                ),
              )
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in selectedSeries)
                    _SelectedChip(
                      label: s.label,
                      color: s.color,
                      onRemove: () => widget.onToggle(s.userId),
                    ),
                ],
              ),
            const SizedBox(height: Spacing.md),
            Divider(
                color: t.colorScheme.onSurface.withOpacity(0.12),
                height: 1),
            const SizedBox(height: Spacing.md),
            Text('ADD PLAYER', style: AppText.label(11)),
            const SizedBox(height: Spacing.sm),
            TextField(
              decoration: InputDecoration(
                hintText: 'Search by name',
                hintStyle: AppText.body(13,
                    color: t.colorScheme.onSurface.withOpacity(0.4)),
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: const OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: Spacing.sm),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        widget.selected.length >= _maxSelected
                            ? 'Max $_maxSelected selected. Remove one to add another.'
                            : (q.isEmpty
                                ? 'Everyone is already selected.'
                                : 'No matches.'),
                        textAlign: TextAlign.center,
                        style: AppText.body(12,
                            color:
                                t.colorScheme.onSurface.withOpacity(0.6)),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollCtrl,
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final s = filtered[i];
                        final canAdd =
                            widget.selected.length < _maxSelected;
                        return InkWell(
                          onTap: canAdd
                              ? () => widget.onToggle(s.userId)
                              : null,
                          child: Opacity(
                            opacity: canAdd ? 1 : 0.4,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Row(
                                children: [
                                  Container(
                                    width: 10,
                                    height: 3,
                                    decoration: BoxDecoration(
                                      color: s.color,
                                      borderRadius: const BorderRadius.all(
                                          Radius.circular(2)),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(s.label,
                                        style: AppText.body(13,
                                            weight: FontWeight.w700)),
                                  ),
                                  Text(
                                      '${s.points.isEmpty ? 0 : s.points.last.toInt()} pts',
                                      style: AppText.label(10,
                                          color: t.colorScheme.onSurface
                                              .withOpacity(0.5))),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LineChart extends StatelessWidget {
  final List<_Series> series;
  final List<SessionLeaderboardRow> sessions;
  final ThemeData theme;
  final double xMin;
  final double xMax;
  const _LineChart({
    required this.series,
    required this.sessions,
    required this.theme,
    required this.xMin,
    required this.xMax,
  });

  @override
  Widget build(BuildContext context) {
    if (series.isEmpty || sessions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.lg),
          child: Text(
            series.isEmpty
                ? 'No players selected — tap PLAYERS to pick some.'
                : 'No data.',
            textAlign: TextAlign.center,
            style: AppText.body(12,
                color: theme.colorScheme.onSurface.withOpacity(0.6)),
          ),
        ),
      );
    }
    // Y-max comes from the *visible* window, so zooming into late sessions
    // doesn't waste vertical space on early-season near-zero values.
    final lo = xMin.floor().clamp(0, sessions.length - 1);
    final hi = xMax.ceil().clamp(0, sessions.length - 1);
    double maxY = 0;
    for (final s in series) {
      for (var i = lo; i <= hi && i < s.points.length; i++) {
        if (s.points[i] > maxY) maxY = s.points[i];
      }
    }
    final yMax = (((maxY / 10).ceil()) * 10).clamp(10, 1000000).toDouble();
    final yInterval = yMax > 80 ? 20.0 : 10.0;
    // X label stride scales with the visible window so we always have ~6
    // labels visible regardless of zoom level. Stride 1 = label every session.
    final visibleCount = (xMax - xMin) + 1;
    final xLabelStride = (visibleCount / 6).ceil().clamp(1, sessions.length);
    return LineChart(
      LineChartData(
        minX: xMin,
        maxX: xMax,
        minY: 0,
        maxY: yMax,
        clipData: const FlClipData.all(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: yInterval,
          getDrawingHorizontalLine: (_) => FlLine(
            color: theme.colorScheme.onSurface.withOpacity(0.08),
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              interval: yInterval,
              getTitlesWidget: (v, _) => Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(v.toInt().toString(),
                    style: AppText.label(9,
                        color: theme.colorScheme.onSurface
                            .withOpacity(0.55))),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: 1,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= sessions.length) return const SizedBox.shrink();
                if (i < lo || i > hi) return const SizedBox.shrink();
                if ((i - lo) % xLabelStride != 0 && i != hi) {
                  return const SizedBox.shrink();
                }
                final s = sessions[i];
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'R${s.eventRound}·${_typeAbbrev(s.sessionType)}',
                    style: AppText.label(9,
                        color: theme.colorScheme.onSurface
                            .withOpacity(0.55)),
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        // We handle gestures externally so the touch reaches the
        // GestureDetector wrapping this chart.
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          for (final s in series)
            LineChartBarData(
              spots: [
                for (var i = 0; i < s.points.length; i++)
                  FlSpot(i.toDouble(), s.points[i]),
              ],
              isCurved: false,
              color: s.color,
              barWidth: 2.4,
              dotData: FlDotData(
                show: true,
                getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                  radius: 2,
                  color: s.color,
                  strokeWidth: 0,
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _typeAbbrev(String t) {
    switch (t) {
      case 'race':         return 'R';
      case 'qualifying':   return 'Q';
      case 'sprint':       return 'S';
      case 'sprint_quali': return 'SQ';
      default:             return t.toUpperCase().substring(0, t.length < 2 ? 1 : 2);
    }
  }
}
