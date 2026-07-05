// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
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
///
/// When [obscure] is true the box grows a tappable show/hide eye in its
/// suffix; the reveal state is local to the field.
class BrandedField extends StatefulWidget {
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
  /// Forwarded to the inner [TextField], for callers that need to react to
  /// focus changes (e.g. re-canonicalizing input on blur).
  final FocusNode? focusNode;

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
    this.focusNode,
  });

  @override
  State<BrandedField> createState() => _BrandedFieldState();
}

class _BrandedFieldState extends State<BrandedField> {
  /// Obscured password fields start hidden; the eye toggle flips this.
  /// Irrelevant (and the eye is absent) when [BrandedField.obscure] is false.
  bool _reveal = false;

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
    if (widget.onDark == null) {
      labelColor = t.colorScheme.onSurface.withOpacity(0.75);
      boxBorder = t.strokeColor;
      boxFill = t.mutedSurface;
      boxText = t.colorScheme.onSurface;
    } else if (widget.onDark == false) {
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
      key: widget.fieldKey,
      controller: widget.controller,
      focusNode: widget.focusNode,
      obscureText: widget.obscure && !_reveal,
      keyboardType: widget.keyboardType,
      inputFormatters: widget.inputFormatters,
      readOnly: widget.readOnly,
      cursorColor: boxText,
      style: AppText.body(14, weight: FontWeight.w700, color: boxText),
      decoration: InputDecoration(
        hintText: widget.hint,
        hintStyle: AppText.body(13, color: boxText.withOpacity(0.45)),
        isDense: true,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 12),
        suffixIcon: widget.obscure
            ? IconButton(
                onPressed: () => setState(() => _reveal = !_reveal),
                splashRadius: 18,
                tooltip: _reveal ? 'Hide password' : 'Show password',
                icon: FaIcon(
                  _reveal
                      ? FontAwesomeIcons.solidEyeSlash
                      : FontAwesomeIcons.solidEye,
                  size: 16,
                  color: boxText.withOpacity(0.6),
                ),
              )
            : null,
        suffixIconConstraints:
            const BoxConstraints(minWidth: 40, minHeight: 40),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: AppText.label(10, color: labelColor)),
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
