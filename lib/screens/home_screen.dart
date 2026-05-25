// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../api/api_client.dart';
import '../api/models/event.dart';
import '../api/models/session.dart';
import '../api/models/session_result.dart';
import '../components/app_card.dart';
import '../components/countdown.dart';
import '../components/pod_tile.dart';
import '../components/session_chip.dart';
import '../state/app_state.dart';
import '../theme/colors.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Future<_HomeData>? _data;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _data ??= _load(AppState.of(context).api);
  }

  Future<_HomeData> _load(ApiClient api) async {
    final events = await api.events();
    final next = await api.nextSession();
    final last = events.lastWhere(
      (e) => e.sessions.any((s) => s.type == SessionType.race && s.status == SessionStatus.finished),
      orElse: () => events.first,
    );
    final lastRace = last.sessions.firstWhere((s) => s.type == SessionType.race);
    final lastResult = await api.sessionResults(lastRace.id);
    final nextEvent = events.firstWhere(
      (e) => e.sessions.any((s) => s.id == next.id),
      orElse: () => events.first,
    );
    return _HomeData(events: events, next: next, nextEvent: nextEvent, lastEvent: last, lastResult: lastResult);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final scope = AppState.of(context);
    return Scaffold(
      backgroundColor: t.colorScheme.surface,
      body: SafeArea(
        bottom: false,
        child: FutureBuilder<_HomeData>(
          future: _data,
          builder: (_, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) return Center(child: Text('${snap.error}'));
            final d = snap.data!;
            return ListView(
              padding: const EdgeInsets.fromLTRB(0, Spacing.lg, 0, Spacing.xxl),
              children: [
                _topbar(scope.league.league.name, scope.league.league.players.length),
                const SizedBox(height: Spacing.xs),
                _hero(d, t),
                _section('Last race · ${d.lastEvent.name}', onTap: () =>
                    context.go('/race/${d.lastEvent.round}/${d.lastEvent.sessions.firstWhere((s) => s.type == SessionType.race).id}')),
                _lastCard(d, t),
                _section('${scope.league.league.name} · Standings', onTap: () => context.go('/standings/league')),
                _leagueCard(scope.league.league.players.map((p) => p.displayName).toList(), scope.auth.currentUserId, t),
                const SizedBox(height: Spacing.xxl),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _topbar(String leagueName, int memberCount) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
        child: Row(
          children: [
            Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3), color: Colors.black,
              child: Text('F1', style: AppText.display(14, color: Colors.white))),
            const SizedBox(width: 4),
            Text('PG', style: AppText.display(14)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 5),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black, width: 1.5),
                borderRadius: const BorderRadius.all(Radius.circular(999)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 8, height: 8, decoration: const BoxDecoration(color: BrandColors.accent, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text('$leagueName · $memberCount', style: AppText.label(11)),
              ]),
            ),
            const SizedBox(width: Spacing.sm),
            IconButton(onPressed: () => context.push('/settings'), icon: const Icon(Icons.settings_outlined)),
          ],
        ),
      );

  Widget _hero(_HomeData d, ThemeData t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xs, Spacing.lg, 0),
      child: AppCard(
        background: BrandColors.accent,
        padding: const EdgeInsets.fromLTRB(Spacing.xl, Spacing.xl, Spacing.xl, Spacing.xl),
        child: DefaultTextStyle.merge(
          style: const TextStyle(color: Colors.white),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${d.nextEvent.country.toUpperCase()} · ROUND ${d.nextEvent.round}',
                  style: AppText.label(10, color: Colors.white.withOpacity(0.85))),
              const SizedBox(height: Spacing.xs),
              Text(d.nextEvent.name.toUpperCase(), style: AppText.display(28, color: Colors.white)),
              const SizedBox(height: Spacing.xs),
              Countdown(target: d.next.scheduledStart, size: 30),
              const SizedBox(height: Spacing.md),
              Row(children: _chips(d).map((c) => Padding(padding: const EdgeInsets.only(right: 6), child: c)).toList()),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _chips(_HomeData d) {
    final order = [SessionType.fp1, SessionType.fp2, SessionType.fp3,
      SessionType.qualifying, SessionType.sprint_quali, SessionType.sprint, SessionType.race];
    final labels = {
      SessionType.fp1:'FP1', SessionType.fp2:'FP2', SessionType.fp3:'FP3',
      SessionType.qualifying:'QUALI', SessionType.sprint_quali:'SQ',
      SessionType.sprint:'SPRINT', SessionType.race:'RACE',
    };
    return [
      for (final t in order)
        if (d.nextEvent.sessions.any((s) => s.type == t))
          SessionChip(label: labels[t]!, state: d.nextEvent.sessions
              .firstWhere((s) => s.type == t).status == SessionStatus.finished
              ? ChipState.done
              : (d.next.id == d.nextEvent.sessions.firstWhere((s) => s.type == t).id
                  ? ChipState.next : ChipState.idle))
    ];
  }

  Widget _section(String title, {VoidCallback? onTap}) => Padding(
        padding: const EdgeInsets.fromLTRB(Spacing.xl, Spacing.xl, Spacing.xl, Spacing.xs),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title.toUpperCase(), style: AppText.label(11)),
            if (onTap != null)
              GestureDetector(onTap: onTap, child: Text('All ›', style: AppText.label(11, color: Colors.black.withOpacity(0.5)))),
          ],
        ),
      );

  Widget _lastCard(_HomeData d, ThemeData t) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
        child: AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Top 3', style: AppText.label(11, color: t.colorScheme.onSurface.withOpacity(0.6))),
                ],
              ),
              const SizedBox(height: Spacing.sm),
              Row(children: [
                for (final r in d.lastResult.take(3))
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: PodTile(position: r.position, driverCode: r.driverCode, constructorId: r.constructorId),
                    ),
                  ),
              ]),
            ],
          ),
        ),
      );

  Widget _leagueCard(List<String> names, String? meId, ThemeData t) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
        child: AppCard(
          child: Column(
            children: List.generate(names.length.clamp(0, 4), (i) {
              final isMe = names[i].toLowerCase() == (meId ?? '');
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(children: [
                      SizedBox(width: 18, child: Text('${i+1}', style: AppText.display(13, color: isMe ? BrandColors.accent : t.colorScheme.onSurface))),
                      const SizedBox(width: 8),
                      Text(isMe ? '${names[i]} (you)' : names[i], style: AppText.body(13, weight: isMe ? FontWeight.w800 : FontWeight.w600)),
                    ]),
                    Text('${(200 - i * 18)}', style: AppText.display(13)),
                  ],
                ),
              );
            }),
          ),
        ),
      );
}

class _HomeData {
  final List<Event> events;
  final Session next;
  final Event nextEvent;
  final Event lastEvent;
  final List<SessionResult> lastResult;
  _HomeData({required this.events, required this.next, required this.nextEvent,
    required this.lastEvent, required this.lastResult});
}
