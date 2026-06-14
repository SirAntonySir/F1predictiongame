// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../api/models/event.dart';
import '../api/models/league_member.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/country_flags.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// Global search across the data the app already has loaded: races on the
/// season calendar, and players in the active league. Drives off the home
/// cache (events) + the league controller (members) — no extra API calls,
/// no debounce needed.
///
/// Reach it from the home topbar's search icon.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _q = TextEditingController();
  final FocusNode _focus = FocusNode();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _q.addListener(() {
      final v = _q.text.trim();
      if (v != _query) setState(() => _query = v);
    });
    // Auto-focus so the user can start typing immediately on push.
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _q.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final scope = AppState.of(context);
    final events = scope.homeCache.data?.events ?? const <Event>[];
    final league = scope.league.league;
    final members = league?.members ?? const <LeagueMember>[];
    final lc = _query.toLowerCase();
    final matchedEvents = lc.isEmpty
        ? const <Event>[]
        : events.where((e) {
            return e.name.toLowerCase().contains(lc) ||
                e.country.toLowerCase().contains(lc) ||
                e.circuitName.toLowerCase().contains(lc) ||
                'round ${e.round}'.startsWith(lc) ||
                'r${e.round}'.startsWith(lc);
          }).take(8).toList();
    final matchedPlayers = lc.isEmpty
        ? const <LeagueMember>[]
        : members
            .where((m) => m.displayName.toLowerCase().contains(lc))
            .take(8)
            .toList();
    final hasResults = matchedEvents.isNotEmpty || matchedPlayers.isNotEmpty;

    return Scaffold(
      backgroundColor: t.colorScheme.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Spacing.sm, Spacing.lg, Spacing.lg, Spacing.sm),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () =>
                        context.canPop() ? context.pop() : context.go('/home'),
                    icon: const Icon(Icons.arrow_back_ios_new, size: 16),
                  ),
                  Expanded(
                    child: Text(
                      'SEARCH',
                      style: AppText.display(22),
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Spacing.lg, 0, Spacing.lg, Spacing.md),
              child: _SearchField(
                controller: _q,
                focusNode: _focus,
                onClear: _q.text.isEmpty ? null : () => _q.clear(),
              ),
            ),
            Expanded(
              child: _query.isEmpty
                  ? const _Hint(text: 'Search races and players in your league.')
                  : !hasResults
                      ? _Hint(text: 'No matches for "$_query".')
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(Spacing.lg,
                              Spacing.xs, Spacing.lg, Spacing.xxl),
                          children: [
                            if (matchedEvents.isNotEmpty) ...[
                              Text('RACES', style: AppText.label(11)),
                              const SizedBox(height: Spacing.sm),
                              for (var i = 0; i < matchedEvents.length; i++) ...[
                                _EventResult(event: matchedEvents[i]),
                                if (i != matchedEvents.length - 1)
                                  const SizedBox(height: 6),
                              ],
                              const SizedBox(height: Spacing.lg),
                            ],
                            if (matchedPlayers.isNotEmpty) ...[
                              Text(
                                  'PLAYERS · ${league?.name.toUpperCase() ?? "LEAGUE"}',
                                  style: AppText.label(11)),
                              const SizedBox(height: Spacing.sm),
                              for (var i = 0;
                                  i < matchedPlayers.length;
                                  i++) ...[
                                _PlayerResult(
                                  member: matchedPlayers[i],
                                  leagueId: league!.id,
                                ),
                                if (i != matchedPlayers.length - 1)
                                  const SizedBox(height: 6),
                              ],
                            ],
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback? onClear;
  const _SearchField({
    required this.controller,
    required this.focusNode,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: t.strokeColor, width: 1.5),
        borderRadius: const BorderRadius.all(Radius.circular(999)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 2),
      child: Row(
        children: [
          Icon(Icons.search, size: 18, color: t.colorScheme.onSurface),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              textInputAction: TextInputAction.search,
              inputFormatters: [LengthLimitingTextInputFormatter(64)],
              style: AppText.body(14),
              decoration: InputDecoration(
                hintText: 'Search races, players…',
                hintStyle: AppText.body(14,
                    color: t.colorScheme.onSurface.withOpacity(0.4)),
                border: InputBorder.none,
                isCollapsed: true,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: Spacing.sm),
              ),
            ),
          ),
          if (onClear != null)
            InkWell(
              onTap: onClear,
              borderRadius: const BorderRadius.all(Radius.circular(999)),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.close,
                    size: 16,
                    color: t.colorScheme.onSurface.withOpacity(0.6)),
              ),
            ),
        ],
      ),
    );
  }
}

