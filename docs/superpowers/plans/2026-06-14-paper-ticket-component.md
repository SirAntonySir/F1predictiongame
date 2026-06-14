# Paper-Ticket Component — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a parameterised `TicketRohling` base widget + two variants (`PickTicket`, `SouvenirTicket`), with three style presets selected per event, and migrate every existing `TicketCard` call site.

**Architecture:** One `CustomPaint`-backed Rohling owns the ticket chrome (background, outline, perforation, tear, notches, edge serials, accent bar). A `TicketStyle` enum bundles font + decor choices; a small lookup table maps each preset to its tokens. `styleForEvent(Event)` picks the default style based on circuit metadata. Variants are thin widgets that pass app data into the Rohling's slots.

**Tech Stack:** Flutter / Dart 3.5, `flutter_svg`, `google_fonts` (new), `CustomPaint`. Backend: Fastify, drizzle-orm, PostgreSQL.

**Spec:** `docs/superpowers/specs/2026-06-14-paper-ticket-component-design.md`

---

## File Structure

```
lib/components/ticket/
  ticket_style.dart             T1   TicketStyle enum + preset tokens
  ticket_ornament.dart          T2   ornament SVG constants
  ticket_stub.dart              T3   stub variants + renderers
  ticket_rohling.dart           T4   base widget + _TicketPainter
  car_svg.dart                  T6   illustration slot
  pick_ticket.dart              T7   PickTicket variant
  souvenir_ticket.dart          T8   SouvenirTicket variant
  ticket_card_compat.dart       T9   deprecated alias
lib/theme/
  ticket_style_for_event.dart   T5   heritage/night mapping
backend/src/db/schema.ts                              T10  constructor_svg table
backend/src/db/migrations/0013_*.sql                  T10  generated migration
backend/src/repo/constructorSvgs.ts                   T10  CRUD
backend/src/api/routes/constructorSvgs.ts             T10  HTTP route
```

Migrations of call sites land as separate commits in T11–T13. Final cleanup is T14.

---

### Task 1: `TicketStyle` enum + preset lookup table

**Files:**
- Create: `lib/components/ticket/ticket_style.dart`
- Modify: `pubspec.yaml` — add `google_fonts: ^6.2.1`

- [ ] **Step 1: Add the dependency**

Append under the existing `dependencies:` block in `pubspec.yaml`:

```yaml
  google_fonts: ^6.2.1
```

Run `flutter pub get`. Expected: clean pub-get output.

- [ ] **Step 2: Write the file**

```dart
// lib/components/ticket/ticket_style.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'ticket_ornament.dart';
import 'ticket_stub.dart';

/// A bundle of typographic + decorative choices for the paper-ticket chrome.
/// Each value maps to a [TicketStyleTokens] entry via [tokensFor].
enum TicketStyle { vintageStencil, posterSprint, darkBoardingPass }

/// Background pattern painted underneath the body content. Drawn by
/// [TicketBackgroundPainter] (see ticket_rohling.dart).
enum TicketBackground { plain, linedVertical, diagonalStripeBand }

/// Resolved tokens for one [TicketStyle]. The Rohling pulls fonts and colours
/// from here so callers never construct a TextStyle directly.
class TicketStyleTokens {
  final TextStyle title;        // big hero block
  final TextStyle subtitle;     // under title + small meta rows
  final TextStyle meta;         // mono edge serial + top row
  final TextStyle dataValue;    // bold value in dataRow cells
  final TextStyle dataLabel;    // small label above the value
  final Color paperColor;
  final Color inkColor;
  final Color? accentBarColor;  // null = no accent bar
  final TicketBackground background;
  final TicketStub defaultStub;
  final TicketOrnament defaultOrnament;
  final bool innerFrame;        // 1px inset frame inside the outline

  const TicketStyleTokens({
    required this.title,
    required this.subtitle,
    required this.meta,
    required this.dataValue,
    required this.dataLabel,
    required this.paperColor,
    required this.inkColor,
    required this.accentBarColor,
    required this.background,
    required this.defaultStub,
    required this.defaultOrnament,
    required this.innerFrame,
  });
}

const _cream = Color(0xFFF1DD95);
const _ink   = Color(0xFF1B1206);
const _red   = Color(0xFFE10600);

TicketStyleTokens tokensFor(TicketStyle s) {
  switch (s) {
    case TicketStyle.vintageStencil:
      return TicketStyleTokens(
        title:     GoogleFonts.alfaSlabOne(fontSize: 44, height: 0.9, letterSpacing: -0.5, color: _ink),
        subtitle:  GoogleFonts.ibmPlexMono(fontSize: 9, letterSpacing: 3, fontWeight: FontWeight.w700, color: _ink),
        meta:      GoogleFonts.ibmPlexMono(fontSize: 9, letterSpacing: 2, fontWeight: FontWeight.w700, color: _ink),
        dataValue: GoogleFonts.alfaSlabOne(fontSize: 14, letterSpacing: 1, color: _ink),
        dataLabel: GoogleFonts.ibmPlexMono(fontSize: 9, letterSpacing: 2, fontWeight: FontWeight.w700, color: _ink),
        paperColor: _cream,
        inkColor: _ink,
        accentBarColor: null,
        background: TicketBackground.linedVertical,
        defaultStub: const TicketStub.admitOne(),
        defaultOrnament: TicketOrnament.crossedFlags,
        innerFrame: true,
      );
    case TicketStyle.posterSprint:
      return TicketStyleTokens(
        title:     GoogleFonts.bebasNeue(fontSize: 56, height: 0.85, letterSpacing: 2, color: _ink),
        subtitle:  GoogleFonts.ibmPlexMono(fontSize: 9, letterSpacing: 3, fontWeight: FontWeight.w700, color: _ink),
        meta:      GoogleFonts.ibmPlexMono(fontSize: 9, letterSpacing: 2, fontWeight: FontWeight.w700, color: _ink),
        dataValue: GoogleFonts.anton(fontSize: 18, letterSpacing: 1, color: _ink),
        dataLabel: GoogleFonts.ibmPlexMono(fontSize: 9, letterSpacing: 2, fontWeight: FontWeight.w700, color: _ink),
        paperColor: _cream,
        inkColor: _ink,
        accentBarColor: null,
        background: TicketBackground.diagonalStripeBand,
        defaultStub: const TicketStub.repeatedTitle(),
        defaultOrnament: TicketOrnament.none,
        innerFrame: false,
      );
    case TicketStyle.darkBoardingPass:
      return TicketStyleTokens(
        title:     GoogleFonts.oswald(fontSize: 36, height: 0.9, letterSpacing: 1, fontWeight: FontWeight.w700, color: _cream),
        subtitle:  GoogleFonts.ibmPlexMono(fontSize: 9, letterSpacing: 3, fontWeight: FontWeight.w700, color: _cream),
        meta:      GoogleFonts.ibmPlexMono(fontSize: 9, letterSpacing: 2, fontWeight: FontWeight.w700, color: _cream),
        dataValue: GoogleFonts.anton(fontSize: 17, letterSpacing: 1, color: _cream),
        dataLabel: GoogleFonts.ibmPlexMono(fontSize: 9, letterSpacing: 2, fontWeight: FontWeight.w700, color: _cream),
        paperColor: _ink,
        inkColor: _cream,
        accentBarColor: _red,
        background: TicketBackground.plain,
        defaultStub: const TicketStub.serialCode(),
        defaultOrnament: TicketOrnament.none,
        innerFrame: true,
      );
  }
}
```

