// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:skeletonizer/skeletonizer.dart';
import '../api/api_client.dart';
import '../api/models/event.dart';
import '../api/models/pick.dart';
import '../api/models/session.dart';
import '../api/models/session_result.dart';
import '../api/models/reference_laps.dart';
import '../components/app_card.dart';
import '../components/branded_sheet.dart';
import '../components/branded_toast.dart';
import '../components/driver_sector_row.dart';
import '../components/error_view.dart';
import '../components/slot.dart';
import '../domain/prediction.dart';
import '../nav/nav_guard.dart';
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
  // Snapshot of picks as last saved to the server. Used to detect dirty
  // state for the discard-confirmation dialog.
  List<String> _initialPicks = const [];
  // Local UI state: when false the slots are read-only and the top row shows
  // an EDIT pill that flips this back to true. Independent from the server's
  // system-lock flag (deadline-based).
  bool _editing = true;
  bool _saving = false;
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
      // Targeted mode: find the requested session across all events,
      // regardless of time or status. Future sessions are pickable;
      // past/locked ones open read-only (the prev/next nav steps into them so
      // the user can review what they locked in). If the id matches nothing,
      // we fall through to auto-find so the screen doesn't sit broken.
      for (final e in events) {
        for (final s in e.sessions) {
          if (s.id == targetId && _isScorable(s.type)) {
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
    _initialPicks = List<String>.from(_picks);
    // Start in edit mode only when the session is still open AND nothing's
    // saved yet. Past the deadline the screen is permanently read-only; with
    // saved picks it opens read-only and the EDIT button is the way back in.
    final deadlinePassed = !session.scheduledStart.isAfter(now);
    _editing = !deadlinePassed && _initialPicks.isEmpty;
    // Prefer a same-weekend finished session that's chronologically right
    // before the one being predicted (FP3>FP2>FP1 → quali/sprintQ; Q>SQ →
    // race/sprint). Falls back to the season-wide most recent finished
    // session when nothing this weekend has run yet — keeps the driver
    // grid populated for the first session of the year (pre-FP1) where no
    // weekend reference exists, just without timing annotations.
    Session? referenceSession = _pickReferenceSession(upcoming, session.type);
    if (referenceSession == null) {
      final finishedSeason = events
          .expand((e) => e.sessions)
          .where((s) => s.status == SessionStatus.finished)
          .toList()
        ..sort((a, b) => b.scheduledStart.compareTo(a.scheduledStart));
      if (finishedSeason.isNotEmpty) referenceSession = finishedSeason.first;
    }
    List<SessionResult> lineup = const [];
    if (referenceSession != null) {
      try {
        lineup = await scope.api.sessionResults(referenceSession.id);
      } on NotFoundException {
        lineup = const [];
      }
    }
    final sorted = [...lineup]
      ..sort((a, b) => a.position.compareTo(b.position));
    // Only annotate tiles with times when the reference is a same-weekend
    // session. Cross-event fallback ordering is useful, but its "Q3" or
    // "race time" would mean something different from session to session.
    final weekendRef = referenceSession != null &&
            upcoming.sessions.any((s) => s.id == referenceSession!.id)
        ? referenceSession
        : null;
    final referenceTimes = <String, String>{};
    if (weekendRef != null) {
      for (final r in sorted) {
        final t = _referenceTimeFor(r, weekendRef.type);
        if (t != null && t.isNotEmpty) referenceTimes[r.driverCode] = t;
      }
    }
    // Sector reference data — backed by OpenF1 /laps via the new endpoint.
    // Best-effort: empty references just hide the per-driver dot rows, the
    // screen still works.
    ReferenceLapsResponse? refLaps;
    try {
      refLaps = await scope.api.sessionReferenceLaps(session.id);
    } catch (_) {
      refLaps = null;
    }
    // WDC standings — used as the fallback sort when no reference laps exist
    // yet (pre-FP1). Best-effort: failure just falls back to alphabetical.
    Map<String, int> standingsOrder = const {};
    try {
      final st = await scope.api.driverStandings();
      standingsOrder = {for (final s in st) s.driverCode: s.position};
    } catch (_) {
      standingsOrder = const {};
    }
    // Recent-form guide: each driver's finishing position in the last 3
    // finished races (newest first). Only fetched in the no-timing-data state
    // (no same-weekend reference + no sector laps) — that's where the rows
    // would otherwise be empty. Best-effort: any failed race just contributes
    // nothing.
    final recentFinishes = <String, List<int>>{};
    final noTimingData =
        weekendRef == null && (refLaps == null || refLaps.references.isEmpty);
    if (noTimingData) {
      final recentRaces = events
          .expand((e) => e.sessions)
          .where((s) =>
              s.type == SessionType.race &&
              s.status == SessionStatus.finished)
          .toList()
        ..sort((a, b) => b.scheduledStart.compareTo(a.scheduledStart));
      final last3 = recentRaces.take(3).toList();
      final perRace = await Future.wait(last3.map((s) async {
        try {
          return await scope.api.sessionResults(s.id);
        } catch (_) {
          return const <SessionResult>[];
        }
      }));
      // perRace[0] is the most recent race, so iterating in order keeps each
      // driver's list newest-first.
      for (final results in perRace) {
        for (final r in results) {
          (recentFinishes[r.driverCode] ??= <int>[]).add(r.position);
        }
      }
    }
    // Build the chronological nav list of every scorable session in the
    // season — past, locked and upcoming. The prev/next chevrons walk this
    // full list so the user can step backward into already-locked sessions
    // (read-only) as well as forward into pickable ones.
    final chronological = <_NavRef>[];
    for (final e in events) {
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
      referenceSession: weekendRef,
      referenceTimes: referenceTimes,
      referenceLaps: refLaps,
      standingsOrder: standingsOrder,
      recentFinishes: recentFinishes,
    );
  }

  @override
  void initState() {
    super.initState();
    // Wire the bottom-nav guard: tapping HOME/CALENDAR/STANDINGS while
    // there are unsaved edits triggers the same discard confirmation as the
    // back gesture (which is handled by PopScope below).
    NavGuard.instance.canLeave = () async {
      if (!_isDirty()) return true;
      return await _confirmDiscard();
    };
  }

  @override
  void dispose() {
    NavGuard.instance.canLeave = null;
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _data ??= _load();
  }

  bool _isDirty() {
    if (_picks.length != _initialPicks.length) return true;
    for (var i = 0; i < _picks.length; i++) {
      if (_picks[i] != _initialPicks[i]) return true;
    }
    return false;
  }

  Future<bool> _confirmDiscard() async {
    return BrandedSheet.confirm(
      context,
      title: 'Discard changes?',
      message: "You have unsaved edits — they'll be lost if you leave.",
      primaryLabel: 'Discard',
      secondaryLabel: 'Keep editing',
    );
  }

  Future<void> _navigateTo(_NavRef target) async {
    if (_isDirty() && !await _confirmDiscard()) return;
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
        BrandedToast.show(context, 'Pick already locked', tone: ToastTone.error);
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
      if (!mounted) return;
      setState(() {
        _initialPicks = List<String>.from(_picks);
        _editing = false;
      });
      BrandedToast.show(context, 'Pick saved', tone: ToastTone.ok);
    } on ConflictException catch (e) {
      if (mounted) BrandedToast.show(context, e.message, tone: ToastTone.error);
    } on ValidationException catch (e) {
      if (mounted) BrandedToast.show(context, e.message, tone: ToastTone.error);
    } catch (_) {
      if (mounted) BrandedToast.show(context, "Couldn't save", tone: ToastTone.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return PopScope(
      canPop: !_isDirty(),
      onPopInvoked: (didPop) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _confirmDiscard() && mounted) {
          nav.pop();
        }
      },
      child: Scaffold(
        backgroundColor: t.colorScheme.surface,
        body: SafeArea(
          bottom: false,
          child: FutureBuilder<_PredictData>(
            future: _data,
            builder: (_, snap) {
            if (snap.connectionState != ConnectionState.done) {
              // Render a static skeleton of the predict layout instead of a
              // spinner. Doesn't mirror the real screen exactly (which depends
              // on session type / picks state) but gives the user a sense of
              // what's coming.
              return const _PredictSkeleton();
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
            final systemLocked = scope.predictions.prediction(session.id)?.isLocked ?? false;
            // A session is locked once the backend flags it OR its deadline
            // (scheduled start) has passed — the latter covers past sessions
            // reached via the prev nav, which the server may not have flagged
            // but are no longer pickable.
            final deadlinePassed = !session.scheduledStart.isAfter(DateTime.now());
            final locked = systemLocked || deadlinePassed;
            final hasSaved = _initialPicks.isNotEmpty;
            final canEdit = _editing && !locked;
            // Partial / empty pick lists are now savable — the backend accepts
            // 0..req picks, so the lock button stays enabled whenever the user
            // is editing an unlocked session, regardless of how many slots
            // they've filled.
            final canLock = !locked && !_saving;
            // Single full-width control that merges the primary action with
            // the lock countdown, styled like the slot/driver cards (rLg
            // radius, card stroke). The old two-pill row collapses into this:
            //   editing → accent "LOCK PICK" + countdown, taps to lock
            //   saved   → outlined "EDIT" + countdown, taps back into edit
            //   locked  → dimmed "LOCKED" status, non-interactive
            final String countdown = _lockLabel(session.scheduledStart);
            final Widget actionBar;
            if (_editing) {
              actionBar = _ActionBar(
                icon: Icons.lock,
                label: _saving ? 'SAVING…' : 'LOCK PICK',
                countdown: countdown,
                accent: true,
                onTap: canLock ? _lock : null,
              );
            } else if (hasSaved && !locked) {
              actionBar = _ActionBar(
                icon: Icons.edit,
                label: 'EDIT',
                countdown: countdown,
                accent: false,
                onTap: () => setState(() => _editing = true),
              );
            } else {
              actionBar = _ActionBar(
                icon: Icons.lock,
                label: 'LOCKED',
                // Drop the redundant trailing "LOCKED" countdown; keep a real
                // remaining-time readout if the system locked before deadline.
                countdown: countdown == 'LOCKED' ? null : countdown,
                accent: false,
                onTap: null,
              );
            }
            return ListView(
                padding: const EdgeInsets.only(bottom: Spacing.xxl + Spacing.xxl),
                children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(Spacing.xl, Spacing.lg, Spacing.lg, Spacing.sm),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(event.name, style: AppText.display(22)),
                      ),
                      // Prev / next session nav grouped together on the right.
                      IconButton(
                        onPressed: d.prev == null ? null : () => _navigateTo(d.prev!),
                        icon: const Icon(Icons.chevron_left, size: 22),
                        tooltip: 'Previous session',
                        visualDensity: VisualDensity.compact,
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
                  padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.sm),
                  child: actionBar,
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
                          emptyLabel: canEdit ? 'Tap a driver below' : 'No pick',
                          onClear: filled && canEdit
                              ? () => setState(() => _picks.removeAt(i))
                              : null,
                        ),
                      );
                    }),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.lg, Spacing.lg, Spacing.sm),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text('DRIVERS', style: AppText.label(11, color: t.colorScheme.onSurface.withOpacity(0.6))),
                      const Spacer(),
                      if (d.referenceLaps != null && d.referenceLaps!.references.isNotEmpty)
                        _SectorLegend(t: t)
                      else if (d.referenceSession != null && d.event != null)
                        _ReferenceSourceChip(
                          referenceSession: d.referenceSession!,
                          eventRound: d.event!.round,
                        )
                      // No timing data and no form guide — the BEST column
                      // shows WDC standing, so label it here. (With a form
                      // guide the per-column header labels both instead.)
                      else if (d.recentFinishes.isEmpty &&
                          d.standingsOrder.isNotEmpty)
                        Text('WDC STANDING',
                            style: AppText.label(10,
                                color: t.colorScheme.onSurface.withOpacity(0.5))),
                    ],
                  ),
                ),
                _SectorReferenceList(
                  data: d,
                  picks: _picks,
                  canEdit: canEdit,
                  onToggle: _toggleDriver,
                ),
              ],
              );
          },
          ),
        ),
      ),
    );
  }

  String _lockLabel(DateTime when) {
    final diff = when.difference(DateTime.now());
    if (diff.isNegative) return 'LOCKED';
    // Break out days so a far-future lock reads as "12d 21h 50m" instead of
    // "309h 50m" — which is technically correct but hard to scan. Days only
    // shown when ≥1d so a same-day lock stays compact ("3h 12m").
    final days = diff.inDays;
    final hours = diff.inHours.remainder(24);
    final mins = diff.inMinutes.remainder(60);
    if (days > 0) return 'LOCKS IN ${days}d ${hours}h ${mins}m';
    return 'LOCKS IN ${hours}h ${mins}m';
  }
}

