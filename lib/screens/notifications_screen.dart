// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';

import '../services/reminder_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// Debug-style view of every locally-scheduled notification this app has
/// queued with the OS. Reads `FlutterLocalNotificationsPlugin
/// .pendingNotificationRequests()` via [ReminderService] so we can verify the
/// 5h/1h/10min reminders for upcoming sessions are actually armed.
///
/// Decodes the notification id (`sessionId * 10 + bucket`) so each row says
/// which session + which lead bucket it belongs to.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  Future<List<PendingNotificationRequest>>? _pending;
  ({bool inited, bool permissionGranted})? _status;

  static const _bucketLabels = ['5h LEAD', '1h LEAD', '10min LEAD'];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _status = ReminderService.instance.statusSnapshot();
      _pending = ReminderService.instance.pendingRequests();
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final scope = AppState.of(context);
    final settings = scope.notifications.settings;
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
                    child: Text('NOTIFICATIONS',
                        style: AppText.display(22),
                        maxLines: 1,
                        overflow: TextOverflow.fade,
                        softWrap: false),
                  ),
                  IconButton(
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh, size: 18),
                    tooltip: 'Refresh',
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                    Spacing.lg, Spacing.sm, Spacing.lg, Spacing.xxl),
                children: [
                  _StatusCard(
                    settingsEnabled: settings.enabled,
                    inited: _status?.inited ?? false,
                    permissionGranted: _status?.permissionGranted ?? false,
                  ),
                  const SizedBox(height: Spacing.lg),
                  Text('PENDING', style: AppText.label(11)),
                  const SizedBox(height: Spacing.sm),
                  FutureBuilder<List<PendingNotificationRequest>>(
                    future: _pending,
                    builder: (_, snap) {
                      if (snap.connectionState != ConnectionState.done) {
                        return const Padding(
                          padding: EdgeInsets.all(Spacing.lg),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      if (snap.hasError) {
                        return _Empty(
                          message: 'Failed to load: ${snap.error}',
                        );
                      }
                      final items = snap.data ?? const [];
                      if (items.isEmpty) {
                        return const _Empty(
                          message:
                              'No notifications scheduled. If you expect a reminder, '
                              'open the app, make sure notifications are enabled, '
                              'and pull-to-refresh upcoming on the home screen.',
                        );
                      }
                      // Sort by id so the same session's 5h / 1h / 10min
                      // buckets group together visually.
                      final sorted = [...items]
                        ..sort((a, b) => a.id.compareTo(b.id));
                      return Column(
                        children: [
                          for (final p in sorted) ...[
                            _NotifRow(req: p),
                            const SizedBox(height: Spacing.sm),
                          ],
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final bool settingsEnabled;
  final bool inited;
  final bool permissionGranted;
  const _StatusCard({
    required this.settingsEnabled,
    required this.inited,
    required this.permissionGranted,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final ok = settingsEnabled && inited && permissionGranted;
    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        border: Border.all(color: t.strokeColor, width: Strokes.card),
        borderRadius: Radii.rLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color:
                    ok ? BrandColors.ok : BrandColors.accent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: Spacing.sm),
            Text(ok ? 'READY' : 'NOT READY',
                style: AppText.label(11,
                    color: ok ? BrandColors.ok : BrandColors.accent)),
          ]),
          const SizedBox(height: Spacing.sm),
          _row(t, 'App toggle', settingsEnabled ? 'On' : 'Off'),
          _row(t, 'Reminder service', inited ? 'Initialised' : 'Not started'),
          _row(t, 'OS permission',
              permissionGranted ? 'Granted' : 'Denied / not asked'),
        ],
      ),
    );
  }

  Widget _row(ThemeData t, String label, String value) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: AppText.body(13,
                    color: t.colorScheme.onSurface.withOpacity(0.65))),
            Text(value, style: AppText.body(13, weight: FontWeight.w700)),
          ],
        ),
      );
}

class _NotifRow extends StatelessWidget {
  final PendingNotificationRequest req;
  const _NotifRow({required this.req});

  ({int sessionId, String bucketLabel}) _decode() {
    final sessionId = req.id ~/ 10;
    final bucket = req.id % 10;
    final label = bucket >= 0 && bucket < _NotificationsScreenState._bucketLabels.length
        ? _NotificationsScreenState._bucketLabels[bucket]
        : 'BUCKET $bucket';
    return (sessionId: sessionId, bucketLabel: label);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final decoded = _decode();
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: t.strokeColor, width: Strokes.card),
        borderRadius: Radii.rLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(req.title ?? '(no title)',
                    style: AppText.body(14, weight: FontWeight.w800)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: const BoxDecoration(
                  color: BrandColors.accent,
                  borderRadius: BorderRadius.all(Radius.circular(6)),
                ),
                child: Text(decoded.bucketLabel,
                    style: AppText.label(9, color: Colors.white)),
              ),
            ],
          ),
          if (req.body != null) ...[
            const SizedBox(height: 4),
            Text(req.body!,
                style: AppText.body(12,
                    color: t.colorScheme.onSurface.withOpacity(0.7))),
          ],
          const SizedBox(height: 6),
          Wrap(
            spacing: Spacing.md,
            runSpacing: 4,
            children: [
              _meta(t, 'ID', req.id.toString()),
              _meta(t, 'Session', decoded.sessionId.toString()),
              if (req.payload != null && req.payload!.isNotEmpty)
                _meta(t, 'Payload', req.payload!),
            ],
          ),
        ],
      ),
    );
  }

  Widget _meta(ThemeData t, String k, String v) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$k ',
              style: AppText.label(9,
                  color: t.colorScheme.onSurface.withOpacity(0.5))),
          Text(v,
              style: AppText.body(11,
                  weight: FontWeight.w700,
                  color: t.colorScheme.onSurface.withOpacity(0.85))),
        ],
      );
}

class _Empty extends StatelessWidget {
  final String message;
  const _Empty({required this.message});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        border: Border.all(color: t.strokeColor, width: Strokes.card),
        borderRadius: Radii.rLg,
      ),
      child: Text(message,
          style: AppText.body(13,
              color: t.colorScheme.onSurface.withOpacity(0.7))),
    );
  }
}