- [ ] **Step 3: Verify it compiles**

Run: `flutter analyze lib/components/ticket/ticket_style.dart`

Expected: no errors. (Imports `ticket_ornament.dart` and `ticket_stub.dart` which don't exist yet — defer to T2/T3; for now this step will fail to resolve those imports.) **Skip the analyze step here**; analyze runs after T3.

- [ ] **Step 4: Commit**

```bash
git add lib/components/ticket/ticket_style.dart pubspec.yaml pubspec.lock
git commit -m "feat(ticket): add TicketStyle enum and preset tokens"
```

---

### Task 2: `TicketOrnament` + SVG constants

**Files:**
- Create: `lib/components/ticket/ticket_ornament.dart`

- [ ] **Step 1: Write the file**

```dart
// lib/components/ticket/ticket_ornament.dart
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

enum TicketOrnament { none, crossedFlags }

/// Renders the ornament for the hero block. Returns SizedBox.shrink for [none].
class TicketOrnamentWidget extends StatelessWidget {
  final TicketOrnament ornament;
  final Color color;
  final double size;
  const TicketOrnamentWidget({
    super.key,
    required this.ornament,
    required this.color,
    this.size = 18,
  });

  @override
  Widget build(BuildContext context) {
    switch (ornament) {
      case TicketOrnament.none:
        return const SizedBox.shrink();
      case TicketOrnament.crossedFlags:
        return SizedBox(
          height: size,
          child: SvgPicture.string(
            _crossedFlags,
            colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
          ),
        );
    }
  }
}

const _crossedFlags = '''
<svg viewBox="0 0 100 36" xmlns="http://www.w3.org/2000/svg">
  <rect x="46" y="2" width="2" height="32"/>
  <rect x="52" y="2" width="2" height="32"/>
  <path d="M28 4 L48 4 L48 18 L28 22 Z"/>
  <path d="M52 4 L72 8 L72 22 L52 18 Z"/>
</svg>
''';
```

- [ ] **Step 2: Commit**

```bash
git add lib/components/ticket/ticket_ornament.dart
git commit -m "feat(ticket): add TicketOrnament with crossed-flags SVG"
```

---

### Task 3: `TicketStub` + renderer

**Files:**
- Create: `lib/components/ticket/ticket_stub.dart`

- [ ] **Step 1: Write the file**

```dart
// lib/components/ticket/ticket_stub.dart
import 'package:flutter/material.dart';

/// Right-edge sliver. Distinct constructors model the three flavours; each
/// carries the data it needs to render (no further parameters in the Rohling).
sealed class TicketStub {
  const TicketStub();
  const factory TicketStub.none() = _StubNone;
  const factory TicketStub.admitOne() = _StubAdmitOne;
  const factory TicketStub.repeatedTitle([String? overrideText]) = _StubRepeated;
  const factory TicketStub.serialCode([String? overrideText]) = _StubSerial;
}

class _StubNone extends TicketStub { const _StubNone(); }
class _StubAdmitOne extends TicketStub { const _StubAdmitOne(); }
class _StubRepeated extends TicketStub {
  final String? overrideText;
  const _StubRepeated([this.overrideText]);
}
class _StubSerial extends TicketStub {
  final String? overrideText;
  const _StubSerial([this.overrideText]);
}

/// Visible width of the stub sliver. The Rohling reserves this space regardless
/// of variant so the perforation line lands consistently across styles.
const double kStubWidth = 60;

/// Width of zero when there is no stub (so the perforation collapses).
double widthFor(TicketStub stub) => stub is _StubNone ? 0 : kStubWidth;

/// Renders the stub contents. The Rohling already provides the bordered slot
/// — this widget only paints the inner text. `titleHint` is the body title,
/// available to stubs that echo it (repeatedTitle).
class TicketStubContent extends StatelessWidget {
  final TicketStub stub;
  final String titleHint;
  final TextStyle textStyle;
  const TicketStubContent({
    super.key,
    required this.stub,
    required this.titleHint,
    required this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    final s = stub;
    if (s is _StubNone) return const SizedBox.shrink();
    final text = switch (s) {
      _StubAdmitOne() => 'ADMIT ONE',
      _StubRepeated() => (s.overrideText ?? titleHint).toUpperCase(),
      _StubSerial()   => (s.overrideText ?? 'PICK').toUpperCase(),
      _ => '',
    };
    return Center(
      child: RotatedBox(
        quarterTurns: 3, // text reads bottom-to-top
        child: Text(
          text,
          style: textStyle.copyWith(letterSpacing: 4, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify imports compile**

Run: `flutter analyze lib/components/ticket/`

Expected: no errors across `ticket_style.dart`, `ticket_ornament.dart`, `ticket_stub.dart`.

- [ ] **Step 3: Commit**

```bash
git add lib/components/ticket/ticket_stub.dart
git commit -m "feat(ticket): add TicketStub sealed class and renderer"
```

---

### Task 4: `TicketRohling` base widget + painter

**Files:**
- Create: `lib/components/ticket/ticket_rohling.dart`
- Create: `test/components/ticket_rohling_test.dart`

The Rohling is intentionally one file with the painter — it's a tight unit (~250 LOC including painter). Splitting the painter into its own file makes navigation worse.

- [ ] **Step 1: Write a widget test for the public surface**

```dart
// test/components/ticket_rohling_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/components/ticket/ticket_ornament.dart';
import 'package:predictiongame/components/ticket/ticket_rohling.dart';
import 'package:predictiongame/components/ticket/ticket_stub.dart';
import 'package:predictiongame/components/ticket/ticket_style.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('renders title and subtitle text', (tester) async {
    await tester.pumpWidget(_wrap(const TicketRohling(
      style: TicketStyle.posterSprint,
      metaLeft: 'RD 07 · MONACO GP',
      metaRight: 'SUN 12:00',
      title: 'MONACO',
      subtitle: 'CIRCUIT DE MONACO',
      dataRow: [],
      stub: TicketStub.admitOne(),
    )));
    expect(find.text('MONACO'), findsOneWidget);
    expect(find.text('CIRCUIT DE MONACO'), findsOneWidget);
    expect(find.text('RD 07 · MONACO GP'), findsOneWidget);
    expect(find.text('SUN 12:00'), findsOneWidget);
  });

  testWidgets('renders data row cells', (tester) async {
    await tester.pumpWidget(_wrap(const TicketRohling(
      style: TicketStyle.posterSprint,
      title: 'MONACO',
      dataRow: [
        TicketDataCell(label: 'P1', value: 'VER'),
        TicketDataCell(label: 'P2', value: 'NOR'),
      ],
      stub: TicketStub.none(),
    )));
    expect(find.text('P1'), findsOneWidget);
    expect(find.text('VER'), findsOneWidget);
    expect(find.text('P2'), findsOneWidget);
    expect(find.text('NOR'), findsOneWidget);
  });

  testWidgets('renders admit-one stub text', (tester) async {
    await tester.pumpWidget(_wrap(const TicketRohling(
      style: TicketStyle.vintageStencil,
      title: 'MONACO',
      dataRow: [],
      stub: TicketStub.admitOne(),
    )));
    expect(find.text('ADMIT ONE'), findsOneWidget);
  });

  testWidgets('renders no stub text when stub is none', (tester) async {
    await tester.pumpWidget(_wrap(const TicketRohling(
      style: TicketStyle.darkBoardingPass,
      title: 'MONACO',
      dataRow: [],
      stub: TicketStub.none(),
    )));
    expect(find.text('ADMIT ONE'), findsNothing);
    expect(find.text('PICK'), findsNothing);
  });
}
```

Run: `flutter test test/components/ticket_rohling_test.dart`

Expected: FAIL — `ticket_rohling.dart` does not exist.

- [ ] **Step 2: Implement the Rohling**

```dart
// lib/components/ticket/ticket_rohling.dart
// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import 'ticket_ornament.dart';
import 'ticket_stub.dart';
import 'ticket_style.dart';

