import 'package:flutter/material.dart';
import '../api/models/my_score.dart';
import '../state/app_state.dart';

class ScoreDetailScreen extends StatefulWidget {
  const ScoreDetailScreen({super.key});
  @override
  State<ScoreDetailScreen> createState() => _ScoreDetailScreenState();
}

class _ScoreDetailScreenState extends State<ScoreDetailScreen> {
  bool _loading = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading) _load();
  }

  Future<void> _load() async {
    final scope = AppState.of(context);
    try {
      await scope.predictions.refreshScores();
    } catch (_) {/* surface via empty state if needed */}
    if (mounted) setState(() => _loading = false);
  }

  String _pad(int n) => n < 10 ? '0$n' : '$n';

  @override
  Widget build(BuildContext context) {
    final scope = AppState.of(context);
    final all = [
      for (final sid in scope.predictions.allScoreIds)
        if (scope.predictions.score(sid) != null) scope.predictions.score(sid)!,
    ]..sort((MyScore a, MyScore b) => b.sessionScheduledStart.compareTo(a.sessionScheduledStart));

    return Scaffold(
      appBar: AppBar(title: const Text('My Scores')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : all.isEmpty
              ? const Center(child: Text('No scored sessions yet. Once the next race finishes, your scores will appear here.'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    itemCount: all.length,
                    itemBuilder: (_, i) {
                      final s = all[i];
                      return ExpansionTile(
                        title: Text('${s.eventName} ${s.sessionType.name}'),
                        subtitle: Text('${s.sessionScheduledStart.year}-${_pad(s.sessionScheduledStart.month)}-${_pad(s.sessionScheduledStart.day)}'),
                        trailing: Text('${s.pointsTotal} pts'),
                        children: [
                          for (final p in s.breakdown.perPosition)
                            ListTile(
                              dense: true,
                              title: Text('P${p.position}  ${p.exact ? 'exact' : p.wrongPos ? 'wrongPos' : 'miss'}'),
                              trailing: Text('+${p.points}'),
                            ),
                          if (s.breakdown.teamBonus.applied)
                            ListTile(
                              dense: true,
                              title: const Text('Team bonus'),
                              trailing: Text('+${s.breakdown.teamBonus.points}'),
                            ),
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text('Rule: ${s.breakdown.rule}', style: Theme.of(context).textTheme.bodySmall),
                          ),
                        ],
                      );
                    },
                  ),
                ),
    );
  }
}