/// Full-width status/action bar merging the primary action with the lock
/// countdown into a single control styled like the slot + driver cards
/// (rLg radius, card stroke, full width). Accent variant (filled red, white
/// text) carries LOCK PICK; outlined variant carries EDIT / LOCKED. A null
/// [onTap] is non-interactive — accent renders dimmed (picks not lockable /
/// saving), outlined renders dimmed (system-locked status). [countdown] is
/// hidden when null so a pure "LOCKED" status doesn't read it twice.
class _ActionBar extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? countdown;
  final bool accent;
  final VoidCallback? onTap;
  const _ActionBar({
    required this.icon,
    required this.label,
    required this.countdown,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final disabled = onTap == null;
    final bg = accent
        ? (disabled ? BrandColors.accent.withOpacity(0.35) : BrandColors.accent)
        : t.colorScheme.surface;
    final fg = accent
        ? Colors.white
        : t.colorScheme.onSurface.withOpacity(disabled ? 0.5 : 1.0);
    final clock = accent ? Colors.white : BrandColors.accent;
    return Material(
      color: bg,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: accent ? Colors.transparent : t.strokeColor,
          width: Strokes.card,
        ),
        borderRadius: Radii.rLg,
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: Spacing.md, vertical: Spacing.md),
          child: Row(
            children: [
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: Spacing.sm),
              Text(label, style: AppText.label(12, color: fg)),
              if (countdown != null) ...[
                const Spacer(),
                FaIcon(FontAwesomeIcons.clock, size: 11, color: clock),
                const SizedBox(width: 5),
                Text(countdown!, style: AppText.label(11, color: clock)),
              ],
            ],
          ),
        ),
      ),
    );
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
  /// The finished session whose classification ordered [drivers] and whose
  /// times appear under each driver tile. Same-weekend when possible:
  /// FP3>FP2>FP1 when predicting quali/sprint-quali, Q>SQ when predicting
  /// race/sprint. Null when no relevant session has run yet (e.g. season
  /// opener pre-FP1) — drivers then come from the most recent finished
  /// session season-wide and tiles render without times.
  final Session? referenceSession;
  /// driverCode → formatted lap-time string for the reference session
  /// (e.g. "1:18.234" for an FP best lap, "1:17.234 (Q1)" for a quali driver
  /// knocked out in Q1). Empty when no useful timing exists.
  final Map<String, String> referenceTimes;
  /// Per-driver best laps with sector tiers across up to 3 reference sessions
  /// of the same event. Null when the new endpoint isn't reachable or no
  /// reference sessions have run yet — list falls back to the legacy
  /// grid+lap-time view.
  final ReferenceLapsResponse? referenceLaps;
  /// driverCode → WDC position. Used to sort the driver list when no
  /// reference laps are available yet (pre-FP1 of the season opener etc).
  /// Empty when the standings endpoint fails or hasn't been called.
  final Map<String, int> standingsOrder;
  /// driverCode → finishing positions in the last up-to-3 finished races,
  /// newest first. Only populated in the no-timing-data state, where it backs
  /// the per-row form guide. Empty otherwise.
  final Map<String, List<int>> recentFinishes;
  _PredictData({
    required this.event,
    required this.session,
    required this.drivers,
    required this.prev,
    required this.next,
    this.referenceSession,
    this.referenceTimes = const {},
    this.referenceLaps,
    this.standingsOrder = const {},
    this.recentFinishes = const {},
  });
}

