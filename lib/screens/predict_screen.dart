import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../api/models/pick.dart';
import '../api/models/upcoming_prediction.dart';
import '../state/app_state.dart';

class PredictScreen extends StatefulWidget {
  const PredictScreen({super.key});
  @override
  State<PredictScreen> createState() => _PredictScreenState();
}

class _PredictScreenState extends State<PredictScreen> {
  Future<UpcomingPrediction?>? _data;
  List<String> _picks = [];
  bool _saving = false;

  Future<UpcomingPrediction?> _load() async {
    final scope = AppState.of(context);
    await scope.predictions.refreshUpcoming();
    final next = scope.predictions.upcoming.where((u) => !u.isLocked).toList()
      ..sort((a, b) => a.locksAt.compareTo(b.locksAt));
    if (next.isEmpty) return null;
    final u = next.first;
    final pred = await scope.predictions.fetchPrediction(u.sessionId);
    _picks = pred?.picks.map((p) => p.driverCode).toList() ?? [];
    return u;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _data ??= _load();
  }

  void _toggle(String code, int required) {
    setState(() {
      if (_picks.contains(code)) {
        _picks.remove(code);
      } else if (_picks.length < required) {
        _picks.add(code);
      }
    });
  }

  Future<void> _save(UpcomingPrediction u) async {
    final scope = AppState.of(context);
    setState(() => _saving = true);
    try {
      final picks = [for (var i = 0; i < _picks.length; i++) Pick(position: i + 1, driverCode: _picks[i])];
      await scope.predictions.savePrediction(u.sessionId, picks);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pick saved')));
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
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<UpcomingPrediction?>(
          future: _data,
          builder: (_, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Center(child: Text("Couldn't load: ${snap.error}"));
            }
            final u = snap.data;
            if (u == null) {
              return const Center(child: Text('Nothing to predict right now.'));
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(u.eventName, style: Theme.of(context).textTheme.headlineSmall),
                Text(u.sessionType.name),
                const SizedBox(height: 8),
                Text('Picks: ${_picks.length}/${u.picksRequired}'),
                const SizedBox(height: 16),
                FilledButton(
                  key: const Key('predict.save'),
                  onPressed: _saving || _picks.length != u.picksRequired ? null : () => _save(u),
                  child: Text(_saving ? 'Saving...' : 'Save picks'),
                ),
                const SizedBox(height: 16),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final d in _knownDrivers())
                    FilterChip(
                      label: Text(d),
                      selected: _picks.contains(d),
                      onSelected: (_) => _toggle(d, u.picksRequired),
                    ),
                ]),
              ],
            );
          },
        ),
      ),
    );
  }

  /// 2026 driver universe — lets the user pick without needing a separate
  /// lineup fetch. Driver-list polish is out of scope for this PR.
  List<String> _knownDrivers() => const [
        'VER','NOR','RUS','PIA','LEC','HAD','ANT','HAM','GAS','BEA',
        'OCO','LIN','ALB','BOR','COL','LAW','HUL','SAI','BOT','PER','ALO','STR',
      ];
}
