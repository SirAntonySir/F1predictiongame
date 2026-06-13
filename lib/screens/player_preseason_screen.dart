// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api/models/league_preseason_view.dart';
import '../api/models/standing.dart';
import '../components/error_view.dart';
import '../components/standings_skeleton.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'standings/preseason_tab.dart';

/// Per-player preseason projections screen — accessed from the player profile
/// "Preseason" linkout. Renders the same `PreseasonBodyView` the standings tab
/// uses, but with the leaderboard section omitted (the profile header already
/// shows league rank) and the section title bound to the player's name.
class PlayerPreseasonScreen extends StatefulWidget {
  final String leagueId;
  final String userId;
  final String displayName;
  const PlayerPreseasonScreen({
    super.key,
    required this.leagueId,
    required this.userId,
    required this.displayName,
  });
  @override
  State<PlayerPreseasonScreen> createState() => _PlayerPreseasonScreenState();
}

class _PlayerPreseasonScreenState extends State<PlayerPreseasonScreen> {
  Future<PreseasonBodyData>? _data;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _data ??= _load();
  }

  Future<PreseasonBodyData> _load() async {
    final scope = AppState.of(context);
    final results = await Future.wait([
      scope.api.leaguePreseason(widget.leagueId, asUserId: widget.userId),
      scope.api.driverStandings(),
      scope.api.constructorStandings(),
    ]);
    return PreseasonBodyData.from(
      view: results[0] as LeaguePreseasonView,
      drivers: results[1] as List<DriverStanding>,
      constructors: results[2] as List<ConstructorStanding>,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      backgroundColor: t.colorScheme.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.lg, Spacing.lg, Spacing.xs),
              child: Row(children: [
                IconButton(
                  onPressed: () => context.pop(),
                  icon: const Icon(Icons.arrow_back_ios_new, size: 16),
                ),
                Expanded(
                  child: Text(widget.displayName.toUpperCase(),
                      style: AppText.display(22),
                      maxLines: 1, overflow: TextOverflow.fade, softWrap: false),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.sm),
              child: Text('PRESEASON · PROJECTIONS', style: AppText.label(11)),
            ),
            Expanded(
              child: FutureBuilder<PreseasonBodyData>(
                future: _data,
                builder: (_, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const StandingsListSkeleton();
                  }
                  if (snap.hasError) {
                    return ErrorView(
                      error: snap.error!,
                      stack: snap.stackTrace,
                      where: 'Player preseason',
                      onRetry: () => setState(() => _data = _load()),
                    );
                  }
                  final title = "${widget.displayName.toUpperCase()}'S PROJECTIONS";
                  return PreseasonBodyView(
                    data: snap.data!,
                    // Leave myUserId null so the leaderboard's isMe styling
                    // doesn't fire — but it's also hidden via showLeaderboard.
                    myUserId: null,
                    sectionTitle: title,
                    showLeaderboard: false,
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