/// Compact accent-bordered chip that names the reference session whose
/// classification drives the driver order + tile lap times. Tapping it
/// pushes to the full results for that session so the user can scan the
/// rest of the field. Mirrors the LOCKS-IN pill styling.
class _ReferenceSourceChip extends StatelessWidget {
  final Session referenceSession;
  final int eventRound;
  const _ReferenceSourceChip({required this.referenceSession, required this.eventRound});

  static const _typeLabel = {
    SessionType.fp1: 'FP1',
    SessionType.fp2: 'FP2',
    SessionType.fp3: 'FP3',
    SessionType.qualifying: 'QUALI',
    SessionType.sprint_quali: 'SQ',
    SessionType.sprint: 'SPRINT',
    SessionType.race: 'RACE',
  };
  static const _weekday = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    final label = '${_typeLabel[referenceSession.type] ?? referenceSession.type.name.toUpperCase()}'
        ' (${_weekday[referenceSession.scheduledStart.weekday - 1]})';
    return InkWell(
      onTap: () => context.push('/race/$eventRound/${referenceSession.id}'),
      borderRadius: const BorderRadius.all(Radius.circular(999)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: BrandColors.accent, width: 1.5),
          borderRadius: const BorderRadius.all(Radius.circular(999)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('TIMES · $label', style: AppText.label(10, color: BrandColors.accent)),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, size: 12, color: BrandColors.accent),
        ]),
      ),
    );
  }
}

