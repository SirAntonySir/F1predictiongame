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
/// Designed to scale to leagues much bigger than the inline preview. Key bits:
///   - Only the *selected* members are plotted (max 10) — keeps the chart
///     readable even when a league has hundreds of players.
///   - Preset chips repopulate the selection: Neighbours (default), Top 10,
///     Around me ±5, Bottom 10. Anything beyond a preset uses "Add players".
///   - Selection is held in a process-lifetime singleton (`_SelectionStore`)
///     so closing → re-opening the fullscreen restores what you had.
///   - Pan + pinch-zoom via `InteractiveViewer`. Native fl_chart tooltips
///     show per-series values when you tap a data point.
///
/// Data is passed via go_router `extra` to avoid a refetch on the route push.
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
  late final List<_Series> _byCurrentRank; // descending by points.last
  late Set<String> _selected;
  _Preset? _activePreset;
  final TransformationController _zoomCtrl = TransformationController();

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
    // Selection comes from the per-session store if present, otherwise the
    // Neighbours preset. We need `me` to compute Neighbours, but AppState
    // isn't safe to read in initState; defer to didChangeDependencies.
    _selected = <String>{};
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final me = AppState.of(context).auth.currentUserId;
    // Re-tag the caller's series as "You".
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

  @override
  void dispose() {
    _zoomCtrl.dispose();
    super.dispose();
  }

  String? get _me => AppState.of(context).auth.currentUserId;

  Set<String> _applyPreset(_Preset preset, String? me) {
    final selected = <String>{};
    if (me != null) selected.add(me);
    switch (preset) {
      case _Preset.neighbours:
        // Top 3 + me + (if outside top 3, my one-above & one-below).
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
        // 5 above + me + 5 below, capped at 10.
        if (me == null) {
          // No "me" → fall back to top 10.
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
    // Hard cap at 10, prefer keeping `me` if present.
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

  void _toggleOne(String userId) {
    setState(() {
      if (_selected.contains(userId)) {
        _selected.remove(userId);
      } else {
        if (_selected.length >= _maxSelected) {
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
      // Any manual edit clears the active preset — we're "Custom" now.
      _activePreset = null;
      _SelectionStore.write(_selected, _activePreset);
    });
  }

  Future<void> _openAddSheet() async {
    final candidates = _all
        .where((s) => !_selected.contains(s.userId))
        .toList()
      ..sort((a, b) => a.label.compareTo(b.label));
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (_) => _AddPlayersSheet(
        candidates: candidates,
        remaining: _maxSelected - _selected.length,
        onPick: (userId) {
          Navigator.of(context).pop();
          _toggleOne(userId);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final hasData = _all.isNotEmpty && _all.first.points.isNotEmpty;
    final sessions = _orderedSessions();
    final visibleSeries = _all.where((s) => _selected.contains(s.userId)).toList();
    return Scaffold(
      backgroundColor: t.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: t.colorScheme.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.canPop() ? context.pop() : context.go('/standings/insights'),
        ),
        title: Text('TRAJECTORY', style: AppText.display(18)),
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
                _presetsRow(t),
                _legend(t, visibleSeries),
                _zoomHintRow(t),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                        Spacing.md, 0, Spacing.lg, Spacing.lg),
                    child: InteractiveViewer(
                      transformationController: _zoomCtrl,
                      minScale: 1,
                      maxScale: 8,
                      panEnabled: true,
                      scaleEnabled: true,
                      child: _LineChart(
                        series: visibleSeries,
                        sessions: sessions,
                        theme: t,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _presetsRow(ThemeData t) {
    final canAddMore = _selected.length < _maxSelected;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(
          Spacing.lg, Spacing.sm, Spacing.lg, Spacing.xs),
      child: Row(
        children: [
          for (final p in _Preset.values) ...[
            _PresetChip(
              label: p.label,
              active: _activePreset == p,
              onTap: () => _setPreset(p),
            ),
            const SizedBox(width: 6),
          ],
          _PresetChip(
            label: '+ Add',
            active: false,
            disabled: !canAddMore,
            onTap: canAddMore ? _openAddSheet : null,
          ),
        ],
      ),
    );
  }

  Widget _legend(ThemeData t, List<_Series> visible) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          Spacing.lg, Spacing.xs, Spacing.lg, Spacing.xs),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final s in visible)
            _LegendChip(
              label: s.label,
              color: s.color,
              onRemove: () => _toggleOne(s.userId),
            ),
        ],
      ),
    );
  }

  Widget _zoomHintRow(ThemeData t) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${_selected.length} / $_maxSelected · pinch to zoom · tap a point',
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: AppText.label(9,
                  color: t.colorScheme.onSurface.withOpacity(0.5)),
            ),
          ),
          TextButton(
            onPressed: () {
              _zoomCtrl.value = Matrix4.identity();
            },
            child: Text('Reset zoom',
                style: AppText.label(10,
                    color: t.colorScheme.onSurface.withOpacity(0.7))),
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

/// Process-lifetime store for the user's series selection. Survives across
/// fullscreen closes & re-opens within the same app session; deliberately not
/// persisted to disk — we'd want to scope it per-league if it were, and one
/// rebuild of the selection from the default preset is cheap.
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

/// One series per member, cumulative points across sessions in chronological
/// order. Caller is floated to the front so they're the accent-red line.
List<_Series> _buildAllSeries(List<SessionLeaderboardRow> sessions, String? me) {
  if (sessions.isEmpty) return const [];
  final asc = [...sessions]..sort((a, b) => a.scheduledStart.compareTo(b.scheduledStart));
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

class _PresetChip extends StatelessWidget {
  final String label;
  final bool active;
  final bool disabled;
  final VoidCallback? onTap;
  const _PresetChip({
    required this.label,
    required this.active,
    this.disabled = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final bg = active ? t.colorScheme.onSurface : Colors.transparent;
    final fg = active
        ? t.colorScheme.surface
        : (disabled
            ? t.colorScheme.onSurface.withOpacity(0.3)
            : t.colorScheme.onSurface);
    return GestureDetector(
      onTap: disabled ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 7),
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

class _LegendChip extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onRemove;
  const _LegendChip({
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

class _AddPlayersSheet extends StatefulWidget {
  final List<_Series> candidates;
  final int remaining;
  final ValueChanged<String> onPick;
  const _AddPlayersSheet({
    required this.candidates,
    required this.remaining,
    required this.onPick,
  });

  @override
  State<_AddPlayersSheet> createState() => _AddPlayersSheetState();
}

class _AddPlayersSheetState extends State<_AddPlayersSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.candidates
        : widget.candidates
            .where((s) => s.label.toLowerCase().contains(q))
            .toList();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
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
                  child: Text('ADD PLAYER', style: AppText.display(15)),
                ),
                Text('${widget.remaining} slot${widget.remaining == 1 ? '' : 's'} left',
                    style: AppText.label(10,
                        color: t.colorScheme.onSurface.withOpacity(0.6))),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            TextField(
              autofocus: false,
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
                      child: Text('No matches',
                          style: AppText.body(12,
                              color: t.colorScheme.onSurface.withOpacity(0.6))),
                    )
                  : ListView.builder(
                      controller: scrollCtrl,
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final s = filtered[i];
                        return InkWell(
                          onTap: () => widget.onPick(s.userId),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 3,
                                  decoration: BoxDecoration(
                                    color: s.color,
                                    borderRadius: const BorderRadius.all(Radius.circular(2)),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(s.label,
                                      style: AppText.body(13, weight: FontWeight.w700)),
                                ),
                                Text('${s.points.isEmpty ? 0 : s.points.last.toInt()} pts',
                                    style: AppText.label(10,
                                        color: t.colorScheme.onSurface.withOpacity(0.5))),
                              ],
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
  const _LineChart({
    required this.series,
    required this.sessions,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    if (series.isEmpty || sessions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.lg),
          child: Text(
            'Nothing selected — tap a preset above or "+ Add" to show players.',
            textAlign: TextAlign.center,
            style: AppText.body(12,
                color: theme.colorScheme.onSurface.withOpacity(0.6)),
          ),
        ),
      );
    }
    final maxY = series
        .expand((s) => s.points)
        .fold<double>(0, (m, v) => v > m ? v : m);
    final yMax = (((maxY / 10).ceil()) * 10).clamp(10, 1000000).toDouble();
    final yInterval = yMax > 80 ? 20.0 : 10.0;
    final xMax = (sessions.length - 1).toDouble();
    final xLabelStride = (sessions.length / 6).ceil().clamp(1, sessions.length);
    return LineChart(
      LineChartData(
        minX: 0,
        maxX: xMax,
        minY: 0,
        maxY: yMax,
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
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              interval: yInterval,
              getTitlesWidget: (v, _) => Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(v.toInt().toString(),
                    style: AppText.label(9,
                        color: theme.colorScheme.onSurface.withOpacity(0.55))),
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
                if (i % xLabelStride != 0 && i != sessions.length - 1) {
                  return const SizedBox.shrink();
                }
                final s = sessions[i];
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'R${s.eventRound}·${_typeAbbrev(s.sessionType)}',
                    style: AppText.label(9,
                        color: theme.colorScheme.onSurface.withOpacity(0.55)),
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => theme.colorScheme.onSurface.withOpacity(0.92),
            getTooltipItems: (spots) => spots.map((sp) {
              final s = series[sp.barIndex];
              return LineTooltipItem(
                '${s.label}: ${sp.y.toInt()}',
                TextStyle(
                  color: theme.colorScheme.surface,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              );
            }).toList(),
          ),
        ),
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
