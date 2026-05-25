import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppText {
  static TextStyle display(double size, {Color? color}) =>
      GoogleFonts.anton(
        fontSize: size,
        height: 1.0,
        letterSpacing: -size * 0.03,
        color: color,
      );

  static TextStyle body(double size, {FontWeight? weight, Color? color}) =>
      GoogleFonts.inter(
        fontSize: size,
        height: 1.4,
        fontWeight: weight ?? FontWeight.w500,
        color: color,
      );

  static TextStyle label(double size, {Color? color}) => GoogleFonts.inter(
        fontSize: size,
        height: 1.0,
        fontWeight: FontWeight.w800,
        letterSpacing: size <= 9 ? 2.0 : 1.5,
        color: color,
      );
}
