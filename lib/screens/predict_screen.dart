// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../api/models/event.dart';
import '../api/models/pick.dart';
import '../api/models/session.dart';
import '../api/models/session_result.dart';
import '../components/app_card.dart';
import '../components/driver_tile.dart';
import '../components/error_view.dart';
import '../components/slot.dart';
import '../domain/prediction.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

class PredictScreen extends StatefulWidget {
  /// When non-null the screen targets this specific session (used by the
  /// "PICK / EDIT" CTA on future-race heroes — lets the user pre-pick any
  /// upcoming weekend, not just the global next). Without it the screen
  /// auto-finds the next upcoming pickable session.
  final int? sessionId;
  const PredictScreen({super.key, this.sessionId});
  @override
  State<PredictScreen> createState() => _PredictScreenState();
}

class _PredictScreenState extends State<PredictScreen> {
  Future<_PredictData>? _data;
  List<String> _picks = [];
  bool _saving = false;
  /// Internal override for which session is being predicted. Lets the user
  /// flick between sessions via swipe / prev-next arrows without bouncing
  /// through the URL on every nudge.
  int? _overrideSessionId;

  bool _isScorable(SessionType t) =>
      t == SessionType.race ||
      t == SessionType.qualifying ||
      t == SessionType.sprint ||
      t == SessionType.sprint_quali;