/// Order to walk same-weekend finished sessions for the reference, given
/// which session we're predicting. Race and sprint reference quali; quali
/// and sprint-quali reference the latest available practice.
const Map<SessionType, List<SessionType>> _referenceOrder = {
  SessionType.qualifying: [SessionType.fp3, SessionType.fp2, SessionType.fp1],
  SessionType.sprint_quali: [SessionType.fp3, SessionType.fp2, SessionType.fp1],
  SessionType.race: [SessionType.qualifying, SessionType.sprint_quali],
  SessionType.sprint: [SessionType.sprint_quali, SessionType.qualifying],
};

/// Championship-position label for the BEST column when a driver has no lap
/// time on this screen yet (pre-FP1 of a weekend). Null → renders as '—'.
String? _wdcLabel(int? position) => position == null ? null : 'P$position';

Session? _pickReferenceSession(Event event, SessionType predicting) {
  final order = _referenceOrder[predicting];
  if (order == null) return null;
  for (final t in order) {
    for (final s in event.sessions) {
      if (s.type == t && s.status == SessionStatus.finished) return s;
    }
  }
  return null;
}

/// Per-driver display time for a reference session.
///
/// - Quali / sprint-quali: best non-null of q3/q2/q1; "(Q1)" / "(Q2)" suffix
///   when the best time is from an earlier knockout (driver eliminated then).
/// - FP1/FP2/FP3: OpenF1's session_result returns the best lap as
///   duration[0], which our parser maps into q1 — read q1 unannotated.
/// - Race / sprint reference (theoretical): raceTime, unannotated.
String? _referenceTimeFor(SessionResult r, SessionType refType) {
  switch (refType) {
    case SessionType.qualifying:
    case SessionType.sprint_quali:
      if (r.q3 != null) return r.q3;
      if (r.q2 != null) return '${r.q2} (Q2)';
      if (r.q1 != null) return '${r.q1} (Q1)';
      return null;
    case SessionType.fp1:
    case SessionType.fp2:
    case SessionType.fp3:
      return r.q1;
    case SessionType.race:
    case SessionType.sprint:
      return r.raceTime;
  }
}