/// A single cell in the bottom dataRow ("P1" / "VER" stacked).
class TicketDataCell {
  final String label;
  final String value;
  const TicketDataCell({required this.label, required this.value});
}

/// Carry-over from the previous TicketCard.
enum TicketTear { none, cut, ghosted }

/// Parameterised "blank" paper-ticket. Variants ([PickTicket], [SouvenirTicket])
/// instantiate this with sensible defaults; callers can use it directly for
/// one-off tickets. All slots are optional except [title] and [stub].
class TicketRohling extends StatelessWidget {
  final TicketStyle style;
  final String? edgeSerial;
  final String? metaLeft;
  final String? metaRight;
  final String title;
  final String? subtitle;
  final Widget? illustration;
  final TicketOrnament? ornament; // overrides preset default
  final List<TicketDataCell> dataRow;
  final TicketStub stub;
  final TicketTear tear;
  final VoidCallback? onTap;

  const TicketRohling({
    super.key,
    required this.style,
    this.edgeSerial,
    this.metaLeft,
    this.metaRight,
    required this.title,
    this.subtitle,
    this.illustration,
    this.ornament,
    required this.dataRow,
    required this.stub,
    this.tear = TicketTear.none,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = tokensFor(style);
    final effectiveOrnament = ornament ?? tokens.defaultOrnament;
    final stubWidth = widthFor(stub);

    final body = Padding(
      padding: const EdgeInsets.fromLTRB(22, 12, 18, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // top meta row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(metaLeft ?? '', style: tokens.meta),
              Text(metaRight ?? '', style: tokens.meta),
            ],
          ),
          const SizedBox(height: 6),
          // hero: ornament + title + subtitle, with illustration on the right
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TicketOrnamentWidget(ornament: effectiveOrnament, color: tokens.inkColor),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(subtitle!, style: tokens.subtitle),
                      ],
                      const SizedBox(height: 2),
                      Text(title, style: tokens.title),
                    ],
                  ),
                ),
                if (illustration != null) ...[
                  const SizedBox(width: 8),
                  SizedBox(width: 90, height: 46, child: illustration),
                ],
              ],
            ),
          ),
          const SizedBox(height: 6),
          // dataRow
          if (dataRow.isNotEmpty)
            Container(
              padding: const EdgeInsets.only(top: 6),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: tokens.inkColor.withOpacity(0.4))),
              ),
              child: Row(
                children: [
                  for (final cell in dataRow)
                    Padding(
                      padding: const EdgeInsets.only(right: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(cell.label, style: tokens.dataLabel),
                          const SizedBox(height: 3),
                          Text(cell.value, style: tokens.dataValue),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );

    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: body),
        if (stubWidth > 0)
          SizedBox(
            width: stubWidth,
            child: TicketStubContent(stub: stub, titleHint: title, textStyle: tokens.meta),
          ),
      ],
    );

    final ticket = IntrinsicHeight(
      child: CustomPaint(
        painter: _TicketPainter(tokens: tokens, stubWidth: stubWidth, tear: tear),
        child: row,
      ),
    );
    if (onTap == null) return ticket;
    return InkWell(
      onTap: onTap,
      borderRadius: const BorderRadius.all(Radius.circular(12)),
      child: ticket,
    );
  }
}

