// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../theme/colors.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../big_pill.dart';
import '../branded_sheet.dart';

/// One selectable row in a [showTicketActionsSheet]. [isShare] flags the share
/// row so the sheet can set it apart (accent label, divider above) from the
/// plain navigation rows.
class TicketAction {
  final String label;
  final VoidCallback onTap;
  final bool isShare;
  const TicketAction({
    required this.label,
    required this.onTap,
    this.isShare = false,
  });
}

/// House-style action menu for a ticket long-press. Renders [title] (the event
/// name) and a stacked list of [actions] as full-width pill buttons. Selecting
/// one closes the sheet and runs its callback on the next frame — so a share
/// capture or route push happens after the sheet's dismissal animation, not
/// during it. Navigation actions use the muted-surface fill; the share action
/// is the accent primary so the menu keeps a clear hierarchy.
Future<void> showTicketActionsSheet(
  BuildContext context, {
  required String title,
  required List<TicketAction> actions,
}) {
  return showBrandedSheet<void>(
    context,
    builder: (sheetCtx) => _TicketActionsBody(title: title, actions: actions),
  );
}

class _TicketActionsBody extends StatelessWidget {
  final String title;
  final List<TicketAction> actions;
  const _TicketActionsBody({required this.title, required this.actions});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            Spacing.lg, Spacing.sm, Spacing.lg, Spacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: Spacing.md),
                decoration: BoxDecoration(
                  color: t.colorScheme.onSurface.withOpacity(0.2),
                  borderRadius: const BorderRadius.all(Radius.circular(999)),
                ),
              ),
            ),
            Text(title,
                style: AppText.display(24, color: t.colorScheme.onSurface),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: Spacing.lg),
            for (var i = 0; i < actions.length; i++) ...[
              if (i > 0) const SizedBox(height: Spacing.sm),
              _button(context, t, actions[i]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _button(BuildContext context, ThemeData t, TicketAction a) {
    return BigPill(
      label: a.label,
      // Share is the accent primary; navigation actions sit on the muted
      // surface so the export action stays visually dominant.
      background: a.isShare ? BrandColors.accent : t.mutedSurface,
      foreground: a.isShare ? Colors.white : t.colorScheme.onSurface,
      onTap: () {
        Navigator.of(context).pop();
        // Defer to the next frame so the sheet finishes dismissing before the
        // action (share capture / navigation) runs.
        WidgetsBinding.instance.addPostFrameCallback((_) => a.onTap());
      },
    );
  }
}
