// ignore_for_file: deprecated_member_use
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../api/models/import_payload.dart';
import '../components/branded_toast.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// Owner-only data import screen — download the JSON schema for a season,
/// fill it in by hand or with an AI, upload it back to preview the planned
/// changes, then confirm the apply.
///
/// Reachable only when the current league's `role == 'owner'` — the settings
/// link is hidden for non-owners and the backend rejects the requests anyway.
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});
  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  // Anchor for the iOS share popover. share_plus throws PlatformException
  // when this rect is zero on iPad/iOS — we attach the key to the Download
  // action row and pass its frame as the origin.
  final GlobalKey _downloadKey = GlobalKey();
  int _season = DateTime.now().year;
  bool _busy = false;
  String? _filePath;
  Map<String, dynamic>? _parsedBody;
  ImportPreview? _preview;
  bool _ackOverwrite = false;
  /// Years actually bootstrapped in the backend — populated on first build.
  /// Falls back to [DateTime.now().year] when the call hasn't finished yet
  /// so the picker isn't empty during initial paint.
  List<int>? _availableSeasons;

  bool _seasonsRequested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // AppState.of(context) can't run from initState — InheritedWidget lookup
    // requires the widget to be mounted. Trigger the seasons fetch on the
    // first didChangeDependencies call instead; guard so it only fires once.
    if (!_seasonsRequested) {
      _seasonsRequested = true;
      // ignore: discarded_futures
      _loadSeasons();
    }
  }

  Future<void> _loadSeasons() async {
    final scope = AppState.of(context);
    try {
      final ss = await scope.api.seasons();
      if (!mounted) return;
      final years = ss.map((s) => s.year).toList()..sort((a, b) => b.compareTo(a));
      setState(() {
        _availableSeasons = years;
        if (years.isNotEmpty && !years.contains(_season)) _season = years.first;
      });
    } catch (_) {
      // Leave _availableSeasons null; picker falls back to the static range.
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final scope = AppState.of(context);
    final league = scope.league.league;

    if (league == null || league.role != 'owner') {
      // Defensive: settings should already filter this out.
      return Scaffold(
        backgroundColor: t.colorScheme.surface,
        body: SafeArea(
          child: Center(
            child: Text('Owner only.',
                style: AppText.body(14, color: t.colorScheme.onSurface)),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: t.colorScheme.surface,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(Spacing.lg),
          children: [
            Row(children: [
              IconButton(
                onPressed: () => context.pop(),
                icon: const Icon(Icons.arrow_back_ios_new, size: 16),
              ),
              Text('Data import'.toUpperCase(), style: AppText.display(22)),
            ]),
            const SizedBox(height: Spacing.sm),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
              child: Text(
                'Download the JSON template for a season, fill it in (yourself '
                'or with an AI), then upload it to preview and apply.',
                style: AppText.body(12,
                    color: t.colorScheme.onSurface.withOpacity(0.7)),
              ),
            ),

            const SizedBox(height: Spacing.xl),
            Text('SEASON', style: AppText.label(11)),
            const SizedBox(height: Spacing.sm),
            _SeasonPicker(
              value: _season,
              years: _availableSeasons,
              onChanged: (y) => setState(() {
                _season = y;
                _preview = null;
                _parsedBody = null;
              }),
            ),

            const SizedBox(height: Spacing.xl),
            Text('1. DOWNLOAD TEMPLATE', style: AppText.label(11)),
            const SizedBox(height: Spacing.sm),
            KeyedSubtree(
              key: _downloadKey,
              child: _ActionRow(
                t: t,
                label: 'Download $_season schema',
                icon: Icons.download_outlined,
                onTap: _busy ? null : _onDownload,
              ),
            ),

            const SizedBox(height: Spacing.xl),
            Text('2. UPLOAD FILLED FILE', style: AppText.label(11)),
            const SizedBox(height: Spacing.sm),
            _ActionRow(
              t: t,
              label: _filePath == null
                  ? 'Pick filled JSON file'
                  : 'Replace: ${_filePath!.split('/').last}',
              icon: Icons.file_upload_outlined,
              onTap: _busy ? null : _onPickFile,
            ),

            if (_preview != null) ...[
              const SizedBox(height: Spacing.xl),
              _PreviewSection(
                preview: _preview!,
                ackOverwrite: _ackOverwrite,
                onAckChanged: (v) => setState(() => _ackOverwrite = v),
              ),
              const SizedBox(height: Spacing.lg),
              _ActionRow(
                t: t,
                label: _busy
                    ? 'Applying…'
                    : 'Apply ${_preview!.applied.predictions} prediction'
                        '${_preview!.applied.predictions == 1 ? '' : 's'}',
                icon: Icons.check_circle_outline,
                accent: true,
                onTap: _busy || _canApply() ? _onApply : null,
              ),
              if (!_canApply()) ...[
                const SizedBox(height: Spacing.xs),
                Text(
                  _preview!.overwrites.isNotEmpty && !_ackOverwrite
                      ? 'Tick the override warning to enable apply.'
                      : '',
                  style: AppText.body(11,
                      color: t.colorScheme.onSurface.withOpacity(0.55)),
                ),
              ],
            ],
            const SizedBox(height: Spacing.xxl),
          ],
        ),
      ),
    );
  }

  bool _canApply() {
    final p = _preview;
    if (p == null) return false;
    if (p.overwrites.isNotEmpty && !_ackOverwrite) return false;
    return p.applied.predictions > 0 ||
        p.applied.preseasonPicks > 0 ||
        p.applied.preseasonStandings > 0;
  }

  Future<void> _onDownload() async {
    final scope = AppState.of(context);
    final league = scope.league.league!;
    setState(() => _busy = true);
    try {
      final json = await scope.api.getImportSchema(league.id, _season);
      final pretty = const JsonEncoder.withIndent('  ').convert(json);
      // Write to a temp file and share — lets the user pick where it lands
      // (Files app, drive, AirDrop, etc.) without us needing a save-dialog.
      final dir = await getTemporaryDirectory();
      final filename = 'undercut-import-${_slug(league.name)}-$_season.json';
      final f = File('${dir.path}/$filename');
      await f.writeAsString(pretty);
      // iOS requires a non-zero anchor rect for the share popover. Derive it
      // from the Download button's bounds so the sheet animates out from the
      // tapped element.
      final box = _downloadKey.currentContext?.findRenderObject() as RenderBox?;
      Rect? origin;
      if (box != null && box.hasSize) {
        final offset = box.localToGlobal(Offset.zero);
        origin = offset & box.size;
      }
      await Share.shareXFiles([XFile(f.path)],
          subject: 'Undercut import schema · $_season',
          sharePositionOrigin: origin);
      if (!mounted) return;
      BrandedToast.show(context, 'Schema downloaded', tone: ToastTone.ok);
    } catch (e, st) {
      debugPrint('[import] download failed: $e');
      debugPrint('[import] stack: $st');
      if (mounted) {
        BrandedToast.show(context, 'Download failed: ${_short(e)}', tone: ToastTone.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _short(Object e) {
    // ApiException etc print the JSON body; trim for the pill.
    final s = e.toString();
    return s.length > 60 ? '${s.substring(0, 60)}…' : s;
  }

  Future<void> _onPickFile() async {
    final scope = AppState.of(context);
    final league = scope.league.league!;
    setState(() => _busy = true);
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      final f = picked.files.first;
      final bytes = f.bytes ?? (f.path == null ? null : await File(f.path!).readAsBytes());
      if (bytes == null) throw 'no bytes';
      final body = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      // Run the preview against the backend.
      final preview = await scope.api.previewImport(league.id, body);
      if (!mounted) return;
      setState(() {
        _filePath = f.path ?? f.name;
        _parsedBody = body;
        _preview = preview;
        _ackOverwrite = false;
      });
    } catch (e, st) {
      debugPrint('[import] preview failed: $e');
      debugPrint('[import] stack: $st');
      if (mounted) BrandedToast.show(context, 'Preview failed: ${_short(e)}', tone: ToastTone.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onApply() async {
    final scope = AppState.of(context);
    final league = scope.league.league!;
    final body = Map<String, dynamic>.from(_parsedBody!);
    if (_preview!.overwrites.isNotEmpty) body['overwrite'] = true;
    setState(() => _busy = true);
    try {
      final res = await scope.api.applyImport(league.id, body);
      if (!mounted) return;
      BrandedToast.show(
        context,
        'Applied ${res.applied.predictions} predictions',
        tone: ToastTone.ok,
      );
      // Clear the preview so the screen resets to step 1.
      setState(() {
        _preview = null;
        _parsedBody = null;
        _filePath = null;
        _ackOverwrite = false;
      });
    } catch (e, st) {
      debugPrint('[import] apply failed: $e');
      debugPrint('[import] stack: $st');
      if (mounted) BrandedToast.show(context, 'Apply failed: ${_short(e)}', tone: ToastTone.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _slug(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
}

class _SeasonPicker extends StatelessWidget {
  final int value;
  /// Bootstrapped seasons returned by the backend. When null we haven't
  /// loaded yet — render a placeholder skeleton row instead of guessing.
  final List<int>? years;
  final ValueChanged<int> onChanged;
  const _SeasonPicker({required this.value, required this.years, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    if (years == null) {
      return SizedBox(
        height: 40,
        child: Center(
          child: Text('Loading seasons…',
              style: AppText.label(10,
                  color: t.colorScheme.onSurface.withOpacity(0.5))),
        ),
      );
    }
    if (years!.isEmpty) {
      return SizedBox(
        height: 40,
        child: Center(
          child: Text('No bootstrapped seasons',
              style: AppText.label(10,
                  color: t.colorScheme.onSurface.withOpacity(0.5))),
        ),
      );
    }
    final yrs = years!;
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final y in yrs) ...[
            GestureDetector(
              onTap: () => onChanged(y),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.md, vertical: 7),
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: y == value ? BrandColors.accent : null,
                  border: Border.all(color: t.strokeColor, width: 1.5),
                  borderRadius: Radii.rSm,
                ),
                child: Center(
                  child: Text('$y',
                      style: AppText.label(11,
                          color: y == value
                              ? Colors.white
                              : t.colorScheme.onSurface)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final ThemeData t;
  final String label;
  final IconData icon;
  final bool accent;
  final VoidCallback? onTap;
  const _ActionRow({
    required this.t,
    required this.label,
    required this.icon,
    this.accent = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    final bg = accent
        ? (disabled ? BrandColors.accent.withOpacity(0.3) : BrandColors.accent)
        : null;
    final fg = accent ? Colors.white : t.colorScheme.onSurface;
    return InkWell(
      onTap: onTap,
      borderRadius: Radii.rLg,
      child: Container(
        padding: const EdgeInsets.all(Spacing.lg),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: t.strokeColor, width: Strokes.card),
          borderRadius: Radii.rLg,
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Text(label,
                  style: AppText.body(14, weight: FontWeight.w700, color: fg)),
            ),
            Text('›',
                style: TextStyle(
                    fontSize: 20, color: fg.withOpacity(disabled ? 0.4 : 1))),
          ],
        ),
      ),
    );
  }
}

class _PreviewSection extends StatelessWidget {
  final ImportPreview preview;
  final bool ackOverwrite;
  final ValueChanged<bool> onAckChanged;
  const _PreviewSection({
    required this.preview,
    required this.ackOverwrite,
    required this.onAckChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('3. PREVIEW', style: AppText.label(11)),
        const SizedBox(height: Spacing.sm),
        // Summary card
        Container(
          padding: const EdgeInsets.all(Spacing.lg),
          decoration: BoxDecoration(
            border: Border.all(color: t.strokeColor, width: Strokes.card),
            borderRadius: Radii.rLg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text('SEASON ${preview.seasonYear}',
                    style: AppText.display(16)),
                const Spacer(),
                Text('${preview.members.length} members',
                    style: AppText.label(10,
                        color: t.colorScheme.onSurface.withOpacity(0.6))),
              ]),
              const SizedBox(height: Spacing.md),
              _statRow(t, 'New predictions',
                  '${preview.applied.predictions - preview.overwrites.length}'),
              _statRow(t, 'Will overwrite in-app',
                  '${preview.overwrites.length}',
                  warn: preview.overwrites.isNotEmpty),
              _statRow(t, 'Preseason picks', '${preview.applied.preseasonPicks}'),
              _statRow(t, 'Standings sets', '${preview.applied.preseasonStandings}'),
              _statRow(t, 'Skipped', '${preview.skipped.length}',
                  warn: preview.skipped.isNotEmpty, muted: true),
            ],
          ),
        ),

        // Score preview per member
        if (preview.scorePreview.isNotEmpty) ...[
          const SizedBox(height: Spacing.lg),
          Text('PROJECTED POINTS', style: AppText.label(11)),
          const SizedBox(height: Spacing.sm),
          for (final s in preview.scorePreview)
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.xs),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.sm, vertical: Spacing.xs),
                decoration: BoxDecoration(
                  border: Border.all(color: t.strokeColor, width: Strokes.card),
                  borderRadius: Radii.rLg,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(s.displayName,
                          style: AppText.body(13, weight: FontWeight.w700)),
                    ),
                    Text('+${s.addedPoints}', style: AppText.display(15)),
                    const SizedBox(width: 2),
                    Text('pts',
                        style: AppText.label(8,
                            color:
                                t.colorScheme.onSurface.withOpacity(0.6))),
                  ],
                ),
              ),
            ),
        ],

        // Override warning
        if (preview.overwrites.isNotEmpty) ...[
          const SizedBox(height: Spacing.lg),
          Container(
            padding: const EdgeInsets.all(Spacing.lg),
            decoration: BoxDecoration(
              color: BrandColors.accent.withOpacity(0.12),
              border: Border.all(color: BrandColors.accent, width: Strokes.card),
              borderRadius: Radii.rLg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: BrandColors.accent, size: 18),
                  const SizedBox(width: Spacing.sm),
                  Text('OVERRIDE WARNING',
                      style: AppText.label(11, color: BrandColors.accent)),
                ]),
                const SizedBox(height: Spacing.xs),
                Text(
                  'This upload will replace ${preview.overwrites.length} '
                  'pick(s) that players entered in the app. The original picks '
                  'will be lost.',
                  style: AppText.body(13, color: t.colorScheme.onSurface),
                ),
                const SizedBox(height: Spacing.sm),
                for (final o in preview.overwrites.take(8))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      '• ${o.displayName} · R${o.round} ${o.sessionType}',
                      style: AppText.body(12,
                          color: t.colorScheme.onSurface.withOpacity(0.8)),
                    ),
                  ),
                if (preview.overwrites.length > 8)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '+ ${preview.overwrites.length - 8} more',
                      style: AppText.body(11,
                          color: t.colorScheme.onSurface.withOpacity(0.55)),
                    ),
                  ),
                const SizedBox(height: Spacing.md),
                GestureDetector(
                  onTap: () => onAckChanged(!ackOverwrite),
                  child: Row(children: [
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: ackOverwrite ? BrandColors.accent : null,
                        border: Border.all(
                            color: BrandColors.accent, width: 1.5),
                        borderRadius: Radii.rSm,
                      ),
                      child: ackOverwrite
                          ? const Icon(Icons.check,
                              color: Colors.white, size: 14)
                          : null,
                    ),
                    const SizedBox(width: Spacing.sm),
                    Expanded(
                      child: Text(
                          'I understand this will replace existing in-app picks.',
                          style: AppText.body(13,
                              weight: FontWeight.w700,
                              color: t.colorScheme.onSurface)),
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ],

        // Skipped section
        if (preview.skipped.isNotEmpty) ...[
          const SizedBox(height: Spacing.lg),
          Text('SKIPPED ROWS', style: AppText.label(11)),
          const SizedBox(height: Spacing.sm),
          Container(
            padding: const EdgeInsets.all(Spacing.lg),
            decoration: BoxDecoration(
              border: Border.all(color: t.strokeColor, width: Strokes.card),
              borderRadius: Radii.rLg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final s in preview.skipped.take(10))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      '• ${s.kind}${s.sessionId != null ? ' #${s.sessionId}' : ''}: ${s.reason}',
                      style: AppText.body(11,
                          color: t.colorScheme.onSurface.withOpacity(0.75)),
                    ),
                  ),
                if (preview.skipped.length > 10)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '+ ${preview.skipped.length - 10} more',
                      style: AppText.body(11,
                          color: t.colorScheme.onSurface.withOpacity(0.55)),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _statRow(ThemeData t, String label, String value,
      {bool warn = false, bool muted = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Expanded(
          child: Text(label,
              style: AppText.body(12,
                  color: muted
                      ? t.colorScheme.onSurface.withOpacity(0.6)
                      : t.colorScheme.onSurface)),
        ),
        Text(value,
            style: AppText.display(15,
                color: warn ? BrandColors.accent : t.colorScheme.onSurface)),
      ]),
    );
  }
}
