// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:skeletonizer/skeletonizer.dart';
import '../api/models/event.dart';
import '../api/models/leaderboard_row.dart';
import '../api/models/prediction_view.dart';
import '../api/models/live_snapshot.dart';
import '../api/models/session.dart';
import '../api/models/session_result.dart';
import '../components/app_card.dart';
import '../components/countdown.dart';
import '../components/error_view.dart';
import '../components/pod_tile.dart';
import '../components/racing_stripes.dart';
import '../components/session_chip.dart';
import '../components/ticket_card.dart';
import '../domain/prediction.dart';
import '../domain/scoring.dart';
import '../state/app_state.dart';
import '../state/home_cache_controller.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/country_flags.dart';
import '../theme/team_colors.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// When non-null the hero countdown targets this session instead of the
  /// chronologically-next one. Set by tapping a chip on the hero card. Reset
  /// implicitly whenever the cache reloads onto a new event — picking a stale
  /// id is harmless, the resolver falls back to `d.next`.
  int? _heroSessionOverride;
  bool _kickedOffRefresh = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_kickedOffRefresh) {
      _kickedOffRefresh = true;
      // Fire a single refresh whenever this screen first sees a context. The
      // cache dedupes concurrent refreshes, so subsequent screen rebuilds
      // (route pops, tab switches) won't kick off duplicate fetches.
      // ignore: discarded_futures
      AppState.of(context).homeCache.refresh();
    }
  }

  /// Resolve which session the hero should target. Default: `d.next` (the
  /// backend's / locally-computed next session). If the user tapped a chip,
  /// the override wins — provided the chosen session still belongs to the
  /// current `nextEvent`. Stale overrides silently fall back to `d.next`.
  Session _resolveHeroSession(HomeData d) {
    final override = _heroSessionOverride;
    if (override != null && d.nextEvent != null) {
      for (final s in d.nextEvent!.sessions) {
        if (s.id == override) return s;
      }
    }
    return d.next!;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final scope = AppState.of(context);
    final cache = scope.homeCache;
    return Scaffold(
      backgroundColor: t.colorScheme.surface,
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: cache,
          builder: (_, __) {
            final hasData = cache.data != null;
            // First-load error: we never got data, just show the error view.
            if (!hasData && cache.error != null && !cache.refreshing) {
              return ErrorView(
                error: cache.error!,
                stack: cache.stack,
                where: 'Home',
                // ignore: discarded_futures
                onRetry: () => cache.refresh(),
              );
            }
            // No data + refreshing → show placeholder under Skeletonizer so
            // the layout is intentional rather than a spinner-in-the-middle.
            // With data → show the real screen + a thin top progress bar
            // while we fetch fresh values in the background.
            final d = cache.data ?? HomeData.placeholder();
            final leagueName = scope.league.league?.name ??
                (scope.auth.leagues.isNotEmpty ? scope.auth.leagues.first.name : 'No league');
            final memberCount = scope.league.league?.members.length ??
                d.leaderboard.length;
            // Section header builders + card builders, paired up so the
            // 2-col path can rebuild each block as `Column(header,
            // Expanded(card))` inside an IntrinsicHeight row — keeping the
            // pick ticket and the last-race card the same height — while
            // the 1-col path stays a plain Column.
            final yourPickHeader = (d.next == null)
                ? null
                : _section('Your pick', onTap: () => context.go('/predict'));
            Widget pickCard() => ListenableBuilder(
                  listenable: scope.predictions,
                  builder: (_, __) => _pickCard(d, scope, t),
                );
            final lastRaceHeader =
                (d.lastEvent == null || d.lastRaceSession == null)
                    ? null
                    : _section(
                        'Last ${_sessionTypeLabel(d.lastRaceSession!.type)}'
                        ' · ${d.lastEvent!.name}', onTap: () {
                        context.push('/race/${d.lastEvent!.round}'
                            '/${d.lastRaceSession!.id}');
                      });
            Widget lastCard() => ListenableBuilder(
                  listenable: scope.predictions,
                  builder: (_, __) => _lastCard(d, scope, t),
                );
            final inSeasonBlock = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _section('$leagueName · In-season',
                    onTap: () => context.go('/standings/league?sort=inseason')),
                InkWell(
                  onTap: () => context.go('/standings/league?sort=inseason'),
                  child: _leagueCard(
                    d.leaderboard,
                    scope.auth.currentUserId,
                    t,
                    points: (r) => r.inSeasonPoints,
                  ),
                ),
              ],
            );
            final totalBlock = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _section('$leagueName · Total',
                    onTap: () => context.go('/standings/league?sort=total')),
                InkWell(
                  onTap: () => context.go('/standings/league?sort=total'),
                  child: _leagueCard(
                    d.leaderboard,
                    scope.auth.currentUserId,
                    t,
                    points: (r) => r.pointsTotal,
                  ),
                ),
              ],
            );

            final body = ListView(
              padding: const EdgeInsets.fromLTRB(0, Spacing.lg, 0, Spacing.xxl),
              children: [
                _topbar(leagueName, memberCount),
                const SizedBox(height: Spacing.xs),
                ListenableBuilder(
                  listenable: scope.live,
                  builder: (_, __) {
                    final live = scope.live;
                    final snap = live.snapshot;
                    if (live.liveSessionId != null &&
                        snap != null &&
                        snap.state != LiveState.finalised) {
                      final ev = d.events.firstWhere(
                        (e) =>
                            e.sessions.any((s) => s.id == live.liveSessionId),
                        orElse: () => d.nextEvent ?? d.events.first,
                      );
                      final sess = ev.sessions
                          .firstWhere((s) => s.id == live.liveSessionId);
                      return LiveHeroCard(
                        event: ev,
                        session: sess,
                        snap: snap,
                        onTap: () => context
                            .go('/race/${ev.round}/${live.liveSessionId}'),
                      );
                    }
                    if (d.next != null && d.nextEvent != null) {
                      return _hero(_resolveHeroSession(d), d.nextEvent!, t);
                    }
                    return _noNextHero(t);
                  },
                ),
                LayoutBuilder(
                  builder: (ctx, constraints) {
                    final twoCol = constraints.maxWidth >= 700;
                    if (!twoCol) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (yourPickHeader != null) yourPickHeader,
                          if (d.next != null) pickCard(),
                          if (lastRaceHeader != null) lastRaceHeader,
                          if (d.lastEvent != null) lastCard(),
                          inSeasonBlock,
                          totalBlock,
                        ],
                      );
                    }
                    // 2-col top row. We deliberately do NOT wrap in
                    // IntrinsicHeight here: the pick card contains a `Wrap`,
                    // which can't report intrinsic dimensions (its height
                    // depends on its width), and IntrinsicHeight would hang
                    // layout on iPad. Cards end up top-aligned with their
                    // natural heights — minor visual asymmetry, but loads.
                    Widget cardSide(Widget? header, Widget card) => Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (header != null) header,
                            card,
                          ],
                        );
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: d.next == null
                                  ? const SizedBox.shrink()
                                  : cardSide(yourPickHeader, pickCard()),
                            ),
                            Expanded(
                              child: d.lastEvent == null
                                  ? const SizedBox.shrink()
                                  : cardSide(lastRaceHeader, lastCard()),
                            ),
                          ],
                        ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: inSeasonBlock),
                            Expanded(child: totalBlock),
                          ],
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: Spacing.xxl),
              ],
            );
            // First-load → wrap the placeholder body in Skeletonizer so every
            // text/box renders as a skeleton block. Refresh-with-data → show
            // the real body and a thin progress bar pinned to the top edge.
            // `fit: expand` so the ListView gets the full surface; without it
            // the ListView falls back to loose-sizing inside the Stack and
            // children measure against an unbounded width.
            return Stack(
              fit: StackFit.expand,
              children: [
                Skeletonizer(
                  enabled: !hasData,
                  child: body,
                ),
                if (hasData && cache.refreshing)
                  const Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      color: BrandColors.accent,
                      backgroundColor: Colors.transparent,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _topbar(String leagueName, int memberCount) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
      child: Row(
        children: [
          // F1 logo plate + settings icon are fixed identity — Skeleton.keep
          // so they don't go gray during the first-load placeholder.
          Skeleton.keep(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  color: t.colorScheme.onSurface,
                  child: Text('F1',
                      style: AppText.display(14, color: t.colorScheme.surface)),
                ),
                const SizedBox(width: 4),
                Text('PG', style: AppText.display(14)),
              ],
            ),
          ),
          const Spacer(),
          // Tapping the league pill jumps to the league standings tab.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => context.go('/standings/league'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 5),
              decoration: BoxDecoration(
                // strokeColor adapts per theme — matches every other pill
                // border in the app (settings, standings tabs, etc.).
                border: Border.all(color: t.strokeColor, width: 1.5),
                borderRadius: const BorderRadius.all(Radius.circular(999)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Skeleton.keep(
                  child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: BrandColors.accent, shape: BoxShape.circle)),
                ),
                const SizedBox(width: 6),
                Text('$leagueName · $memberCount', style: AppText.label(11)),
              ]),
            ),
          ),
          const SizedBox(width: Spacing.sm),
          Skeleton.keep(
            child: IconButton(
              onPressed: () => context.push('/settings'),
              icon: const Icon(Icons.settings_outlined),
            ),
          ),
        ],
      ),
    );
  }

  Widget _noNextHero(ThemeData t) => Padding(
        padding: const EdgeInsets.fromLTRB(
            Spacing.lg, Spacing.xs, Spacing.lg, 0),
        child: AppCard(
          background: t.mutedSurface,
          padding: const EdgeInsets.symmetric(
              horizontal: Spacing.lg, vertical: Spacing.xxl),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('NO UPCOMING SESSION', style: AppText.label(11)),
                const SizedBox(height: Spacing.sm),
                Text("Season's done — or the schedule hasn't been published.",
                    textAlign: TextAlign.center,
                    style: AppText.body(13,
                        color:
                            t.colorScheme.onSurface.withOpacity(0.7))),
              ],
            ),
          ),
        ),
      );

  Widget _hero(Session next, Event nextEvent, ThemeData t) {
    final flag = flagFor(nextEvent.country);
    final lines = _splitRaceName(nextEvent.name);
    final dateLabel = DateFormat('EEE d MMM').format(next.scheduledStart);
    final timeLabel = DateFormat('HH:mm').format(next.scheduledStart);
    final typeLabel = _sessionTypeLabel(next.type);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xs, Spacing.lg, 0),
      child: AppCard(
        background: BrandColors.accent,
        padding: EdgeInsets.zero,
        child: Stack(
          children: [
            const Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: RacingStripesPainter()),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Spacing.xl, Spacing.xl, Spacing.xl, Spacing.xl),
              child: DefaultTextStyle.merge(
                style: const TextStyle(color: Colors.white),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            '${flag != null ? '$flag  ' : ''}${nextEvent.country.toUpperCase()} · ROUND ${nextEvent.round}',
                            style: AppText.label(10,
                                color: Colors.white.withOpacity(0.85)),
                          ),
                        ),
                        const SizedBox(width: Spacing.sm),
                        Text(typeLabel,
                            style: AppText.label(10,
                                color: Colors.white.withOpacity(0.85))),
                      ],
                    ),
                    const SizedBox(height: Spacing.sm),
                    for (final line in lines)
                      Text(line.toUpperCase(),
                          style: AppText.display(30, color: Colors.white)),
                    const SizedBox(height: Spacing.xs),
                    Text(
                      '$dateLabel · $timeLabel · ${nextEvent.circuitName}',
                      style: AppText.body(11,
                          color: Colors.white.withOpacity(0.9)),
                    ),
                    const SizedBox(height: Spacing.md),
                    Countdown(target: next.scheduledStart, size: 30),
                    const SizedBox(height: Spacing.md),
                    Row(
                      children: _chips(next, nextEvent)
                          .map((c) => Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: c))
                          .toList(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<String> _splitRaceName(String name) {
    const tail = ' Grand Prix';
    if (name.endsWith(tail)) {
      return [name.substring(0, name.length - tail.length), 'Grand Prix'];
    }
    return [name];
  }

  String _sessionTypeLabel(SessionType type) {
    switch (type) {
      case SessionType.race:
        return 'RACE';
      case SessionType.qualifying:
        return 'QUALI';
      case SessionType.sprint_quali:
        return 'SPRINT QUALI';
      case SessionType.sprint:
        return 'SPRINT';
      case SessionType.fp1:
      case SessionType.fp2:
      case SessionType.fp3:
        return type.name.toUpperCase();
    }
  }

  List<Widget> _chips(Session next, Event nextEvent) {
    final order = [SessionType.fp1, SessionType.fp2, SessionType.fp3,
      SessionType.qualifying, SessionType.sprint_quali, SessionType.sprint, SessionType.race];
    final labels = {
      SessionType.fp1:'FP1', SessionType.fp2:'FP2', SessionType.fp3:'FP3',
      SessionType.qualifying:'QUALI', SessionType.sprint_quali:'SQ',
      SessionType.sprint:'SPRINT', SessionType.race:'RACE',
    };
    return [
      for (final t in order)
        if (nextEvent.sessions.any((s) => s.type == t))
          () {
            final session = nextEvent.sessions.firstWhere((s) => s.type == t);
            // "Done" = finished (results in) OR simply past its scheduled end,
            // so practice sessions — which never get a 'finished' status — also
            // strike through once they're over.
            final isDone = session.status == SessionStatus.finished ||
                session.scheduledEnd.isBefore(DateTime.now());
            return SessionChip(
              label: labels[t]!,
              state: isDone
                  ? ChipState.done
                  : (next.id == session.id ? ChipState.next : ChipState.idle),
              // Tapping retargets the hero's countdown at this session.
              // Past/finished sessions stay non-interactive — nothing to
              // count down to.
              onTap: isDone
                  ? null
                  : () => setState(() => _heroSessionOverride = session.id),
            );
          }(),
    ];
  }

  Widget _section(String title, {VoidCallback? onTap}) {
    // Use theme-aware onSurface so the "All ›" affordance stays readable in
    // dark mode (was hardcoded black, which disappeared on dark iPad/iOS).
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.xl, Spacing.xl, Spacing.xl, Spacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: AppText.label(11),
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: Spacing.sm),
            // The affordance is a fixed label, not data — keep it readable
            // during skeleton loading so the user understands the section is
            // interactive even before content lands.
            Skeleton.keep(
              child: GestureDetector(
                onTap: onTap,
                child: Text(
                  'All ›',
                  style: AppText.label(11,
                      color: t.colorScheme.onSurface.withOpacity(0.5)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _pickCard(HomeData d, scope, ThemeData t) {
    // Use the next *pickable* session — d.next can be FP1 which has no
    // prediction. Falls back to d.next for the rare case where there's no
    // upcoming scorable session at all (shouldn't normally happen).
    final pickSession = d.nextPickable ?? d.next!;
    final sessionId = pickSession.id;
    // `scope` is dynamic here (private InheritedWidget type can't appear in
    // public method signatures), so cast the prediction lookup to restore
    // static typing — otherwise `.toList()` produces List<dynamic>.
    final PredictionView? pred =
        scope.predictions.prediction(sessionId) as PredictionView?;
    final picks =
        pred?.picks.map((p) => p.driverCode).toList() ?? const <String>[];
    final locked = pred?.isLocked ?? false;
    final empty = picks.isEmpty;
    final sessionLabel = _sessionTypeLabel(pickSession.type);
    // Split tap zones: tapping the body opens the race-detail view (same
    // route the calendar uses), tapping the EDIT/PICK stub jumps straight
    // into the predict screen.
    final round = d.pickEvent?.round ?? d.nextEvent?.round;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
      child: TicketCard(
        onBodyTap: round == null
            ? null
            : () => context.push('/race/$round/$sessionId'),
        onStubTap: () => context.go('/predict?session=$sessionId'),
        stubWidth: 80,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                // Hardcoded black tones because the ticket card is cream in
                // both themes — using t.colorScheme.onSurface would render
                // white-on-cream in dark mode.
                Text(sessionLabel,
                    style: AppText.label(10,
                        color: Colors.black.withOpacity(0.6))),
                const SizedBox(width: 6),
                _statusDot(t, empty: empty, locked: locked),
                const SizedBox(width: 4),
                Text(empty ? 'no picks' : (locked ? 'locked' : 'draft'),
                    style: AppText.label(10,
                        color: Colors.black.withOpacity(0.6))),
                const Spacer(),
                Text('YOUR PICK',
                    style: AppText.label(9,
                        color: Colors.black.withOpacity(0.45))),
              ],
            ),
            const SizedBox(height: 10),
            if (empty)
              Text('Tap to make your pick',
                  style: AppText.body(13,
                      color: Colors.black.withOpacity(0.5))
                      .copyWith(fontStyle: FontStyle.italic))
            else
              Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < picks.length; i++)
                    _pickChip(t, i + 1, picks[i]),
                ],
              ),
          ],
        ),
        stub: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(empty ? 'PICK' : (locked ? 'LOCKED' : 'EDIT'),
                style: AppText.display(15,
                    color: empty ? BrandColors.accent : Colors.black)),
            const SizedBox(height: 4),
            Text(empty ? 'tap →' : (locked ? '✦' : 'tap →'),
                style: AppText.label(9,
                    color: Colors.black.withOpacity(0.55))),
          ],
        ),
      ),
    );
  }

  Widget _statusDot(ThemeData t, {required bool empty, required bool locked}) {
    final color = empty
        ? BrandColors.accent
        : (locked ? Colors.black : Colors.black.withOpacity(0.4));
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  Widget _pickChip(ThemeData t, int position, String driverCode) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.08),
            borderRadius: const BorderRadius.all(Radius.circular(4)),
          ),
          child: Text('P$position',
              style: AppText.label(9, color: Colors.black.withOpacity(0.7))),
        ),
        const SizedBox(width: 6),
        Text(driverCode,
            style: AppText.body(14, weight: FontWeight.w800, color: Colors.black)),
      ],
    );
  }

  Widget _lastCard(HomeData d, scope, ThemeData t) {
    final lastSession = d.lastRaceSession;
    final PredictionView? pred = lastSession == null
        ? null
        : scope.predictions.prediction(lastSession.id) as PredictionView?;
    final picks =
        pred?.picks.map((p) => p.driverCode).toList() ?? const <String>[];
    // Render as many finisher tiles as the session's pick depth (race = 5,
    // sprint = 3, qualifying = 2, sprint-quali = 1) so users see every slot
    // they were asked to predict, not a fixed top-3. Falls back to 3 when
    // there's no session for some reason.
    final topN = lastSession != null ? requiredPicks(lastSession.type) : 3;
    // Points come from the backend's authoritative score (it includes the team
    // bonus and DNF/standings logic the client can't reproduce). Null until the
    // scores load or the session is scored — in which case we show the
    // exact-count alone rather than recompute with the client's diverging
    // formula (which would print a wrong figure, e.g. +8 instead of +4).
    final int? score = lastSession == null
        ? null
        : scope.predictions.score(lastSession.id)?.pointsTotal;
    int exactHits = 0;
    if (lastSession != null && picks.isNotEmpty && d.lastResult.isNotEmpty) {
      for (var i = 0; i < picks.length; i++) {
        if (outcomeFor(picks[i], i + 1, d.lastResult, topN) ==
            PickOutcome.exact) {
          exactHits++;
        }
      }
    }
    final route = lastSession == null || d.lastEvent == null
        ? null
        : '/race/${d.lastEvent!.round}/${lastSession.id}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
      child: InkWell(
        onTap: route == null ? null : () => context.push(route),
        borderRadius: const BorderRadius.all(Radius.circular(14)),
        child: AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Top $topN',
                      style: AppText.label(11,
                          color: t.colorScheme.onSurface.withOpacity(0.6))),
                  if (picks.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: const BoxDecoration(
                        color: BrandColors.ok,
                        borderRadius: BorderRadius.all(Radius.circular(6)),
                      ),
                      child: Text(
                          score != null
                              ? '+$score pts · $exactHits exact'
                              : '$exactHits exact',
                          style: AppText.label(9, color: Colors.black)),
                    ),
                ],
              ),
              const SizedBox(height: Spacing.sm),
              Row(children: [
                for (final r in d.lastResult.take(topN))
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: PodTile(
                        position: r.position,
                        driverCode: r.driverCode,
                        constructorId: r.constructorId,
                        mark: _markFor(picks, r),
                      ),
                    ),
                  ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  PodMark _markFor(List<String> picks, SessionResult r) {
    if (picks.isEmpty) return PodMark.none;
    final slotIndex = r.position - 1;
    if (slotIndex >= picks.length) return PodMark.none;
    return picks[slotIndex] == r.driverCode ? PodMark.exact : PodMark.miss;
  }

  Widget _leagueCard(
    List<LeaderboardRow> rows,
    String? meId,
    ThemeData t, {
    required int Function(LeaderboardRow) points,
  }) {
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
        child: AppCard(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Spacing.md),
            child: Text(
              'Leaderboard will fill in as sessions finish.',
              style: AppText.body(12, color: t.colorScheme.onSurface.withOpacity(0.6)),
            ),
          ),
        ),
      );
    }
    final preview = [...rows]
      ..sort((a, b) => points(b).compareTo(points(a)));
    final top = preview.take(4).toList();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
      child: Column(
        children: List.generate(top.length, (i) {
          final r = top[i];
          final isMe = r.userId == meId;
          return Padding(
            padding: const EdgeInsets.only(bottom: Spacing.xs),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.sm, vertical: Spacing.xs),
              decoration: BoxDecoration(
                color: isMe ? t.rowHighlight : null,
                border: Border.all(color: t.strokeColor, width: Strokes.card),
                borderRadius: Radii.rLg,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    child: Text('${i + 1}',
                        style: AppText.display(13,
                            color: isMe
                                ? BrandColors.accent
                                : t.colorScheme.onSurface)),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: Text(
                      isMe ? '${r.displayName} (you)' : r.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: AppText.body(13,
                          weight: isMe ? FontWeight.w800 : FontWeight.w600),
                    ),
                  ),
                  SizedBox(
                    width: 40,
                    child: Text('${points(r)}',
                        style: AppText.display(15),
                        textAlign: TextAlign.right),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// Live-session card shown on Home in place of the next/countdown hero while a
/// scorable session is in progress. Branded red shell (matching the normal
/// hero — racing stripes, flag, big event title, LIVE pulse) with a readable
/// inner panel for the live top-5 + projected points.
class LiveHeroCard extends StatelessWidget {
  final Event event;
  final Session session;
  final LiveSnapshot snap;
  final VoidCallback onTap;
  const LiveHeroCard({
    super.key,
    required this.event,
    required this.session,
    required this.snap,
    required this.onTap,
  });

  String get _typeLabel {
    switch (session.type) {
      case SessionType.race:
        return 'RACE';
      case SessionType.qualifying:
        return 'QUALIFYING';
      case SessionType.sprint:
        return 'SPRINT';
      case SessionType.sprint_quali:
        return 'SPRINT QUALI';
      case SessionType.fp1:
      case SessionType.fp2:
      case SessionType.fp3:
        return session.type.name.toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final flag = flagFor(event.country);
    final top = snap.order.take(5).toList();
    final pts = snap.myPointsTotal;
    final badge = snap.state == LiveState.provisional ? 'PROVISIONAL' : 'LIVE';

    return Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xs, Spacing.lg, 0),
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.all(Radius.circular(14)),
        child: AppCard(
          background: BrandColors.accent,
          padding: EdgeInsets.zero,
          child: Stack(
            children: [
              const Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: RacingStripesPainter()),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(Spacing.lg),
                child: DefaultTextStyle.merge(
                  style: const TextStyle(color: Colors.white),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${flag != null ? '$flag  ' : ''}${event.country.toUpperCase()} · ROUND ${event.round}',
                              style: AppText.label(10,
                                  color: Colors.white.withOpacity(0.85)),
                            ),
                          ),
                          const SizedBox(width: Spacing.sm),
                          Container(
                              width: 7,
                              height: 7,
                              decoration: const BoxDecoration(
                                  color: Colors.white, shape: BoxShape.circle)),
                          const SizedBox(width: 5),
                          Text('$badge · $_typeLabel',
                              style: AppText.label(10, color: Colors.white)),
                        ],
                      ),
                      const SizedBox(height: Spacing.sm),
                      Text(event.name.toUpperCase(),
                          style: AppText.display(24, color: Colors.white)),
                      const SizedBox(height: Spacing.md),
                      Container(
                        decoration: BoxDecoration(
                          color: t.colorScheme.surface,
                          borderRadius:
                              const BorderRadius.all(Radius.circular(12)),
                        ),
                        padding: const EdgeInsets.all(Spacing.sm),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final r in top)
                              Padding(
                                padding: const EdgeInsets.only(bottom: Spacing.xs),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: Spacing.sm, vertical: Spacing.xs),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: t.strokeColor, width: Strokes.card),
                                    borderRadius: Radii.rLg,
                                  ),
                                  child: Row(children: [
                                    SizedBox(
                                        width: 22,
                                        child: Text('${r.position}',
                                            style: AppText.display(13,
                                                color: t.colorScheme.onSurface))),
                                    const SizedBox(width: Spacing.xs),
                                    Container(
                                      width: 5,
                                      height: 22,
                                      decoration: BoxDecoration(
                                        color: teamColor(r.constructorId,
                                            fallbackHex: r.teamColour),
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                    const SizedBox(width: Spacing.sm),
                                    SizedBox(
                                        width: 42,
                                        child: Text(r.driverCode,
                                            style: AppText.body(12,
                                                weight: FontWeight.w800,
                                                color: t.colorScheme.onSurface))),
                                    Expanded(
                                        child: Text(r.driverName,
                                            overflow: TextOverflow.ellipsis,
                                            style: AppText.body(12,
                                                color: t.colorScheme.onSurface
                                                    .withOpacity(0.7)))),
                                  ]),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (pts != null) ...[
                        const SizedBox(height: Spacing.md),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text('YOUR PROJECTED',
                                style: AppText.label(10,
                                    color: Colors.white.withOpacity(0.85))),
                            const SizedBox(width: Spacing.sm),
                            Text('+$pts',
                                style:
                                    AppText.display(26, color: Colors.white)),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