class _EventResult extends StatelessWidget {
  final Event event;
  const _EventResult({required this.event});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final flag = flagFor(event.country);
    // Prefer the race session as the tap target; fall back to whatever the
    // event's first session is so freshly-published rounds without a race
    // session yet still navigate somewhere useful.
    final session = event.sessions.isEmpty
        ? null
        : event.sessions.firstWhere(
            (s) => s.type.name == 'race',
            orElse: () => event.sessions.first,
          );
    return InkWell(
      onTap: session == null
          ? null
          : () => context.push('/race/${event.round}/${session.id}'),
      borderRadius: Radii.rLg,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md, vertical: Spacing.sm),
        decoration: BoxDecoration(
          border: Border.all(color: t.strokeColor, width: Strokes.card),
          borderRadius: Radii.rLg,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: Text('R${event.round}', style: AppText.display(14)),
            ),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      if (flag != null) ...[
                        Text(flag,
                            style: const TextStyle(fontSize: 14, height: 1)),
                        const SizedBox(width: 6),
                      ],
                      Flexible(
                        child: Text(
                          event.name.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                          style: AppText.body(13, weight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 1),
                  Text(
                    event.circuitName,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: AppText.body(11,
                        color: t.colorScheme.onSurface.withOpacity(0.55)),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                size: 18,
                color: t.colorScheme.onSurface.withOpacity(0.45)),
          ],
        ),
      ),
    );
  }
}

class _PlayerResult extends StatelessWidget {
  final LeagueMember member;
  final String leagueId;
  const _PlayerResult({required this.member, required this.leagueId});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final scope = AppState.of(context);
    final isMe = member.id == scope.auth.currentUserId;
    return InkWell(
      onTap: () => context.push('/league/$leagueId/player/${member.id}'),
      borderRadius: Radii.rLg,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md, vertical: Spacing.sm),
        decoration: BoxDecoration(
          border: Border.all(color: t.strokeColor, width: Strokes.card),
          borderRadius: Radii.rLg,
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isMe
                    ? BrandColors.accent
                    : t.colorScheme.onSurface.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: Text(
                member.displayName.isEmpty
                    ? '?'
                    : member.displayName[0].toUpperCase(),
                style: AppText.display(12,
                    color: isMe
                        ? Colors.white
                        : t.colorScheme.onSurface.withOpacity(0.7)),
              ),
            ),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      member.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: AppText.body(13,
                          weight:
                              isMe ? FontWeight.w800 : FontWeight.w700),
                    ),
                  ),
                  if (isMe) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: const BoxDecoration(
                        color: BrandColors.accent,
                        borderRadius: Radii.rSm,
                      ),
                      child: Text('YOU',
                          style: AppText.label(8, color: Colors.white)),
                    ),
                  ],
                  if (member.role.toLowerCase() == 'owner') ...[
                    const SizedBox(width: 6),
                    Text('· OWNER',
                        style: AppText.label(9,
                            color:
                                t.colorScheme.onSurface.withOpacity(0.45))),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                size: 18,
                color: t.colorScheme.onSurface.withOpacity(0.45)),
          ],
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  final String text;
  const _Hint({required this.text});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.xl),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: AppText.body(13,
              color: t.colorScheme.onSurface.withOpacity(0.6)),
        ),
      ),
    );
  }
}