class _TicketPainter extends CustomPainter {
  final TicketStyleTokens tokens;
  final double stubWidth;
  final TicketTear tear;
  static const _radius = 10.0;
  static const _notchRadius = 7.0;

  _TicketPainter({required this.tokens, required this.stubWidth, required this.tear});

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = tokens.paperColor..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = tokens.inkColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final body = _outline(size);
    canvas.drawPath(body, fill);
    _paintBackground(canvas, size);
    canvas.drawPath(body, stroke);

    if (tokens.innerFrame) {
      final inset = Rect.fromLTWH(5, 5, size.width - 10, size.height - 10);
      final frame = Paint()
        ..color = tokens.inkColor.withOpacity(0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8;
      canvas.drawRRect(
        RRect.fromRectAndRadius(inset, const Radius.circular(4)),
        frame,
      );
    }

    if (tokens.accentBarColor != null) {
      final bar = Paint()..color = tokens.accentBarColor!..style = PaintingStyle.fill;
      canvas.drawRect(Rect.fromLTWH(0, 0, 6, size.height), bar);
    }

    if (stubWidth > 0) {
      final perfX = size.width - stubWidth;
      final dashPaint = Paint()
        ..color = tokens.inkColor.withOpacity(0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      const top = _notchRadius;
      final bottom = size.height - _notchRadius;
      const dash = 4.0, gap = 4.0;
      var y = top;
      while (y < bottom) {
        canvas.drawLine(
          Offset(perfX, y),
          Offset(perfX, (y + dash).clamp(top, bottom)),
          dashPaint,
        );
        y += dash + gap;
      }
    }
  }

  void _paintBackground(Canvas canvas, Size size) {
    switch (tokens.background) {
      case TicketBackground.plain:
        return;
      case TicketBackground.linedVertical:
        final p = Paint()..color = tokens.inkColor.withOpacity(0.08)..strokeWidth = 1;
        for (double x = 10; x < size.width - stubWidth - 4; x += 3) {
          canvas.drawLine(Offset(x, 4), Offset(x, size.height - 4), p);
        }
        return;
      case TicketBackground.diagonalStripeBand:
        final bandTop = size.height * 0.30;
        final bandBottom = size.height * 0.78;
        canvas.save();
        canvas.clipRect(Rect.fromLTRB(0, bandTop, size.width - stubWidth, bandBottom));
        final p = Paint()..color = tokens.inkColor.withOpacity(0.10)..strokeWidth = 8;
        for (double d = -size.height; d < size.width + size.height; d += 22) {
          canvas.drawLine(Offset(d, 0), Offset(d + size.height, size.height), p);
        }
        canvas.restore();
        return;
    }
  }

  Path _outline(Size size) {
    const r = _radius;
    const n = _notchRadius;
    final stubX = stubWidth > 0 ? size.width - stubWidth : null;
    final p = Path()..moveTo(r, 0);
    if (stubX != null) {
      p.lineTo(stubX - n, 0);
      p.arcToPoint(Offset(stubX + n, 0), radius: const Radius.circular(_notchRadius), clockwise: false);
    }
    if (tear == TicketTear.cut) {
      p.lineTo(size.width - n, 0);
      p.arcToPoint(Offset(size.width, n), radius: const Radius.circular(_notchRadius), clockwise: false);
      p.lineTo(size.width, size.height - n);
      p.arcToPoint(Offset(size.width - n, size.height), radius: const Radius.circular(_notchRadius), clockwise: false);
    } else {
      p.lineTo(size.width - r, 0);
      p.arcToPoint(Offset(size.width, r), radius: const Radius.circular(_radius));
      p.lineTo(size.width, size.height - r);
      p.arcToPoint(Offset(size.width - r, size.height), radius: const Radius.circular(_radius));
    }
    if (stubX != null) {
      p.lineTo(stubX + n, size.height);
      p.arcToPoint(Offset(stubX - n, size.height), radius: const Radius.circular(_notchRadius), clockwise: false);
    }
    p.lineTo(r, size.height);
    p.arcToPoint(Offset(0, size.height - r), radius: const Radius.circular(_radius));
    p.lineTo(0, r);
    p.arcToPoint(Offset(r, 0), radius: const Radius.circular(_radius));
    p.close();
    return p;
  }

  @override
  bool shouldRepaint(_TicketPainter old) =>
      old.tokens != tokens || old.stubWidth != stubWidth || old.tear != tear;
}
```

(Edge serial rendering — left/right vertical mono text — is deferred to T4b. Adding it inline blew the file past 350 LOC.)

- [ ] **Step 3: Re-run the test**

Run: `flutter test test/components/ticket_rohling_test.dart`

Expected: PASS, 4/4 tests green.

- [ ] **Step 4: Commit**

```bash
git add lib/components/ticket/ticket_rohling.dart test/components/ticket_rohling_test.dart
git commit -m "feat(ticket): add TicketRohling base widget and painter"
```

---

### Task 4b: Edge serials on Rohling

**Files:**
- Modify: `lib/components/ticket/ticket_rohling.dart`
- Modify: `test/components/ticket_rohling_test.dart`

- [ ] **Step 1: Add a failing test**

Append to `test/components/ticket_rohling_test.dart` inside the same `void main()`:

```dart
  testWidgets('renders edgeSerial on left and right edges when provided', (tester) async {
    await tester.pumpWidget(_wrap(const TicketRohling(
      style: TicketStyle.posterSprint,
      edgeSerial: 'AA1234',
      title: 'MONACO',
      dataRow: [],
      stub: TicketStub.none(),
    )));
    expect(find.text('AA1234'), findsNWidgets(2));
  });
```

Run the test file. Expected: FAIL — edgeSerial isn't rendered yet.

- [ ] **Step 2: Implement**

In `TicketRohling.build`, wrap the existing `IntrinsicHeight(...)` in a `Stack` so the edge serials can be positioned absolutely. Replace the `final ticket = IntrinsicHeight(...)` assignment with:

```dart
    final core = IntrinsicHeight(
      child: CustomPaint(
        painter: _TicketPainter(tokens: tokens, stubWidth: stubWidth, tear: tear),
        child: row,
      ),
    );