/// Layout-stable skeleton shown while the predict screen is fetching the
/// session + drivers list. Renders a few placeholder cards under a
/// Skeletonizer so the user gets a sense of the upcoming structure instead
/// of a spinner.
class _PredictSkeleton extends StatelessWidget {
  const _PredictSkeleton();

  @override
  Widget build(BuildContext context) {
    return Skeletonizer(
      child: ListView(
        padding: const EdgeInsets.only(bottom: Spacing.xxl + Spacing.xxl),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Spacing.xl, Spacing.lg, Spacing.lg, Spacing.sm),
            child: Text('Loading Grand Prix', style: AppText.display(22)),
          ),
          // 5 pick slots — generous enough to cover race (5), sprint (3),
          // quali (2), sprint-quali (1). Extra rows in the smaller cases
          // just become extra skeleton rows; not a layout problem.
          for (var i = 0; i < 5; i++)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: 4),
              child: SizedBox(
                height: 56,
                child: AppCard(
                  child: SizedBox.expand(),
                ),
              ),
            ),
          const SizedBox(height: Spacing.lg),
          Padding(
            padding: const EdgeInsets.fromLTRB(Spacing.xl, 0, Spacing.xl, Spacing.sm),
            child: Text('DRIVERS', style: AppText.label(11)),
          ),
          // Driver tiles — 6 placeholder rows.
          for (var i = 0; i < 6; i++)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: 3),
              child: SizedBox(
                height: 56,
                child: AppCard(
                  child: SizedBox.expand(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Column-header strip above the sector-row list. Names the up-to-3 reference
/// sessions (FP1/FP2/FP3 or Q1/Q2/Q3 etc) and the BEST + star columns. Sits
/// inset to align with the row internals (skip past team stripe + code col).
class _SectorReferenceHeader extends StatelessWidget {
  final ReferenceLapsResponse refs;
  const _SectorReferenceHeader({required this.refs});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = AppText.label(8, color: t.colorScheme.onSurface.withOpacity(0.55));
    return Padding(
      padding: const EdgeInsets.only(left: 78, right: Spacing.md, bottom: Spacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final r in refs.references) Text(r.label, style: muted),
              ],
            ),
          ),
          SizedBox(width: 60, child: Text('BEST', style: muted, textAlign: TextAlign.right)),
        ],
      ),
    );
  }
}

