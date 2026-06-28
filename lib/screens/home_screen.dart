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
import '../components/app_card.dart';
import '../components/circuit_svg.dart';
import '../components/countdown.dart';
import '../components/league_row.dart' show LeagueRowYouBadge;
import '../components/error_view.dart';
import '../components/trend_badge.dart';
import '../domain/leaderboard_trend.dart';
import '../domain/live_session.dart';
import '../components/racing_stripes.dart';
import '../components/session_chip.dart';
import '../components/ticket/pick_ticket.dart';
import '../components/ticket/souvenir_ticket.dart';
import '../state/app_state.dart';
import '../state/home_cache_controller.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/country_flags.dart';
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
            Widget pickCard({Session? sessionOverride}) => ListenableBuilder(
                  listenable: scope.predictions,
                  builder: (_, __) =>
                      _pickCard(d, scope, t, sessionOverride: sessionOverride),
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
                    prevPoints: (r) => r.prevInSeasonPoints,
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
                    prevPoints: (r) => r.prevPointsTotal,
                  ),
                ),
              ],
            );

            final body = ListView(
              // Always-scrollable so pull-to-refresh works even when the
              // content fits the viewport (short seasons / no-next-session).
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(0, Spacing.lg, 0, Spacing.xxl),
              children: [
                _topbar(leagueName, memberCount),
                const SizedBox(height: Spacing.xs),
                ListenableBuilder(
                  listenable: scope.live,
                  builder: (_, __) {
                    final live = scope.live;
                    final snap = live.snapshot;
                    final liveId = live.liveSessionId;
                    // Show the live hero while the session is actually running.
                    // "Running" is decided by the schedule (isSessionRunning),
                    // OR by the snapshot reporting `live` — the two can disagree
                    // because the backend's live-state flag lags the clock, and
                    // trusting the snapshot alone would skip a running race in
                    // favour of the *next* event's countdown. Once the race is
                    // provisional/finished, both are false and we fall through
                    // to the next-event hero (its souvenir shows under "Last
                    // race" by then).
                    if (liveId != null) {
                      Event? liveEvent;
                      Session? liveSess;
                      for (final e in d.events) {
                        for (final s in e.sessions) {
                          if (s.id == liveId) {
                            liveEvent = e;
                            liveSess = s;
                            break;
                          }
                        }
                        if (liveSess != null) break;
                      }
                      final runningNow = liveSess != null &&
                          (isSessionRunning(liveSess, DateTime.now()) ||
                              (snap != null && snap.state == LiveState.live));
                      if (runningNow && liveEvent != null) {
                        final ev = liveEvent;
                        return LiveHeroCard(
                          event: ev,
                          session: liveSess,
                          snap: snap,
                          onTap: () => context.go('/race/${ev.round}/$liveId'),
                        );
                      }
                    }
                    if (d.next != null && d.nextEvent != null) {
                      return _hero(_resolveHeroSession(d), d.nextEvent!, t);
                    }
                    return _noNextHero(t);
                  },
                ),
                ListenableBuilder(
                  // Rebuild when a session goes live / finalises so the
                  // Your-pick block can swap from the *next* pickable session
                  // to the *currently live* one (showing the locked ticket
                  // for what's actually running instead of the next race).
                  listenable: scope.live,
                  builder: (_, __) {
                    final live = scope.live;
                    final snap = live.snapshot;
                    final liveId = live.liveSessionId;
                    // Find the active session object inside the events list so
                    // PickTicket can resolve its event/round.
                    Session? liveSession;
                    if (liveId != null) {
                      for (final e in d.events) {
                        for (final s in e.sessions) {
                          if (s.id == liveId) {
                            liveSession = s;
                            break;
                          }
                        }
                        if (liveSession != null) break;
                      }
                    }
                    // "Live" pick swap is gated to actually-running sessions —
                    // decided by the schedule OR the snapshot's live state (same
                    // reasoning as the hero: the snapshot can lag the clock).
                    // Once provisional/finalised, both are false and we fall
                    // through to the next pickable session's card.
                    final isLive = liveSession != null &&
                        (isSessionRunning(liveSession, DateTime.now()) ||
                            (snap != null && snap.state == LiveState.live));
                    final pickOverride = isLive ? liveSession : null;
                    final showPick = isLive || d.next != null;
                    final pickHeader = !showPick
                        ? null
                        : (isLive
                            ? _section('Your pick · Locked')
                            : yourPickHeader);
                    Widget thePickCard() =>
                        pickCard(sessionOverride: pickOverride);
                    return LayoutBuilder(
                      builder: (ctx, constraints) {
                        final twoCol = constraints.maxWidth >= 700;
                        if (!twoCol) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (pickHeader != null) pickHeader,
                              if (showPick) thePickCard(),
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
                                  child: !showPick
                                      ? const SizedBox.shrink()
                                      : cardSide(pickHeader, thePickCard()),
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
                  child: RefreshIndicator(
                    onRefresh: cache.refresh,
                    color: BrandColors.accent,
                    child: body,
                  ),
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
              onPressed: () => context.push('/search'),
              icon: const Icon(Icons.search),
              tooltip: 'Search',
            ),
          ),
          Skeleton.keep(
            child: IconButton(
              onPressed: () => context.push('/notifications'),
              icon: const Icon(Icons.notifications_outlined),
              tooltip: 'Notifications',
            ),
          ),
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
      child: InkWell(
        onTap: () => context.push('/race/${nextEvent.round}/${next.id}'),
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
            // Circuit map — black-outline variant, anchored top-right of the
            // hero. Slides behind the text content. Renders nothing when
            // the event doesn't map to a known circuit id, so the layout is
            // unaffected on weekends we don't have data for.
            Positioned(
              top: Spacing.xxl + Spacing.sm,
              right: Spacing.lg,
              child: IgnorePointer(
                child: Opacity(
                  opacity: 0.5,
                  child: CircuitSvg(
                    event: nextEvent,
                    // 'white' (single-color stroked paths) renders reliably
                    // across every circuit. 'black-outline' is stacked outline
                    // + inner paths and silently fails to render for some
                    // circuits (catalunya was the holdout) — see race_tile.dart
                    // for the same reasoning on the calendar tile.
                    variant: 'white',
                    width: 150,
                    height: 150,
                  ),
                ),
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
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (flag != null) ...[
                                Text(flag, style: const TextStyle(fontSize: 18, height: 1)),
                                const SizedBox(width: 8),
                              ],
                              Flexible(
                                child: Text(
                                  '${nextEvent.country.toUpperCase()} · ROUND ${nextEvent.round}',
                                  style: AppText.label(10,
                                      color: Colors.white.withOpacity(0.85)),
                                  maxLines: 1,
                                  overflow: TextOverflow.fade,
                                  softWrap: false,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: Spacing.sm),
                        // Circuit name in the top-right. Fades on overflow so
                        // long names ("Circuit de Spa-Francorchamps") don't
                        // collide with the country label on the left.
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 160),
                          child: Text(
                            nextEvent.circuitName.toUpperCase(),
                            style: AppText.label(10,
                                color: Colors.white.withOpacity(0.85)),
                            maxLines: 1,
                            overflow: TextOverflow.fade,
                            softWrap: false,
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Spacing.sm),
                    for (final line in lines)
                      Text(line.toUpperCase(),
                          style: AppText.display(30, color: Colors.white)),
                    const SizedBox(height: Spacing.xs),
                    // Date/time line — circuit name moved to the top-right
                    // header, plus the session type label is already implied
                    // by the highlighted chip below.
                    Text(
                      '$dateLabel · $timeLabel · $typeLabel',
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

  Widget _pickCard(HomeData d, scope, ThemeData t, {Session? sessionOverride}) {
    // Use the next *pickable* session — d.next can be FP1 which has no
    // prediction. Falls back to d.next for the rare case where there's no
    // upcoming scorable session at all (shouldn't normally happen).
    // [sessionOverride] takes priority — used while a race is live to show
    // the locked ticket for the running session instead of the next one.
    final pickSession = sessionOverride ?? d.nextPickable ?? d.next!;
    final sessionId = pickSession.id;
    // Lazy + idempotent fetch — the predictions controller dedupes concurrent
    // requests and re-renders this card via its ListenableBuilder once the
    // response lands. Without this the home card stays on "NO PICKS" until
    // you visit the predict screen, because `prediction(id)` only reads the
    // local cache and the home screen never warms it.
    // ignore: discarded_futures
    scope.predictions.fetchPrediction(sessionId);
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
    // When a sessionOverride is in play (live session), resolve its parent
    // event from the events list instead of falling through to nextEvent —
    // otherwise the live ticket would carry the wrong round/circuit/style.
    Event? overrideEvent;
    if (sessionOverride != null) {
      for (final e in d.events) {
        if (e.sessions.any((s) => s.id == sessionOverride.id)) {
          overrideEvent = e;
          break;
        }
      }
    }
    final event = overrideEvent ?? d.pickEvent ?? d.nextEvent;
    final round = event?.round;
    if (event == null) {
      // No upcoming event at all — exit early so PickTicket has a real event.
      return const SizedBox.shrink();
    }
    // Pick.driverCode → constructorId via the most recent finished session's
    // classification — gives the P1 car silhouette its right team palette.
    // Resolves null when the driver wasn't in the last lineup (rare; reserve
    // drivers, mid-season swaps); PickTicket then renders without the car.
    final constructorByDriver = <String, String>{
      for (final r in d.lastResult) r.driverCode: r.constructorId,
    };
    final p1ConstructorId =
        picks.isEmpty ? null : constructorByDriver[picks.first];
    final dayTime = _formatDayTime(pickSession.scheduledStart);
    final status = empty ? 'NO PICKS' : (locked ? 'LOCKED' : 'DRAFT');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
      child: PickTicket(
        event: event,
        driverCodes: picks,
        p1ConstructorId: p1ConstructorId,
        circuitWatermark: CircuitSvg(event: event),
        dayTime: '$sessionLabel · $dayTime',
        statusOverride: status,
        sessionType: pickSession.type,
        onBodyTap: round == null
            ? null
            : () => context.push('/race/$round/$sessionId'),
        onStubTap: () => context.go('/predict?session=$sessionId'),
      ),
    );
  }

  static const _weekday = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
  String _formatDayTime(DateTime t) {
    final local = t.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '${_weekday[local.weekday - 1]} $hh:$mm';
  }

  Widget _lastCard(HomeData d, scope, ThemeData t) {
    final lastEvent = d.lastEvent;
    final lastSession = d.lastRaceSession;
    if (lastEvent == null || lastSession == null) {
      return const SizedBox.shrink();
    }
    // ignore: discarded_futures
    scope.predictions.fetchPrediction(lastSession.id);
    final PredictionView? pred =
        scope.predictions.prediction(lastSession.id) as PredictionView?;
    final picks =
        pred?.picks.map((p) => p.driverCode).toList() ?? const <String>[];
    // Backend's authoritative score (includes team bonus + DNF logic). Null
    // until the session is scored — souvenir then reads as +0 / OFF-PACE
    // until the scorer catches up, which is what you'd expect right after
    // the chequered flag too.
    final score =
        scope.predictions.score(lastSession.id)?.pointsTotal ?? 0;
    String? p1ConstructorId;
    if (picks.isNotEmpty) {
      for (final r in d.lastResult) {
        if (r.driverCode == picks.first) {
          p1ConstructorId = r.constructorId;
          break;
        }
      }
    }
    // Exact-position match per pick slot — those cells get the hand-drawn
    // tick painted on top inside SouvenirTicket. We compare against
    // `d.lastResult` (sorted by finishing position) so slot 0 = P1 etc.
    final correctSlots = <int>{
      for (var i = 0; i < picks.length; i++)
        if (i < d.lastResult.length &&
            d.lastResult[i].driverCode == picks[i])
          i,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
      child: SouvenirTicket(
        event: lastEvent,
        driverCodes: picks,
        scorePoints: score,
        p1ConstructorId: p1ConstructorId,
        circuitWatermark: CircuitSvg(event: lastEvent),
        correctSlots: correctSlots,
        onTap: () =>
            context.push('/race/${lastEvent.round}/${lastSession.id}'),
      ),
    );
  }

  Widget _leagueCard(
    List<LeaderboardRow> rows,
    String? meId,
    ThemeData t, {
    required int Function(LeaderboardRow) points,
    required int? Function(LeaderboardRow) prevPoints,
  }) {
    // Hide players who haven't scored in the current metric yet — a row of
    // zeros adds noise to the home preview without conveying any standing.
    final preview = [...rows.where((r) => points(r) > 0)]
      ..sort((a, b) => points(b).compareTo(points(a)));
    // Trend across the FULL filtered preview, not just the visible 4 — the
    // arrow on row 4 should reflect what happened across the whole league.
    final trendByUser = computeLeaderboardTrend(
      sortedRows: preview,
      prevPoints: prevPoints,
    );
    if (preview.isEmpty) {
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
    final top = preview.take(4).toList();
    final leagueId = AppState.of(context).league.league?.id;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
      // Single outer border around the whole list — individual rows keep
      // their inline styling (rank, name, points, isMe row-highlight) but
      // share one bordered container instead of stacking N bordered cards.
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: t.strokeColor, width: Strokes.card),
          borderRadius: Radii.rLg,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: List.generate(top.length, (i) {
            final r = top[i];
            final isMe = r.userId == meId;
            return InkWell(
              onTap: leagueId == null
                  ? null
                  : () => context.push('/league/$leagueId/player/${r.userId}'),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.sm, vertical: Spacing.sm),
                decoration: BoxDecoration(
                  border: i == top.length - 1
                      ? null
                      : Border(
                          bottom: BorderSide(
                              color: t.strokeColor.withOpacity(0.25),
                              width: 1),
                        ),
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
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              r.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.fade,
                              softWrap: false,
                              style: AppText.body(13,
                                  weight: isMe ? FontWeight.w800 : FontWeight.w600),
                            ),
                          ),
                          if (isMe) ...[
                            const SizedBox(width: 6),
                            const LeagueRowYouBadge(),
                          ],
                        ],
                      ),
                    ),
                    Builder(builder: (_) {
                      final tr = trendByUser[r.userId] ?? PositionTrend.equal;
                      if (tr.direction == TrendDirection.equal) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: TrendBadge(
                            direction: tr.direction,
                            label: '${tr.magnitude}'),
                      );
                    }),
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
  /// Null while the race is running by the schedule but the backend `/live`
  /// snapshot hasn't arrived yet — the card still renders its branded shell and
  /// defaults the badge to LIVE.
  final LiveSnapshot? snap;
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
    final flag = flagFor(event.country);
    final badge = snap?.state == LiveState.provisional ? 'PROVISIONAL' : 'LIVE';

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
              Positioned(
                top: Spacing.xxl + Spacing.sm,
                right: Spacing.lg,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: 0.5,
                    child: CircuitSvg(
                      event: event,
                      variant: 'white',
                      width: 150,
                      height: 150,
                    ),
                  ),
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