    final serialStyle = tokens.meta.copyWith(letterSpacing: 3);
    final ticket = Stack(
      children: [
        core,
        if (edgeSerial != null) ...[
          Positioned(
            left: 4, top: 0, bottom: 0,
            child: Center(
              child: RotatedBox(
                quarterTurns: 3,
                child: Text(edgeSerial!, style: serialStyle, maxLines: 1, overflow: TextOverflow.fade),
              ),
            ),
          ),
          Positioned(
            right: 4, top: 0, bottom: 0,
            child: Center(
              child: RotatedBox(
                quarterTurns: 1,
                child: Text(edgeSerial!, style: serialStyle, maxLines: 1, overflow: TextOverflow.fade),
              ),
            ),
          ),
        ],
      ],
    );
```

- [ ] **Step 3: Run tests + commit**

Expected: 5/5 pass.

```bash
git add lib/components/ticket/ticket_rohling.dart test/components/ticket_rohling_test.dart
git commit -m "feat(ticket): render edge serials on left and right edges"
```

---

### Task 5: `styleForEvent` mapping

**Files:**
- Create: `lib/theme/ticket_style_for_event.dart`
- Create: `test/theme/ticket_style_for_event_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/theme/ticket_style_for_event_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/models/event.dart';
import 'package:predictiongame/components/ticket/ticket_style.dart';
import 'package:predictiongame/theme/ticket_style_for_event.dart';

Event _ev(String circuitId) => Event(
  // Fill required Event fields. Inspect lib/api/models/event.dart for the
  // exact constructor — this is a fixture, only `circuitId` matters to
  // styleForEvent. If Event has named required params, pass placeholders.
  // TODO(implementer): adjust to the actual Event constructor.
);

void main() {
  test('heritage circuits map to vintageStencil', () {
    expect(styleForEvent(_ev('monaco')), TicketStyle.vintageStencil);
    expect(styleForEvent(_ev('monza')),  TicketStyle.vintageStencil);
    expect(styleForEvent(_ev('spa')),    TicketStyle.vintageStencil);
  });
  test('night circuits map to darkBoardingPass', () {
    expect(styleForEvent(_ev('singapore')), TicketStyle.darkBoardingPass);
    expect(styleForEvent(_ev('las_vegas')), TicketStyle.darkBoardingPass);
  });
  test('default is posterSprint', () {
    expect(styleForEvent(_ev('bahrain')), TicketStyle.posterSprint);
    expect(styleForEvent(_ev('unknown')), TicketStyle.posterSprint);
  });
}
```

The implementer must inspect `lib/api/models/event.dart` and adjust the `_ev` helper to satisfy `Event`'s real constructor (it has named required params for round, name, etc).

- [ ] **Step 2: Implement**

```dart
// lib/theme/ticket_style_for_event.dart
import '../api/models/event.dart';
import '../components/ticket/ticket_style.dart';

const _heritage = <String>{
  'monaco', 'monza', 'silverstone', 'spa', 'suzuka', 'interlagos'
};
const _night = <String>{
  'singapore', 'las_vegas', 'jeddah', 'bahrain_night', 'losail'
};

TicketStyle styleForEvent(Event event) {
  final id = event.circuitId; // adjust if the field has a different name
  if (_heritage.contains(id)) return TicketStyle.vintageStencil;
  if (_night.contains(id))    return TicketStyle.darkBoardingPass;
  return TicketStyle.posterSprint;
}
```

If `Event.circuitId` doesn't exist under that exact name (check `lib/api/models/event.dart`), use whatever the equivalent slug field is (the existing `CircuitSvg` widget resolves a slug from `Event` via `circuit_slugs.dart` — reuse that resolution).

- [ ] **Step 3: Test + commit**

Run: `flutter test test/theme/ticket_style_for_event_test.dart`

Expected: PASS.

```bash
git add lib/theme/ticket_style_for_event.dart test/theme/ticket_style_for_event_test.dart
git commit -m "feat(ticket): event-driven default style picker"
```

---

### Task 6: `CarSvg` widget (frontend slot)

**Files:**
- Create: `lib/components/ticket/car_svg.dart`

This task ships the widget. The backend route comes in T10; until then, every call returns a zero-size `SizedBox` (the widget is built to handle that gracefully).

- [ ] **Step 1: Write the widget**

Use `lib/components/circuit_svg.dart` as the structural reference — same `StatefulWidget` shape, same `didChangeDependencies` resolution, same error fallback. The endpoint is `GET /api/constructors/:id/car-svg?variant=outline`. Reuse the app's existing API client (the one CircuitSvg pulls via `app_state.dart`).

```dart
// lib/components/ticket/car_svg.dart
// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../state/app_state.dart';

/// Renders a constructor car SVG fetched from /api/constructors/:id/car-svg.
/// Returns a zero-size SizedBox when the SVG isn't stored or the fetch fails —
/// the ticket layout still works without it.
class CarSvg extends StatefulWidget {
  final String? constructorId;
  final String variant;
  final double? width;
  final double? height;
  final Color? color;
  const CarSvg({
    super.key,
    required this.constructorId,
    this.variant = 'outline',
    this.width,
    this.height,
    this.color,
  });

