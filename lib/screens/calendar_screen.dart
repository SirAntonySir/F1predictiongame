// ignore_for_file: deprecated_member_use
import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:skeletonizer/skeletonizer.dart';
import '../api/models/event.dart';
import '../api/models/session.dart';
import '../domain/race_phase.dart';
import '../components/cached_view.dart';
import '../components/circuit_svg.dart';
import '../components/race_tile.dart';
import '../components/ticket/souvenir_ticket.dart';
import '../state/app_state.dart';
import '../state/async_cache.dart';
import '../theme/app_theme.dart';
import '../theme/country_flags.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late final AsyncCache<_CalData> _cache = AsyncCache<_CalData>(_fetch);
  final ScrollController _scroll = ScrollController();
  // GlobalKey attached to the live tile (or the next race when nothing is
  // live) so we can jump-scroll to it on first load.
  final GlobalKey _nextRaceKey = GlobalKey();
  bool _scrolledToNext = false;
  bool _kickedOffRefresh = false;
  // 'schedule' (default) shows the month-grouped race tiles; 'souvenirs' shows
  // the wallet-style stack of past souvenir tickets earned this season.
  String _tab = 'schedule';
  // When set, the wallet filters to souvenirs whose event.round matches.
  // Null means "ALL" — the default folder.
  int? _walletFilterRound;
  // Wallet scroll position drives the stack animation — every card's `top`
  // is recomputed from this controller's offset on each frame.
  late final ScrollController _walletScroll = ScrollController()
    ..addListener(_onWalletScroll);

  void _onWalletScroll() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_kickedOffRefresh) {
      _kickedOffRefresh = true;
      // ignore: discarded_futures
      _cache.refresh();
    }
  }

  @override
  void dispose() {
    _walletScroll.removeListener(_onWalletScroll);
    _walletScroll.dispose();
    _scroll.dispose();
    _cache.dispose();
    super.dispose();
  }

  Future<_CalData> _fetch() async {
    final scope = AppState.of(context);
    final events = await scope.api.events();
    events.sort((a, b) => a.round.compareTo(b.round));
    // Pull the backend's authoritative scores for the caller, then aggregate
    // per event round. Single round-trip; no per-session prediction fetches.
    await scope.predictions.refreshScores();
    final points = <int, int>{};
    for (final sid in scope.predictions.allScoreIds) {
      final s = scope.predictions.score(sid);
      if (s == null) continue;
      points.update(s.eventRound, (v) => v + s.pointsTotal,
          ifAbsent: () => s.pointsTotal);
    }
    // Souvenirs: one ticket per scored session. Fan out prediction fetches
    // in parallel — typical season has ~24 races × {quali, race} = ~48 round
    // trips, which beats waiting for each in series. Skip sessions whose
    // event/picks we can't reconstruct (missing from /events or no picks).
    final eventByRound = {for (final e in events) e.round: e};
    final scoreIds = scope.predictions.allScoreIds.toList();
    await Future.wait(scoreIds.map(scope.predictions.fetchPrediction));
    final souvenirs = <_Souvenir>[];
    for (final sid in scoreIds) {
      final s = scope.predictions.score(sid);
      if (s == null) continue;
      final ev = eventByRound[s.eventRound];
      if (ev == null) continue;
      final session = ev.sessions.firstWhere(
        (sess) => sess.id == sid,
        orElse: () => ev.sessions.first,
      );
      final pred = scope.predictions.prediction(sid);
      final picks = pred?.picks.map((p) => p.driverCode).toList() ?? const [];
      if (picks.isEmpty) continue;
      final correctSlots = <int>{
        for (final pp in s.breakdown.perPosition)
          if (pp.exact) pp.position - 1,
      };
      souvenirs.add(_Souvenir(
        event: ev,
        session: session,
        picks: picks,
        score: s.pointsTotal,
        sessionStart: s.sessionScheduledStart,
        correctSlots: correctSlots,
      ));
    }
    // Newest first so the wallet shows the latest souvenir on top.
    souvenirs.sort((a, b) => b.sessionStart.compareTo(a.sessionStart));
    return _CalData(
      events: events,
      pointsByRound: points,
      souvenirs: souvenirs,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        bottom: false,
        child: CachedView<_CalData>(
          cache: _cache,
          placeholder: _CalData.placeholder(),
          where: 'Calendar',
          builder: (_, data) {
            // Header + tabs are stable across both modes; the body underneath
            // switches based on [_tab].
            final header = Skeleton.keep(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    Spacing.xl, Spacing.lg, Spacing.xl, Spacing.xs),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Calendar'.toUpperCase(), style: AppText.display(28)),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: Spacing.md, vertical: 5),
                      decoration: BoxDecoration(
                        // Theme-aware stroke: white-ish on dark surfaces,
                        // black on light. Hardcoded `Colors.black` disappeared
                        // against the dark scaffold.
                        border: Border.all(
                            color: Theme.of(context).strokeColor, width: 1.5),
                        borderRadius:
                            const BorderRadius.all(Radius.circular(999)),
                      ),
                      child: Text('2026',
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                              color: Theme.of(context).colorScheme.onSurface)),
                    ),
                  ],
                ),
              ),
            );
            final tabs = Skeleton.keep(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    Spacing.xl, 0, Spacing.xl, Spacing.xs),
                child: Row(
                  children: [
                    _tabPill('schedule', 'SCHEDULE'),
                    const SizedBox(width: 6),
                    _tabPill('souvenirs', 'SOUVENIRS'),
                  ],
                ),
              ),
            );
            if (_tab == 'souvenirs') {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  header,
                  tabs,
                  Expanded(child: _buildSouvenirs(context, data)),
                ],
              );
            }
            final children = <Widget>[];
            final events = data.events;
            final now = DateTime.now();
            final phases = classifyCalendar(events, now);
            // Scroll target: the live event if there is one, otherwise the next
            // race — derived from the same classification the tiles render.
            int? liveRound;
            int? nextRound;
            phases.forEach((round, st) {
              if (st == RaceState.live) liveRound = round;
              if (st == RaceState.next) nextRound = round;
            });
            final scrollRound = liveRound ?? nextRound;

            // Bucket events by month so the layout builder can pair tiles
            // within each month on wide viewports (iPad → 2-up rows).
            final monthOrder = <String>[];
            final byMonth = <String, List<Widget>>{};
            for (final e in events) {
              final race = e.sessions.firstWhere(
                (s) => s.type == SessionType.race,
                orElse: () => e.sessions.first,
              );
              final month = DateFormat('MMMM').format(race.scheduledStart);
              if (!byMonth.containsKey(month)) {
                monthOrder.add(month);
                byMonth[month] = <Widget>[];
              }

              final raceState = phases[e.round] ?? RaceState.future;

              final pts = raceState == RaceState.past
                  ? (data.pointsByRound[e.round] ?? 0)
                  : null;

              byMonth[month]!.add(RaceTile(
                // Tag the next race's tile so the post-frame callback below
                // can scroll the list to it.
                key: e.round == scrollRound ? _nextRaceKey : null,
                round: e.round,
                event: e,
                flag: flagFor(e.country),
                country: '${e.country} · ${e.circuitName}',
                name: e.name.replaceAll('Grand Prix', 'GP'),
                when:
                    '${DateFormat('d MMM').format(e.sessions.first.scheduledStart)} – ${DateFormat('d MMM').format(race.scheduledStart)}',
                state: raceState,
                sprint: e.hasSprint,
                pointsScored: pts,
                distanceFromNow: raceState == RaceState.future
                    ? _humanDelta(race.scheduledStart)
                    : null,
                onTap: () => context.push('/race/${e.round}/${race.id}'),
              ));
            }

            Widget monthDivider(String month) => Padding(
                  padding: const EdgeInsets.fromLTRB(
                      Spacing.xl, Spacing.lg, Spacing.xl, Spacing.xs),
                  child: Row(children: [
                    Text(month.toUpperCase(), style: AppText.label(11)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Container(
                            height: 1, color: Colors.black.withOpacity(0.15))),
                  ]),
                );

            children.add(LayoutBuilder(
              builder: (ctx, constraints) {
                final twoCol = constraints.maxWidth >= 700;
                final items = <Widget>[];
                for (final month in monthOrder) {
                  items.add(monthDivider(month));
                  final tiles = byMonth[month]!;
                  if (!twoCol) {
                    for (final tile in tiles) {
                      items.add(Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: Spacing.lg, vertical: 5),
                        child: tile,
                      ));
                    }
                  } else {
                    for (var i = 0; i < tiles.length; i += 2) {
                      final left = tiles[i];
                      final right = i + 1 < tiles.length ? tiles[i + 1] : null;
                      items.add(Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: Spacing.lg, vertical: 5),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: left),
                            const SizedBox(width: Spacing.sm),
                            Expanded(
                              child: right ?? const SizedBox.shrink(),
                            ),
                          ],
                        ),
                      ));
                    }
                  }
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: items,
                );
              },
            ));
            children.add(const SizedBox(height: Spacing.xxl));
            // Auto-scroll to the "next" race on first build. Runs once per
            // mount; subsequent rebuilds (e.g. on scroll) skip the jump so
            // the user can scroll freely past it. Skipped while we're still
            // showing the placeholder data — would scroll to fake content.
            if (!_scrolledToNext &&
                scrollRound != null &&
                _cache.data != null) {
              _scrolledToNext = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                final ctx = _nextRaceKey.currentContext;
                if (ctx == null || !_scroll.hasClients) return;
                Scrollable.ensureVisible(
                  ctx,
                  // 0.1 puts the next-race tile just below the header
                  // instead of pinned to the very top of the viewport.
                  alignment: 0.1,
                  duration: const Duration(milliseconds: 350),
                );
              });
            }
            // Header + tabs stay pinned; only the months list scrolls. Keeps
            // the "CALENDAR · 2026" and the SCHEDULE/SOUVENIRS tabs anchored
            // while the user pages through the season.
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                tabs,
                Expanded(
                  child: SingleChildScrollView(
                    controller: _scroll,
                    child: Column(children: children),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _humanDelta(DateTime when) {
    final d = when.difference(DateTime.now()).inDays;
    return 'in ${d}d';
  }

  /// Compact pill toggle. Matches the standings_screen sub-tab look — filled
  /// when active, stroked-only when inactive.
  Widget _tabPill(String id, String label) {
    final t = Theme.of(context);
    final on = _tab == id;
    return GestureDetector(
      onTap: () => setState(() => _tab = id),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: 7),
        decoration: BoxDecoration(
          color: on ? t.colorScheme.onSurface : Colors.transparent,
          border: Border.all(color: t.strokeColor, width: 1.5),
          borderRadius: const BorderRadius.all(Radius.circular(8)),
        ),
        child: Text(
          label,
          style: AppText.label(
            10,
            color: on ? t.colorScheme.surface : t.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }

  /// Wallet-style stack of every souvenir the user has earned this season.
  /// Newest sits on top; older cards peek out below by [peek] px so the user
  /// can scan / tap into earlier weekends. Tickets navigate to the same race
  /// detail route as the home souvenir card.
  Widget _buildSouvenirs(BuildContext context, _CalData data) {
    final t = Theme.of(context);
    final souvenirs = data.souvenirs;
    if (souvenirs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xl),
          child: Text(
            'No souvenirs yet — your first scored\nsession will land here.',
            textAlign: TextAlign.center,
            style: AppText.body(
              13,
              color: t.colorScheme.onSurface.withOpacity(0.55),
            ),
          ),
        ),
      );
    }
    // Filter pills: ALL + one per scored event round, labelled with the
    // country flag emoji (falls back to a 3-char country code if no flag
    // mapping). Same pill style as the SCHEDULE/SOUVENIRS toggle above.
    final eventByRound = <int, Event>{};
    for (final s in souvenirs) {
      eventByRound.putIfAbsent(s.event.round, () => s.event);
    }
    final orderedRounds = eventByRound.keys.toList()..sort();
    final filtered = _walletFilterRound == null
        ? souvenirs
        : souvenirs
            .where((s) => s.event.round == _walletFilterRound)
            .toList();
    void selectRound(int? round) {
      setState(() => _walletFilterRound = round);
      if (_walletScroll.hasClients) _walletScroll.jumpTo(0);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(
                Spacing.xl, 0, Spacing.xl, Spacing.xs),
            children: [
              _filterPill(
                label: 'All',
                on: _walletFilterRound == null,
                onTap: () => selectRound(null),
              ),
              const SizedBox(width: 6),
              for (final round in orderedRounds) ...[
                _filterPill(
                  countryCode: _isoFromFlag(
                          flagFor(eventByRound[round]!.country)) ??
                      eventByRound[round]!.country.toUpperCase(),
                  on: _walletFilterRound == round,
                  onTap: () => selectRound(round),
                ),
                const SizedBox(width: 6),
              ],
            ],
          ),
        ),
        Expanded(child: _buildWalletStack(t, filtered)),
      ],
    );
  }

  /// Extracts the ISO 3166-1 alpha-2 country code from a regional-indicator
  /// flag emoji (e.g. 🇫🇷 → "FR"). Returns null for malformed input.
  String? _isoFromFlag(String? emoji) {
    if (emoji == null || emoji.isEmpty) return null;
    final runes = emoji.runes.toList();
    if (runes.length < 2) return null;
    const base = 0x1F1E6; // regional indicator A
    final a = runes[0] - base;
    final b = runes[1] - base;
    if (a < 0 || a > 25 || b < 0 || b > 25) return null;
    return String.fromCharCodes([65 + a, 65 + b]);
  }

  /// One filter pill. Pass [countryCode] (ISO 3166-1 alpha-2) to fill the
  /// chip with a flag; pass [label] alone for a text pill (used by "All").
  /// Selection state thickens the border and bumps opacity so the active
  /// filter reads across the strip.
  Widget _filterPill({
    String? label,
    String? countryCode,
    required bool on,
    required VoidCallback onTap,
  }) {
    final t = Theme.of(context);
    const w = 52.0;
    const h = 28.0;
    final border = Border.all(
      color: on ? t.colorScheme.onSurface : t.strokeColor,
      width: on ? 2.2 : 1.5,
    );
    const outerRadius = BorderRadius.all(Radius.circular(8));
    // Inner radius hugs *inside* the stroke so the flag doesn't peek past
    // the rounded border. Outer radius - border width = inner radius.
    const innerRadius = BorderRadius.all(Radius.circular(6));
    final hasFlag = countryCode != null;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Opacity(
        opacity: on || !hasFlag ? 1.0 : 0.6,
        child: Container(
          width: hasFlag ? w : null,
          height: h,
          alignment: Alignment.center,
          padding: hasFlag
              ? const EdgeInsets.all(1.5)
              : const EdgeInsets.symmetric(horizontal: Spacing.md),
          decoration: BoxDecoration(
            color: hasFlag
                ? null
                : (on ? t.colorScheme.onSurface : Colors.transparent),
            border: border,
            borderRadius: outerRadius,
          ),
          child: hasFlag
              ? ClipRRect(
                  borderRadius: innerRadius,
                  child: CountryFlag.fromCountryCode(
                    countryCode,
                    height: h,
                    width: w,
                  ),
                )
              : Text(
                  label ?? '',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                    height: 1.0,
                    color: on
                        ? t.colorScheme.surface
                        : t.colorScheme.onSurface,
                  ),
                ),
        ),
      ),
    );
  }

  /// The actual stack rendering — split out so [_buildSouvenirs] can compose
  /// the folder strip above it and pass in a filtered souvenir list.
  Widget _buildWalletStack(ThemeData t, List<_Souvenir> souvenirs) {
    if (souvenirs.isEmpty) {
      return Center(
        child: Text(
          'No souvenirs for this Grand Prix yet.',
          style: AppText.body(13,
              color: t.colorScheme.onSurface.withOpacity(0.55)),
        ),
      );
    }
    // Match the SouvenirTicket's actual rendered height at full phone width.
    // The previous 290 figure was guesswork that left the bottom of the
    // focused card overflowing into the next card's slot — fix by sizing
    // the math to reality. Each card is rendered inside a same-height
    // SizedBox so the scroll math stays in sync with what's on screen.
    const ticketHeight = 250.0;
    // How much of the next-newer card peeks below the focused one. ~110px
    // is enough to show the card's bottom edge + data-row preview (P1..P5
    // / POINTS), so each peek identifies the souvenir rather than just
    // hinting at it.
    const peek = 110.0;
    final n = souvenirs.length;
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final viewport = constraints.maxHeight;
        // Focused card sits with just a hair of padding above — enough to
        // keep it from kissing the folder strip but not so much that the
        // upper third is empty space.
        final topInset = viewport / 20;
        // One ticketHeight of scroll per card-transition. Floor at
        // n*ticketHeight + topInset so the last card can still reach the
        // focus slot even on short screens.
        final stackHeight = ((n - 1) * ticketHeight + viewport)
            .clamp(n * ticketHeight + topInset, 1e6);
        final offset = _walletScroll.hasClients ? _walletScroll.offset : 0.0;
        // Snap-derived focus index — the card currently at the focus slot.
        // Drives the tap-to-open vs. tap-to-focus behaviour below.
        final focusedIdx =
            (offset / ticketHeight).round().clamp(0, n - 1);

        double topFor(int i) {
          final effSlot = i - offset / ticketHeight;
          if (effSlot >= 0) {
            // Below or at the focus slot: peek-stacked. Add `offset` to
            // translate from viewport coords (peek * effSlot below topInset)
            // into stack coords.
            return i * peek + offset * (1 - peek / ticketHeight) + topInset;
          }
          // Above the focus slot: card moves UP at 2× the scroll rate so it
          // exits the viewport quickly and stacks just above the rendered
          // area. Continuous with the in-stack formula at effSlot = 0
          // (both give i*ticketHeight + topInset). Card stays mounted —
          // scrolling back re-pulls it smoothly into the focus slot.
          return topInset + 2 * i * ticketHeight - offset;
        }

        // Visually shrink peek cards by their effSlot distance from focus.
        // 5% per slot, floored at 0.82, so the second peek is ~90%, third
        // ~85%, etc. Focused (effSlot ≈ 0) and past cards stay at 1.0.
        double scaleFor(int i) {
          final eff = i - offset / ticketHeight;
          if (eff <= 0) return 1.0;
          return (1.0 - eff * 0.05).clamp(0.82, 1.0);
        }

        return SingleChildScrollView(
          controller: _walletScroll,
          padding:
              const EdgeInsets.fromLTRB(Spacing.lg, Spacing.sm, Spacing.lg, 0),
          physics: const _WalletSnapPhysics(
            itemHeight: ticketHeight,
            parent: ClampingScrollPhysics(),
          ),
          child: SizedBox(
            height: stackHeight.toDouble(),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Paint order:
                //   1. Future cards (effSlot >= 0) from far-peek up to the
                //      focused one (focused painted last among future).
                //   2. Past cards (effSlot < 0) painted AFTER focused →
                //      a card that's just slid off stays on top of the
                //      incoming focused card all the way until it's
                //      clipped by the viewport edge. Most recently
                //      slid-off (highest past index, closest to current
                //      focus) paints last so it's the topmost.
                //   Stable ValueKey lets Flutter reuse each SouvenirTicket
                //   across rebuilds — only the Positioned `top` changes.
                for (final i in [
                  for (var j = n - 1; j >= 0; j--)
                    if (j - offset / ticketHeight >= 0) j,
                  for (var j = 0; j < n; j++)
                    if (j - offset / ticketHeight < 0) j,
                ])
                  Positioned(
                    key: ValueKey(souvenirs[i].session.id),
                    top: topFor(i),
                    left: 0,
                    right: 0,
                    // No `height` — the slot shrink-wraps to the
                    // SouvenirTicket's intrinsic height so the hit area
                    // matches the visible card and taps below the painted
                    // ticket don't register as taps on it.
                    // Transform.scale shrinks peek cards visually (focused
                    // stays 1.0). Alignment.topCenter keeps the card's top
                    // edge pinned to topFor(i) so stack geometry stays
                    // predictable while the visible card shrinks downward.
                    child: Transform.scale(
                      scale: scaleFor(i),
                      alignment: Alignment.topCenter,
                      child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius:
                            const BorderRadius.all(Radius.circular(10)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.28),
                            blurRadius: 18,
                            spreadRadius: -2,
                            offset: const Offset(0, 10),
                          ),
                          BoxShadow(
                            color: Colors.black.withOpacity(0.12),
                            blurRadius: 6,
                            spreadRadius: 0,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      // Hard-clip the ticket to its rounded rect so nothing
                      // (edge serials past the corner, watermark bleed,
                      // next-card peeking) paints outside the visible card.
                      child: ClipRRect(
                        borderRadius:
                            const BorderRadius.all(Radius.circular(10)),
                        child: SouvenirTicket(
                          event: souvenirs[i].event,
                          driverCodes: souvenirs[i].picks,
                          scorePoints: souvenirs[i].score,
                          correctSlots: souvenirs[i].correctSlots,
                          sessionType: souvenirs[i].session.type,
                          circuitWatermark:
                              CircuitSvg(event: souvenirs[i].event),
                          // First tap on a peek scrolls the card into the
                          // focus slot. Tap again once focused to navigate
                          // — gives the user a chance to inspect the
                          // souvenir before committing to opening it.
                          onTap: i == focusedIdx
                              ? () => context.push(
                                  '/race/${souvenirs[i].event.round}/${souvenirs[i].session.id}',
                                )
                              : () => _walletScroll.animateTo(
                                    i * ticketHeight,
                                    duration:
                                        const Duration(milliseconds: 360),
                                    curve: Curves.easeOutCubic,
                                  ),
                        ),
                      ),
                    ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CalData {
  final List<Event> events;
  final Map<int, int> pointsByRound;
  final List<_Souvenir> souvenirs;
  _CalData({
    required this.events,
    required this.pointsByRound,
    this.souvenirs = const [],
  });

  /// Synthetic 8-race calendar across the next few months — enough rows to
  /// fill the scrollview with skeleton tiles. Real values get replaced once
  /// [AsyncCache] hands us the live payload.
  factory _CalData.placeholder() {
    final now = DateTime.now();
    final events = <Event>[];
    for (var i = 0; i < 8; i++) {
      final start =
          DateTime(now.year, now.month + i ~/ 2, 1 + (i % 2) * 14, 14);
      events.add(Event(
        round: i + 1,
        name: 'Loading Grand Prix',
        country: 'XX',
        circuitName: 'Loading Circuit',
        hasSprint: i.isEven,
        sessions: [
          Session(
            id: i * 5,
            type: SessionType.race,
            scheduledStart: start.add(const Duration(days: 2)),
            scheduledEnd: start.add(const Duration(days: 2, hours: 2)),
            status: SessionStatus.scheduled,
          ),
          Session(
            id: i * 5 + 1,
            type: SessionType.qualifying,
            scheduledStart: start.add(const Duration(days: 1)),
            scheduledEnd: start.add(const Duration(days: 1, hours: 1)),
            status: SessionStatus.scheduled,
          ),
        ],
      ));
    }
    return _CalData(events: events, pointsByRound: const {});
  }
}

/// One scored session's worth of data: enough to render a [SouvenirTicket]
/// without re-fetching. Sorted newest-first by [sessionStart] before being
/// handed to the wallet view.
class _Souvenir {
  final Event event;
  final Session session;
  final List<String> picks;
  final int score;
  final DateTime sessionStart;
  /// 0-based pick slot indices that were exact-correct. Source: the score
  /// breakdown's `perPosition[i].exact` (the backend already knows which
  /// slots hit) — no extra fetch needed.
  final Set<int> correctSlots;
  _Souvenir({
    required this.event,
    required this.session,
    required this.picks,
    required this.score,
    required this.sessionStart,
    required this.correctSlots,
  });
}

/// ScrollPhysics that snaps to integer multiples of [itemHeight] on release.
/// Used by the souvenir wallet so a half-flicked drag locks into one focused
/// card instead of leaving the stack mid-transition between two.
///
/// Snap target factors in fling velocity (~0.15s of inertia) so a hard
/// swipe travels one card further than a slow drag. The spring used by the
/// ballistic simulation is **critically damped + stiff** — earlier attempts
/// used an underdamped spring (damping ≪ 2·√(mass·stiffness)) which
/// oscillated near the target and produced the visible wiggle / "infinite
/// loop between two states" the user reported. Critical damping plus a
/// generous tolerance for the early-return kills both.
class _WalletSnapPhysics extends ScrollPhysics {
  final double itemHeight;
  const _WalletSnapPhysics({required this.itemHeight, super.parent});

  @override
  _WalletSnapPhysics applyTo(ScrollPhysics? ancestor) =>
      _WalletSnapPhysics(itemHeight: itemHeight, parent: buildParent(ancestor));

  double _snapTarget(ScrollMetrics position, double velocity) {
    final projected = position.pixels + velocity * 0.15;
    final idx = (projected / itemHeight).round();
    final pixels = idx * itemHeight;
    return pixels.clamp(position.minScrollExtent, position.maxScrollExtent);
  }

  @override
  Simulation? createBallisticSimulation(
      ScrollMetrics position, double velocity) {
    final target = _snapTarget(position, velocity);
    // Already settled at a snap point with no real fling — let the scroll
    // stop without a sim. Tolerances are deliberately wider than the
    // default toleranceFor() so float-precision residue (sub-pixel deltas)
    // can't retrigger the spring and visibly twitch the cards.
    if ((target - position.pixels).abs() < 1.0 && velocity.abs() < 10) {
      return null;
    }
    // Critically-damped spring → fast, decisive snap with no overshoot,
    // no oscillation. Stiffness 300 settles in ~200ms; ratio 1.0 means
    // exactly critical damping. ScrollSpringSimulation respects the
    // velocity already in the system so a hard fling still feels weighty.
    return ScrollSpringSimulation(
      SpringDescription.withDampingRatio(
        mass: 1.0,
        stiffness: 300,
        ratio: 1.0,
      ),
      position.pixels,
      target,
      velocity,
      tolerance: const Tolerance(distance: 0.5, velocity: 0.5),
    );
  }

  @override
  bool get allowImplicitScrolling => false;
}

