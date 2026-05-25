import 'package:flutter/material.dart';

class Spacing {
  static const double xxs = 4;
  static const double xs = 6;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 14;
  static const double xl = 18;
  static const double xxl = 24;
}

class Radii {
  static const Radius sm = Radius.circular(8);
  static const Radius md = Radius.circular(12);
  static const Radius lg = Radius.circular(14);
  static const Radius xl = Radius.circular(18);
  static const Radius pill = Radius.circular(999);

  static const BorderRadius rSm = BorderRadius.all(sm);
  static const BorderRadius rMd = BorderRadius.all(md);
  static const BorderRadius rLg = BorderRadius.all(lg);
  static const BorderRadius rXl = BorderRadius.all(xl);
  static const BorderRadius rPill = BorderRadius.all(pill);
}

class Strokes {
  static const double subtle = 1.5;
  static const double card = 2;
}

class Durations {
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration tick = Duration(seconds: 1);
}