  @override
  State<CarSvg> createState() => _CarSvgState();
}

class _CarSvgState extends State<CarSvg> {
  Future<String?>? _svgFuture;
  String? _key;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant CarSvg old) {
    super.didUpdateWidget(old);
    if (old.constructorId != widget.constructorId || old.variant != widget.variant) {
      _resolve();
    }
  }

  void _resolve() {
    final id = widget.constructorId;
    if (id == null || id.isEmpty) {
      _svgFuture = Future.value(null);
      _key = null;
      return;
    }
    final next = '$id|${widget.variant}';
    if (next == _key) return;
    _key = next;
    final api = AppState.of(context).api; // adjust if AppState exposes a different getter
    _svgFuture = api.fetchString('/api/constructors/$id/car-svg?variant=${widget.variant}')
        .catchError((_) => null);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _svgFuture,
      builder: (ctx, snap) {
        final svg = snap.data;
        if (svg == null || svg.isEmpty) return const SizedBox.shrink();
        return SvgPicture.string(
          svg,
          width: widget.width,
          height: widget.height,
          colorFilter: widget.color == null
              ? null
              : ColorFilter.mode(widget.color!, BlendMode.srcIn),
        );
      },
    );
  }
}
```

Open the existing `lib/components/circuit_svg.dart` while implementing — copy the exact `AppState.of(context).api.<getStringMethod>` pattern (the name may be `fetch`, `getString`, etc — the implementer must inspect the existing client). The catch-all `catchError((_) => null)` is what mirrors the existing CircuitSvg behaviour.

- [ ] **Step 2: Commit**

```bash
git add lib/components/ticket/car_svg.dart
git commit -m "feat(ticket): add CarSvg illustration slot"
```

---

### Task 7: `PickTicket` variant

**Files:**
- Create: `lib/components/ticket/pick_ticket.dart`
- Create: `test/components/pick_ticket_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/components/pick_ticket_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// import the real Event, Pick types — see lib/api/models/
import 'package:predictiongame/components/ticket/pick_ticket.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('shows LOCKED status before the race', (tester) async {
    // build a PickTicket with score=null
    // expect: text 'LOCKED' is in the data row
  });

  testWidgets('shows +points after the race', (tester) async {
    // build a PickTicket with score(points: 18)
    // expect: text '+18' is in the data row
  });

  testWidgets('shows P1/P2 driver codes', (tester) async {
    // build a PickTicket with picks [VER, NOR]
    // expect: 'VER' and 'NOR' appear
  });
}
```

The implementer fills in the test fixtures by inspecting `lib/api/models/event.dart`, `lib/api/models/pick.dart`, `lib/api/models/my_score.dart` (or whichever score model is currently in use). Keep test fixtures inline — don't create a shared helper for one widget's tests.

- [ ] **Step 2: Implement**

```dart
// lib/components/ticket/pick_ticket.dart
import 'package:flutter/material.dart';
import '../../api/models/event.dart';
import '../../api/models/pick.dart';
import '../../theme/ticket_style_for_event.dart';
import 'car_svg.dart';
import 'ticket_rohling.dart';
import 'ticket_stub.dart';
import 'ticket_style.dart';

class PickTicket extends StatelessWidget {
  final Event event;
  final List<Pick> picks;
  /// Null before the race has been scored. When non-null the status cell
  /// shows the score; the stub flips from admit-one to a serial code.
  final int? scorePoints;
  final TicketStyle? styleOverride;
  final VoidCallback? onTap;

  const PickTicket({
    super.key,
    required this.event,
    required this.picks,
    this.scorePoints,
    this.styleOverride,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final style = styleOverride ?? styleForEvent(event);
    final p1 = picks.isNotEmpty ? picks[0] : null;
    final p2 = picks.length >= 2 ? picks[1] : null;
    final p3 = picks.length >= 3 ? picks[2] : null;

    return TicketRohling(
      style: style,
      edgeSerial: 'RD ${event.round} · ${event.circuitId.toUpperCase()}',
      metaLeft: 'RD ${event.round.toString().padLeft(2, '0')} · ${event.name.toUpperCase()}',
      metaRight: _formatTime(event),
      title: event.name.toUpperCase(),
      subtitle: event.circuitName.toUpperCase(),
      illustration: CarSvg(constructorId: p1?.constructorId),
      dataRow: [
        if (p1 != null) TicketDataCell(label: 'P1', value: p1.driverCode),
        if (p2 != null) TicketDataCell(label: 'P2', value: p2.driverCode),
        if (p3 != null) TicketDataCell(label: 'P3', value: p3.driverCode),
        TicketDataCell(
          label: 'STATUS',
          value: scorePoints == null ? 'LOCKED' : '+$scorePoints',
        ),
      ],
      stub: scorePoints == null
          ? const TicketStub.admitOne()
          : TicketStub.serialCode('PICK · ${event.round}'),
      onTap: onTap,
    );
  }

  String _formatTime(Event e) {
    // Match the existing predict-screen header format if available; otherwise
    // a sensible default. Inspect lib/screens/predict_screen.dart for the
    // current convention.
    return ''; // TODO(implementer): fill in
  }
}
```

(Real field names — `event.circuitId`, `event.circuitName`, `pick.constructorId`, `pick.driverCode` — must be confirmed against the actual models. Adjust if the project uses different names.)

- [ ] **Step 3: Run tests + commit**

```bash
git add lib/components/ticket/pick_ticket.dart test/components/pick_ticket_test.dart
git commit -m "feat(ticket): add PickTicket variant"
```

---

### Task 8: `SouvenirTicket` variant

**Files:**
- Create: `lib/components/ticket/souvenir_ticket.dart`
- Create: `test/components/souvenir_ticket_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/components/souvenir_ticket_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/components/ticket/souvenir_ticket.dart';

void main() {
  testWidgets('shows qualitative grade in status cell', (tester) async {
    // build a SouvenirTicket with scorePoints: 25
    // expect: text 'PODIUM CALL' (or whatever the grade resolves to)
  });
  testWidgets('always renders the crossed-flags ornament', (tester) async {
    // expect: SvgPicture finds 1 widget under the ornament slot region
    // OR more robust: pass an ornament test hook
  });
}
```

- [ ] **Step 2: Implement**

```dart
// lib/components/ticket/souvenir_ticket.dart
import 'package:flutter/material.dart';
import '../../api/models/event.dart';
import '../../api/models/pick.dart';
import '../../theme/ticket_style_for_event.dart';
import 'car_svg.dart';
import 'ticket_ornament.dart';
import 'ticket_rohling.dart';
import 'ticket_stub.dart';
import 'ticket_style.dart';

class SouvenirTicket extends StatelessWidget {
  final Event event;
  final List<Pick> picks;
  final int scorePoints;
  final TicketStyle? styleOverride;