/// Column header for the no-timing-data fallback: labels the recent-form
/// chips strip and the WDC-standing column. Mirrors [_SectorReferenceHeader]'s
/// inset so the labels line up with the row internals.
class _FormHeader extends StatelessWidget {
  const _FormHeader();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = AppText.label(8, color: t.colorScheme.onSurface.withOpacity(0.55));
    return Padding(
      padding: const EdgeInsets.only(left: 78, right: Spacing.md, bottom: Spacing.xs),
      child: Row(
        children: [
          Expanded(child: Center(child: Text('LAST 3 RACES', style: muted))),
          SizedBox(width: 64, child: Text('WDC', style: muted, textAlign: TextAlign.right)),
        ],
      ),
    );
  }
}

/// Reference list: one row per driver who's not currently picked. Sorted by
/// fastest lap across the available reference sessions (drivers with no lap
/// fall to the bottom).
class _SectorReferenceList extends StatelessWidget {
  final _PredictData data;
  final List<String> picks;
  final bool canEdit;
  final ValueChanged<String> onToggle;
  const _SectorReferenceList({
    required this.data,
    required this.picks,
    required this.canEdit,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final refs = data.referenceLaps;
    final hasRefs = refs != null && refs.references.isNotEmpty;
    final byDriver = hasRefs ? refs.byDriver : const <String, List<ReferenceLap?>>{};
    final byCode = {for (final r in data.drivers) r.driverCode: r};

    // Build sortable rows for every driver in either the driver list or the
    // reference data — the reference set is the truth source for who ran on
    // track this weekend; the SessionResult lookup gives us team color.
    final allCodes = <String>{...byCode.keys, ...byDriver.keys};
    final rows = <_DriverSectorRowModel>[];
    for (final code in allCodes) {
      final laps = byDriver[code] ??
          (hasRefs
              ? List<ReferenceLap?>.filled(refs.references.length, null)
              : const <ReferenceLap?>[]);
      ReferenceLap? best;
      for (final l in laps) {
        if (l == null) continue;
        if (best == null || l.lapMs < best.lapMs) best = l;
      }
      final sr = byCode[code];
      // Constructor lookup falls back to the reference-laps payload when the
      // driver wasn't classified in the lineup (DNF, reserve drivers — e.g.
      // VER didn't finish Monaco, Lindblad doesn't race the GP at all). The
      // /reference-laps endpoint reads constructorId from the practice/quali
      // session_result rows, which always have a team for every driver who
      // turned a wheel that weekend.
      String? constructorId = sr?.constructorId;
      for (final l in laps) {
        if (l == null) continue;
        constructorId ??= l.constructorId;
        if (constructorId != null) break;
      }
      final pickIdx = picks.indexOf(code);
      rows.add(_DriverSectorRowModel(
        driverCode: code,
        constructorId: constructorId,
        teamColorHex: sr?.teamColour,
        laps: laps,
        bestLapMs: best?.lapMs,
        pickedSlot: pickIdx == -1 ? null : pickIdx + 1,
      ));
    }
    // With sector refs: fastest first, no-laps last (alphabetical tiebreaker).
    // Without refs: sort by current WDC position; drivers not in the
    // standings sink to the bottom (alphabetical among themselves).
    rows.sort((a, b) {
      if (!hasRefs) {
        final pa = data.standingsOrder[a.driverCode];
        final pb = data.standingsOrder[b.driverCode];
        if (pa == null && pb == null) return a.driverCode.compareTo(b.driverCode);
        if (pa == null) return 1;
        if (pb == null) return -1;
        return pa.compareTo(pb);
      }
      if (a.bestLapMs == null && b.bestLapMs == null) return a.driverCode.compareTo(b.driverCode);
      if (a.bestLapMs == null) return 1;
      if (b.bestLapMs == null) return -1;
      return a.bestLapMs!.compareTo(b.bestLapMs!);
    });

    // Show the recent-form guide only in the no-timing-data state, where the
    // backend supplied last-3-race finishes and the rows are otherwise bare.
    final showForm = !hasRefs && data.recentFinishes.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
      child: Column(
        children: [
          if (hasRefs)
            _SectorReferenceHeader(refs: refs)
          else if (showForm)
            const _FormHeader(),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.xs),
              child: DriverSectorRow(
                driverCode: r.driverCode,
                constructorId: r.constructorId,
                teamColorHex: r.teamColorHex,
                referenceLaps: r.laps,
                pickedSlot: r.pickedSlot,
                // No sector data: prefer a weekend lap time, else fall back to
                // the driver's WDC standing so the column carries meaning
                // instead of a column of dashes (pre-FP1 of a weekend).
                bestLapOverride: hasRefs
                    ? null
                    : (data.referenceTimes[r.driverCode] ??
                        _wdcLabel(data.standingsOrder[r.driverCode])),
                recentFinishes: showForm ? data.recentFinishes[r.driverCode] : null,
                onTap: canEdit ? () => onToggle(r.driverCode) : null,
              ),
            ),
        ],
      ),
    );
  }
}

class _DriverSectorRowModel {
  final String driverCode;
  final String? constructorId;
  final String? teamColorHex;
  final List<ReferenceLap?> laps;
  final int? bestLapMs;
  final int? pickedSlot;
  _DriverSectorRowModel({
    required this.driverCode,
    required this.constructorId,
    required this.teamColorHex,
    required this.laps,
    required this.bestLapMs,
    required this.pickedSlot,
  });
}

/// Tiny legend pill explaining the dot colors. Sits where the "TIMES · FP2"
/// chip used to live so the header strip stays informative without spelling
/// it out per-row.
class _SectorLegend extends StatelessWidget {
  final ThemeData t;
  const _SectorLegend({required this.t});

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _LegendDot(color: BrandColors.violet, label: 'BEST'),
        SizedBox(width: Spacing.sm),
        _LegendDot(color: BrandColors.ok, label: 'PB'),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 3),
        Text(label,
            style: AppText.label(9, color: t.colorScheme.onSurface.withOpacity(0.6))),
      ],
    );
  }
}
