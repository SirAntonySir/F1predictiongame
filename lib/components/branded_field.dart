// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// Form input that matches the rest of the app's pill / card aesthetic:
/// caps label above a bordered box, replaces Material's floating-label
/// `TextField`. Picks a colour direction via [onDark] so the same widget
/// works on light surfaces (cream tickets, theme surface) and on the
/// brand-red striped pavilion the onboarding uses.
///
/// When [onDark] is null (the default), the field follows the current
/// theme: white-or-near-black border + onSurface text. Pass `false` on
/// cream tickets, `true` on red surfaces.
class BrandedField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool obscure;
  final String? hint;
  final bool? onDark;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final bool readOnly;
  final String? Function(String?)? validator;
  /// Forwarded to the inner [TextField]. Allows tests to address the
  /// underlying input by key while the BrandedField wrapper itself can
  /// stay un-keyed.
  final Key? fieldKey;

  const BrandedField({
    super.key,
    required this.label,
    required this.controller,
    this.obscure = false,
    this.hint,
    this.onDark,
    this.keyboardType,
    this.inputFormatters,
    this.readOnly = false,
    this.validator,
    this.fieldKey,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    // Three colour modes — separates the label (sits on the surrounding
    // surface) from the box (its own white/cream stock so the input
    // stays readable regardless of what's behind it).
    //
    // - onDark==null  : theme defaults. Label = onSurface, box = mutedSurface.
    // - onDark==false : "light surface" (cream ticket etc.). Label = black,
    //                   box = translucent white over the cream so it still
    //                   reads as part of the ticket.
    // - onDark==true  : "dark surface" (brand-red pavilion, etc.). Label =
    //                   white to blend with the surrounding text; the BOX
    //                   is opaque white with black inner text so the input
    //                   reads like a high-contrast ticket-stub insert.
    final Color labelColor;
    final Color boxBorder;
    final Color boxFill;
    final Color boxText;
    if (onDark == null) {
      labelColor = t.colorScheme.onSurface.withOpacity(0.75);
      boxBorder = t.strokeColor;
      boxFill = t.mutedSurface;
      boxText = t.colorScheme.onSurface;
    } else if (onDark == false) {
      labelColor = Colors.black.withOpacity(0.75);
      boxBorder = Colors.black;
      boxFill = Colors.white.withOpacity(0.55);
      boxText = Colors.black;
    } else {
      labelColor = Colors.white;
      boxBorder = Colors.white;
      boxFill = Colors.white;
      boxText = Colors.black;
    }
    final Widget input = TextField(
      key: fieldKey,
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      readOnly: readOnly,
      cursorColor: boxText,
      style: AppText.body(14, weight: FontWeight.w700, color: boxText),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: AppText.body(13, color: boxText.withOpacity(0.45)),
        isDense: true,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 12),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppText.label(10, color: labelColor)),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: boxFill,
            border: Border.all(color: boxBorder, width: 1.5),
            borderRadius: const BorderRadius.all(Radius.circular(8)),
          ),
          child: input,
        ),
      ],
    );
  }
}