  const SouvenirTicket({
    super.key,
    required this.event,
    required this.picks,
    required this.scorePoints,
    this.styleOverride,
  });

  @override
  Widget build(BuildContext context) {
    final style = styleOverride ?? styleForEvent(event);
    final p1 = picks.isNotEmpty ? picks[0] : null;

    return TicketRohling(
      style: style,
      edgeSerial: 'PICK ${event.round} · ${event.circuitId.toUpperCase()}',
      metaLeft: 'RD ${event.round.toString().padLeft(2, '0')} · ${event.name.toUpperCase()}',
      metaRight: 'SEALED',
      title: '${event.name.toUpperCase()} GRAND PRIX',
      subtitle: event.circuitName.toUpperCase(),
      illustration: CarSvg(constructorId: p1?.constructorId),
      ornament: TicketOrnament.crossedFlags, // forced
      dataRow: [
        for (final p in picks.take(3))
          TicketDataCell(label: 'P${picks.indexOf(p) + 1}', value: p.driverCode),
        TicketDataCell(label: 'GRADE', value: _grade(scorePoints)),
        TicketDataCell(label: 'POINTS', value: '+$scorePoints'),
      ],
      stub: TicketStub.serialCode('PICK · ${event.round}'),
    );
  }

  String _grade(int points) {
    if (points >= 25) return 'PODIUM CALL';
    if (points >= 15) return 'SHARP';
    if (points >= 5)  return 'ON IT';
    return 'OFF-PACE';
  }
}
```

- [ ] **Step 3: Test + commit**

```bash
git add lib/components/ticket/souvenir_ticket.dart test/components/souvenir_ticket_test.dart
git commit -m "feat(ticket): add SouvenirTicket variant"
```

---

### Task 9: `TicketCard` compat alias

**Files:**
- Create: `lib/components/ticket/ticket_card_compat.dart`

The current `lib/components/ticket_card.dart` is the source of truth for the old API. Re-export the new component under the old name so the call sites compile while the migration commits land.

- [ ] **Step 1: Add the alias**

```dart
// lib/components/ticket/ticket_card_compat.dart
@Deprecated('Use TicketRohling / PickTicket / SouvenirTicket instead. '
    'This alias is removed in T14.')
export 'ticket_rohling.dart' show TicketRohling, TicketTear, TicketDataCell;
```

- [ ] **Step 2: Commit**

```bash
git add lib/components/ticket/ticket_card_compat.dart
git commit -m "chore(ticket): add deprecated alias for migration"
```

(The original `lib/components/ticket_card.dart` is removed in T14 once all call sites have been migrated.)

---

### Task 10: Backend — `constructor_svg` table + route

**Files:**
- Modify: `backend/src/db/schema.ts`
- Create: `backend/src/db/migrations/0013_*.sql` (drizzle-generated)
- Create: `backend/src/repo/constructorSvgs.ts`
- Create: `backend/src/api/routes/constructorSvgs.ts`
- Modify: `backend/src/index.ts` — register the new route
- Create: `backend/test/integration/api_constructor_svg.test.ts`

Mirror the existing circuit-svg infrastructure (`backend/src/repo/circuitSvgs.ts`, `backend/src/api/routes/circuits.ts` — find the SVG route there).

- [ ] **Step 1: Add the schema**

In `backend/src/db/schema.ts`, after the `circuitSvg` table declaration, add:

```typescript
export const constructorSvg = pgTable('constructor_svg', {
  constructorId: text('constructor_id').notNull().references(() => constructor.id, { onDelete: 'cascade' }),
  variant: text('variant').notNull(), // 'outline' for v1
  svg: text('svg').notNull(),
  fetchedAt: timestamp('fetched_at', { withTimezone: true }).notNull().defaultNow()
}, (t) => ({
  pk: primaryKey({ columns: [t.constructorId, t.variant] })
}))
```

- [ ] **Step 2: Generate the migration**

Run: `cd backend && npm run db:generate`

Hand-edit if needed (same pattern as the quali-knockout migration). Apply with `make migrate`.

- [ ] **Step 3: Repo**

```typescript
// backend/src/repo/constructorSvgs.ts
import { and, eq } from 'drizzle-orm'
import { getDb } from '../db/client.js'
import { constructorSvg } from '../db/schema.js'

export async function get(constructorId: string, variant: string): Promise<string | null> {
  const db = getDb()
  const rows = await db.select().from(constructorSvg).where(
    and(eq(constructorSvg.constructorId, constructorId), eq(constructorSvg.variant, variant))
  )
  return rows[0]?.svg ?? null
}

export async function upsert(constructorId: string, variant: string, svg: string): Promise<void> {
  const db = getDb()
  await db.insert(constructorSvg).values({ constructorId, variant, svg })
    .onConflictDoUpdate({
      target: [constructorSvg.constructorId, constructorSvg.variant],
      set: { svg, fetchedAt: new Date() }
    })
}
```

- [ ] **Step 4: Route**

```typescript
// backend/src/api/routes/constructorSvgs.ts
import type { FastifyInstance } from 'fastify'
import * as repo from '../../repo/constructorSvgs.js'
import { ApiError } from '../errors.js'

export async function registerConstructorSvgRoutes(app: FastifyInstance): Promise<void> {
  app.get<{ Params: { id: string }, Querystring: { variant?: string } }>(
    '/api/constructors/:id/car-svg',
    async (req, reply) => {
      const variant = req.query.variant ?? 'outline'
      const svg = await repo.get(req.params.id, variant)
      if (svg == null) throw new ApiError('NOT_FOUND', `no car svg for ${req.params.id}/${variant}`)
      reply.type('image/svg+xml').send(svg)
    }
  )
}
```

Register in `backend/src/index.ts` alongside the other route registrations.

- [ ] **Step 5: Integration test**

```typescript
// backend/test/integration/api_constructor_svg.test.ts
import { describe, it, expect } from 'vitest'
import { buildApp } from '../../src/index.js'
import * as constructors from '../../src/repo/constructors.js'
import * as repo from '../../src/repo/constructorSvgs.js'

describe('GET /api/constructors/:id/car-svg', () => {
  it('returns 404 when the svg is not stored', async () => {
    const app = await buildApp({ scheduler: null })
    const res = await app.inject({ method: 'GET', url: '/api/constructors/nonexistent/car-svg' })
    expect(res.statusCode).toBe(404)
  })

  it('returns the stored svg with image/svg+xml content-type', async () => {
    await constructors.upsertConstructor({
      id: 'red_bull', name: 'Red Bull', nationality: null,
      wikipediaUrl: null, imageUrl: null, imageUrlOverride: null, teamColour: null
    })
    await repo.upsert('red_bull', 'outline', '<svg><rect/></svg>')
    const app = await buildApp({ scheduler: null })
    const res = await app.inject({ method: 'GET', url: '/api/constructors/red_bull/car-svg' })
    expect(res.statusCode).toBe(200)
    expect(res.headers['content-type']).toContain('image/svg+xml')
    expect(res.body).toBe('<svg><rect/></svg>')
  })
})
```

Run: `make backend-test`. Expected: all tests pass with 2 new.

- [ ] **Step 6: Commit**

```bash
git add backend/src/db/schema.ts backend/src/db/migrations/0013_*.sql backend/src/db/migrations/meta/* backend/src/repo/constructorSvgs.ts backend/src/api/routes/constructorSvgs.ts backend/src/index.ts backend/test/integration/api_constructor_svg.test.ts
git commit -m "feat(api): constructor_svg storage and GET /api/constructors/:id/car-svg"
```

---

### Task 11: Migrate `home_screen._pickCard`

**Files:**
- Modify: `lib/screens/home_screen.dart`

- [ ] **Step 1: Find the call site**

```bash
grep -n "TicketCard" lib/screens/home_screen.dart
```

- [ ] **Step 2: Replace the `TicketCard(...)` invocation**

Replace with `PickTicket(event: …, picks: …, scorePoints: …)`. The existing call constructs body and stub widgets manually — those go away; PickTicket handles its own layout. Where the body had a custom child (e.g. a Countdown widget), check whether it's still needed — if yes, file as a follow-up. For v1, the countdown is dropped from the ticket and stays on a separate widget on the home screen (the existing Countdown widget already lives independently).

- [ ] **Step 3: Smoke-test in the app**

Run `flutter run`. Navigate to the home screen with a pick committed. Visual check:
- Ticket shows event name as title
- P1 / P2 driver codes in data row
- "LOCKED" status (pre-race) or "+points" (post-race)
- Style matches the event (e.g. Monaco = vintage)

- [ ] **Step 4: Commit**

```bash
git add lib/screens/home_screen.dart
git commit -m "refactor(home): migrate pick card to PickTicket"
```

---

### Task 12: Migrate `session_results_screen._FutureSessionHero`

**Files:**
- Modify: `lib/screens/session_results_screen.dart`

Same pattern as T11. Replace the `TicketCard(...)` invocation inside `_FutureSessionHero` with `PickTicket(event: ..., picks: ..., scorePoints: null)`.

Commit:
```bash
git commit -m "refactor(results): migrate future-session hero to PickTicket"
```

---

### Task 13: Migrate the second `TicketCard` in `session_results_screen`

**Files:**
- Modify: `lib/screens/session_results_screen.dart`

Same pattern. Locate the second usage (post-race ticket; `grep -n "TicketCard" lib/screens/session_results_screen.dart` will list both). Replace with `PickTicket(event, picks, scorePoints: score.points)`.

Commit:
```bash
git commit -m "refactor(results): migrate post-race ticket to PickTicket"
```

---

### Task 14: Delete the old `TicketCard`

**Files:**
- Delete: `lib/components/ticket_card.dart`
- Delete: `lib/components/ticket/ticket_card_compat.dart`
- Modify: any leftover import sites

- [ ] **Step 1: Confirm no remaining users**

```bash
grep -rn "TicketCard\|ticket_card" lib/ test/
```

Expected: only the file to be deleted itself shows up (its own declaration). Any other hit is a missed migration — go back and fix that first.

- [ ] **Step 2: Delete the files and update any imports**

```bash
rm lib/components/ticket_card.dart lib/components/ticket/ticket_card_compat.dart
```

- [ ] **Step 3: Analyze + test**

```bash
flutter analyze
flutter test
```

Expected: clean (modulo the pre-existing `withOpacity` warning in `pod_tile.dart`).

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "chore(ticket): remove deprecated TicketCard"
```

---

## Out-of-plan follow-ups (separate tickets)

- **Seed constructor car SVGs.** Script `backend/src/scripts/seedConstructorSvgs.ts` that ingests a folder of SVG files keyed by constructor id. Not strictly needed to ship the component — the ticket renders without the illustration when the endpoint returns 404.
- **Share / image export flow for SouvenirTicket.** Not in scope for this plan.
- **Backend-driven style mapping.** Move the heritage/night sets into a `style` column on the `circuit` table once we want non-engineers editing the table.