  Future<_PredictData> _load() async {
    final scope = AppState.of(context);
    final events = await scope.api.events();
    if (events.isEmpty) {
      return _PredictData(event: null, session: null, drivers: const [], prev: null, next: null);
    }
    Event? upcoming;
    Session? session;
    final now = DateTime.now();
    final targetId = _overrideSessionId ?? widget.sessionId;

    if (targetId != null) {
      // Targeted mode: find the requested session across all events. We allow
      // any future session regardless of status — pre-picking ahead is the
      // whole point. If the requested session has already started, fall back
      // to auto-find so the screen doesn't sit broken.
      for (final e in events) {
        for (final s in e.sessions) {
          if (s.id == targetId &&
              _isScorable(s.type) &&
              s.scheduledStart.isAfter(now)) {
            upcoming = e;
            session = s;
            break;
          }
        }
        if (session != null) break;
      }
    }

    if (session == null) {
      // Auto-find the next upcoming pickable session.
      for (final e in events) {
        for (final s in e.sessions) {
          if (s.status == SessionStatus.scheduled &&
              _isScorable(s.type) &&
              s.scheduledStart.isAfter(now) &&
              (session == null ||
                  s.scheduledStart.isBefore(session.scheduledStart))) {
            upcoming = e;
            session = s;
          }
        }
      }
    }

    if (upcoming == null || session == null) {
      return _PredictData(event: null, session: null, drivers: const [], prev: null, next: null);
    }
    final existing = await scope.predictions.fetchPrediction(session.id);
    _picks = existing?.picks.map((p) => p.driverCode).toList() ?? <String>[];
    final finished = events
        .expand((e) => e.sessions)
        .where((s) => s.status == SessionStatus.finished)
        .toList()
      ..sort((a, b) => b.scheduledStart.compareTo(a.scheduledStart));
    List<SessionResult> lineup = const [];
    if (finished.isNotEmpty) {
      try {
        lineup = await scope.api.sessionResults(finished.first.id);
      } on NotFoundException {
        lineup = const [];
      }
    }
    final sorted = [...lineup]
      ..sort((a, b) => a.position.compareTo(b.position));
    // Build the chronological nav list of all upcoming pickable sessions in
    // events whose lock hasn't passed (event lock = earliest session start).
    final chronological = <_NavRef>[];
    for (final e in events) {
      DateTime? earliest;
      for (final s in e.sessions) {
        if (earliest == null || s.scheduledStart.isBefore(earliest)) {
          earliest = s.scheduledStart;
        }
      }
      if (earliest == null || !earliest.isAfter(now)) continue;
      for (final s in e.sessions) {
        if (!_isScorable(s.type)) continue;
        chronological.add(_NavRef(sessionId: s.id, scheduledStart: s.scheduledStart));
      }
    }
    chronological.sort((a, b) => a.scheduledStart.compareTo(b.scheduledStart));
    final activeId = session.id;
    final idx = chronological.indexWhere((r) => r.sessionId == activeId);
    final prev = idx > 0 ? chronological[idx - 1] : null;
    final next = idx >= 0 && idx < chronological.length - 1 ? chronological[idx + 1] : null;
    return _PredictData(
      event: upcoming, session: session, drivers: sorted, prev: prev, next: next,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _data ??= _load();
  }

  void _navigateTo(_NavRef target) {
    setState(() {
      _overrideSessionId = target.sessionId;
      _data = _load();
    });
  }

  void _toggleDriver(String code) {
    final required = requiredPicks(_currentType);
    setState(() {
      if (_picks.contains(code)) {
        _picks.remove(code);
      } else if (_picks.length < required) {
        _picks.add(code);
      }
    });
  }

  SessionType _currentType = SessionType.race;

  Future<void> _lock() async {
    final scope = AppState.of(context);
    final session = (await _data!).session;
    if (session == null) return;
    if (scope.predictions.prediction(session.id)?.isLocked == true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pick already locked')));
      }
      return;
    }
    setState(() => _saving = true);
    try {
      final picks = [
        for (var i = 0; i < _picks.length; i++)
          Pick(position: i + 1, driverCode: _picks[i]),
      ];
      await scope.predictions.savePrediction(session.id, picks);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pick locked')));
    } on ConflictException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } on ValidationException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't save")));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      backgroundColor: t.colorScheme.surface,
      body: SafeArea(
        bottom: false,
        child: FutureBuilder<_PredictData>(
          future: _data,
          builder: (_, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return ErrorView(
                error: snap.error!,
                stack: snap.stackTrace,
                where: 'Predict',
                onRetry: () {
                  setState(() {
                    _data = _load();
                  });
                },
              );
            }
            final d = snap.data!;
            if (d.event == null || d.session == null) {
              return Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.lg, vertical: Spacing.xxl),
                child: AppCard(
                  background: t.mutedSurface,
                  padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.lg, vertical: Spacing.xxl),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('NO UPCOMING SESSION',
                            style: AppText.label(11)),
                        const SizedBox(height: Spacing.sm),
                        Text(
                          "Nothing to predict right now.",
                          style: AppText.body(13,
                              color: t.colorScheme.onSurface.withOpacity(0.7)),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }
            final Event event = d.event!;
            final Session session = d.session!;
            _currentType = session.type;
            final req = requiredPicks(session.type);
            final scope = AppState.of(context);
            final locked = scope.predictions.prediction(session.id)?.isLocked ?? false;
            return GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragEnd: (details) {
                final v = details.primaryVelocity ?? 0;
                if (v.abs() < 250) return;
                final target = v < 0 ? d.next : d.prev;
                if (target != null) _navigateTo(target);
              },
              child: ListView(
                padding: const EdgeInsets.only(bottom: Spacing.xxl + Spacing.xxl),
                children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.lg, Spacing.lg, Spacing.sm),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: d.prev == null ? null : () => _navigateTo(d.prev!),
                        icon: const Icon(Icons.chevron_left, size: 22),
                        tooltip: 'Previous session',
                        visualDensity: VisualDensity.compact,
                      ),
                      Expanded(
                        child: Text(event.name,
                            textAlign: TextAlign.center, style: AppText.display(22)),
                      ),
                      IconButton(
                        onPressed: d.next == null ? null : () => _navigateTo(d.next!),
                        icon: const Icon(Icons.chevron_right, size: 22),
                        tooltip: 'Next session',
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Spacing.xl, 0, Spacing.xl, Spacing.sm),
                  child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 4),
                      decoration: BoxDecoration(border: Border.all(color: BrandColors.accent, width: 1.5), borderRadius: const BorderRadius.all(Radius.circular(999))),
                      child: Text(_lockLabel(session.scheduledStart), style: AppText.label(10, color: BrandColors.accent)),
                    ),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Spacing.xl, Spacing.md, Spacing.xl, Spacing.xs),
                  child: Text('${session.type.name.toUpperCase()} · TOP $req', style: AppText.label(11, color: t.colorScheme.onSurface.withOpacity(0.6))),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Spacing.lg, 6, Spacing.lg, 6),
                  child: Column(
                    children: List.generate(req, (i) {
                      final filled = i < _picks.length;
                      final pickCode = filled ? _picks[i] : null;
                      final r = filled ? d.drivers.firstWhere((dr) => dr.driverCode == pickCode, orElse: () => d.drivers.first) : null;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Slot(
                          position: i + 1,
                          driverCode: pickCode,
                          driverName: r?.driverName,
                          number: null,
                          constructorId: r?.constructorId,
                          onClear: filled && !locked
                              ? () => setState(() => _picks.removeAt(i))
                              : null,
                        ),
                      );
                    }),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.lg, Spacing.lg, Spacing.sm),
                  child: Text('DRIVERS', style: AppText.label(11, color: t.colorScheme.onSurface.withOpacity(0.6))),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
                  child: GridView.count(
                    crossAxisCount: 4,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                    childAspectRatio: 1.4,
                    children: d.drivers.map((r) {
                      final slot = _picks.indexOf(r.driverCode);
                      return DriverTile(
                        code: r.driverCode,
                        constructorId: r.constructorId,
                        pickedSlot: slot == -1 ? null : slot + 1,
                        onTap: locked ? null : () => _toggleDriver(r.driverCode),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: Spacing.xxl),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: locked || _saving ? null : (_picks.length == req ? _lock : null),
                      style: FilledButton.styleFrom(
                        backgroundColor: locked ? Colors.black : BrandColors.accent,
                        disabledBackgroundColor: locked ? Colors.black : null,
                        disabledForegroundColor: locked ? Colors.white : null,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: Spacing.md),
                        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                      ),
                      child: Text(locked ? 'LOCKED' : (_saving ? 'SAVING…' : 'LOCK PICK'),
                          style: AppText.label(13, color: Colors.white)),
                    ),
                  ),
                ),
              ],
              ),
            );
          },
        ),
      ),
    );
  }

  String _lockLabel(DateTime when) {
    final diff = when.difference(DateTime.now());
    if (diff.isNegative) return 'LOCKED';
    return 'LOCKS IN ${diff.inHours}h ${diff.inMinutes.remainder(60)}m';
  }
}

class _NavRef {
  final int sessionId;
  final DateTime scheduledStart;
  const _NavRef({required this.sessionId, required this.scheduledStart});
}

class _PredictData {
  final Event? event;
  final Session? session;
  final List<SessionResult> drivers;
  final _NavRef? prev;
  final _NavRef? next;
  _PredictData({
    required this.event,
    required this.session,
    required this.drivers,
    required this.prev,
    required this.next,
  });
}
