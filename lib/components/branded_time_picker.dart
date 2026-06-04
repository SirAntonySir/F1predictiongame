// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'branded_sheet.dart';

/// House-style time picker — two Anton number wheels (hours / minutes) in a
/// [BrandedSheet], replacing Material's clock-face `showTimePicker` so the
/// quiet-hours selection matches the rest of the app. Returns the chosen
/// time, or null if dismissed.
Future<TimeOfDay?> showBrandedTimePicker(
  BuildContext context, {
  required TimeOfDay initial,
  String title = 'Select time',
}) {
  return showBrandedSheet<TimeOfDay>(
    context,
    builder: (_) => _BrandedTimePickerDialog(initial: initial, title: title),
  );
}

class _BrandedTimePickerDialog extends StatefulWidget {
  final TimeOfDay initial;
  final String title;
  const _BrandedTimePickerDialog({required this.initial, required this.title});

  @override
  State<_BrandedTimePickerDialog> createState() => _BrandedTimePickerDialogState();
}

class _BrandedTimePickerDialogState extends State<_BrandedTimePickerDialog> {
  late final FixedExtentScrollController _hourCtrl =
      FixedExtentScrollController(initialItem: widget.initial.hour);
  late final FixedExtentScrollController _minuteCtrl =
      FixedExtentScrollController(initialItem: widget.initial.minute);

  @override
  void dispose() {
    _hourCtrl.dispose();
    _minuteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return BrandedSheet(
      title: widget.title,
      content: SizedBox(
        height: 174,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _wheel(t, controller: _hourCtrl, count: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
              child: Text(':', style: AppText.display(30, color: t.colorScheme.onSurface)),
            ),
            _wheel(t, controller: _minuteCtrl, count: 60),
          ],
        ),
      ),
      primaryLabel: 'Set',
      onPrimary: () => Navigator.of(context).pop(TimeOfDay(
        hour: _hourCtrl.selectedItem % 24,
        minute: _minuteCtrl.selectedItem % 60,
      )),
      onSecondary: () => Navigator.of(context).pop(),
    );
  }

  Widget _wheel(
    ThemeData t, {
    required FixedExtentScrollController controller,
    required int count,
  }) {
    return SizedBox(
      width: 78,
      height: 174,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Selection band behind the centre row, in the app's pill style.
          Container(
            height: 54,
            decoration: BoxDecoration(
              color: t.mutedSurface,
              border: Border.all(color: t.strokeColor, width: 1.5),
              borderRadius: const BorderRadius.all(Radius.circular(10)),
            ),
          ),
          ListWheelScrollView.useDelegate(
            controller: controller,
            itemExtent: 54,
            perspective: 0.004,
            diameterRatio: 1.6,
            physics: const FixedExtentScrollPhysics(),
            useMagnifier: true,
            magnification: 1.12,
            overAndUnderCenterOpacity: 0.35,
            childDelegate: ListWheelChildBuilderDelegate(
              childCount: count,
              builder: (_, i) => Center(
                child: Text(
                  i.toString().padLeft(2, '0'),
                  style: AppText.display(30, color: t.colorScheme.onSurface),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
