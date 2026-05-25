// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import '../api/models/event.dart';
import '../api/models/session.dart';
import '../api/models/session_result.dart';
import '../components/driver_tile.dart';
import '../components/slot.dart';
import '../domain/prediction.dart';
import '../state/app_state.dart';
import '../theme/colors.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

class PredictScreen extends StatefulWidget {
  const PredictScreen({super.key});
  @override
  State<PredictScreen> createState() => _PredictScreenState();
}

class _PredictScreenState extends State<PredictScreen> {
  Future<_PredictData>? _data;
  List<String> _picks = [];

  Future<_PredictData> _load() async {
    final scope = AppState.of(context);
    final events = await scope.api.events();
    final upcoming = events.firstWhere(
      (e) => e.sessions.any((s) => s.status == SessionStatus.scheduled),
      orElse: () => events.last,
    );
    final session = upcoming.sessions.firstWhere(
      (s) => s.status == SessionStatus.scheduled,
      orElse: () => upcoming.sessions.last,
    );
    final existing = scope.predictions.picksFor(userId: scope.auth.currentUserId!, sessionId: session.id);
    _picks = List<String>.from(existing);
    // Drivers from most recent finished session as a proxy lineup
    final finished = events.expand((e) => e.sessions).where((s) => s.status == SessionStatus.finished).toList();
    finished.sort((a, b) => b.scheduledStart.compareTo(a.scheduledStart));
    final lineup = finished.isEmpty ? <SessionResult>[] : await scope.api.sessionResults(finished.first.id);
    return _PredictData(event: upcoming, session: session, drivers: lineup);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _data ??= _load();
  }

  void _toggleDriver(String code) {
    final required = requiredPicks(/*from data*/ _currentType);
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
    final userId = scope.auth.currentUserId!;
    if (scope.predictions.isLocked(userId: userId, sessionId: session.id)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pick already locked')));
      }
      return;
    }
    await scope.predictions.save(userId: userId, sessionId: session.id, picks: _picks);
    await scope.predictions.lock(userId: userId, sessionId: session.id);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pick locked')));
    setState(() {});
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
            if (snap.hasError) return Center(child: Text('${snap.error}'));
            final d = snap.data!;
            _currentType = d.session.type;
            final req = requiredPicks(d.session.type);
            final scope = AppState.of(context);
            final locked = scope.auth.currentUserId != null &&
                scope.predictions.isLocked(
                    userId: scope.auth.currentUserId!, sessionId: d.session.id);
            return ListView(
              padding: const EdgeInsets.only(bottom: Spacing.xxl + Spacing.xxl),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(Spacing.xl, Spacing.lg, Spacing.xl, Spacing.sm),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text(d.event.name, style: AppText.display(22)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 4),
                      decoration: BoxDecoration(border: Border.all(color: BrandColors.accent, width: 1.5), borderRadius: const BorderRadius.all(Radius.circular(999))),
                      child: Text(_lockLabel(d.session.scheduledStart), style: AppText.label(10, color: BrandColors.accent)),
                    ),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Spacing.xl, Spacing.md, Spacing.xl, Spacing.xs),
                  child: Text('${d.session.type.name.toUpperCase()} · TOP $req', style: AppText.label(11, color: t.colorScheme.onSurface.withOpacity(0.6))),
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
                      onPressed: locked ? null : (_picks.length == req ? _lock : null),
                      style: FilledButton.styleFrom(
                        backgroundColor: locked ? Colors.black : BrandColors.accent,
                        disabledBackgroundColor: locked ? Colors.black : null,
                        disabledForegroundColor: locked ? Colors.white : null,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: Spacing.md),
                        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                      ),
                      child: Text(locked ? 'LOCKED' : 'LOCK PICK',
                          style: AppText.label(13, color: Colors.white)),
                    ),
                  ),
                ),
              ],
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

class _PredictData {
  final Event event;
  final Session session;
  final List<SessionResult> drivers;
  _PredictData({required this.event, required this.session, required this.drivers});
}
