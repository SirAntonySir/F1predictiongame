# Paper-Ticket Component — Design

**Goal:** Replace the existing `TicketCard` with a richer, more bespoke "paper ticket" component that the F1 prediction app uses everywhere a user's pick or a future session appears. Each ticket should feel hand-printed, not corporate-template.

**Status:** Approved (brainstorm 2026-06-14)

---

## Vocabulary

- **Rohling** — the parameterised base widget. German for "blank" / "blueprint stock". It owns the paper-ticket *chrome* (background, outline, perforation, tear, edge serials, ornament, stub) and exposes slots for content.
- **Variant** — a thin domain-specific widget (`PickTicket`, `SouvenirTicket`) that wraps the Rohling, fills its slots from app data, and picks sensible defaults.
- **Style preset** — a bundle of typographic and decorative choices (display font, stub treatment, background pattern, palette). One `TicketStyle` enum, three values today.

## Decisions

### Scope

- Two variants ship: **`PickTicket`** (locked user prediction) and **`SouvenirTicket`** (shareable post-race artifact). No live-animated state.
- All current `TicketCard` call sites migrate to `PickTicket`:
  - `home_screen._pickCard`
  - `session_results_screen._FutureSessionHero` (pre-race form)
  - `session_results_screen` second `TicketCard` usage (post-race form)
- `TicketCard` stays exported as a deprecated alias around `TicketRohling` for one release so build doesn't break mid-cutover, then is deleted.

### Architecture

Slot model **C** (named layouts on a shared painter) with a parameterised Rohling on top. One painter, one set of slot semantics, multiple style presets, two variants.

```
TicketRohling
  ├─ _TicketPainter   (background pattern, outline, perforation, tear, notches, accent bar)
  ├─ edgeSerial       (vertical mono on both edges)
  ├─ ornament         (small SVG above title)
  ├─ metaLeft + metaRight  (top row)
  ├─ title + subtitle (hero block — display typeface)
  ├─ illustration     (CarSvg from backend, optional)
  ├─ dataRow          (bottom-row label/value cells)
  └─ stub             (right-edge sliver — admit-one, serial, repeated-title, or cut)
```

### Style presets

`TicketStyle` enum with three values. Each preset bundles a font choice, palette, background pattern, default stub treatment, and ornament default. New styles are added by extending the enum and the lookup table — no new widget.

| Preset | Display font | Background | Palette | Default stub | Default ornament | Inspiration |
| --- | --- | --- | --- | --- | --- | --- |
| `vintageStencil` | Alfa Slab One | lined-paper vertical hairlines | cream-on-dark with thin inset frame | admit-one | crossed flags | reference image #1 |
| `posterSprint` | Bebas Neue | diagonal stripe band behind title only | cream | repeated title in stub | none | reference image #2 |
| `darkBoardingPass` | Oswald 700 | plain | cream-on-black with red 8 px accent bar on left | serial code | none | modern souvenir |

Edge-serial typeface is **IBM Plex Mono** across all presets.

### Style mapping

Event-driven default with caller override. Lives in `lib/theme/ticket_style_for_event.dart`:

```dart
TicketStyle styleForEvent(Event e) {
  if (_heritage.contains(e.circuitId)) return TicketStyle.vintageStencil;
  if (_night.contains(e.circuitId))    return TicketStyle.darkBoardingPass;
  return TicketStyle.posterSprint;     // default
}

const _heritage = <String>{
  'monaco', 'monza', 'silverstone', 'spa', 'suzuka', 'interlagos'
};
const _night = <String>{
  'singapore', 'las_vegas', 'jeddah', 'bahrain_night', 'losail'
};
```

`PickTicket` and `SouvenirTicket` both accept an optional `styleOverride: TicketStyle?` so the souvenir-share flow can lock a style independent of the event.

### Asset pipeline

#### Fonts

Add `google_fonts: ^6.x` as a pubspec dependency. Use `GoogleFonts.alfaSlabOne()`, `GoogleFonts.bebasNeue()`, `GoogleFonts.oswald()`, `GoogleFonts.ibmPlexMono()` from inside the style preset table. First-launch download is acceptable for this feature; styles fall through to system serif/sans if the network call fails (`google_fonts` does this automatically).

If we later want offline-first guarantees, bundle the .ttf files under `assets/fonts/` and declare them in `pubspec.yaml`. Not required for ship.

#### Car SVGs

Mirror the existing circuit-SVG pipeline (`lib/components/circuit_svg.dart` + `/api/circuits/:id/svg`):

- **Storage:** new table `constructor_svg(constructorId, variant, svg, fetchedAt)` keyed by `(constructorId, variant)`. Schema like `circuit_svg`.
- **Backend route:** `GET /api/constructors/:id/car-svg?variant=outline` returning the SVG body as `image/svg+xml`. Returns 404 when not stored.
- **Flutter widget:** `CarSvg(constructorId, variant, width, height, color)` — same shape as `CircuitSvg`. Renders a zero-size `SizedBox` on miss so the ticket layout stays correct.
- **Initial seed:** one variant (`outline`) per current constructor. Seed by `tsx src/scripts/seedConstructorSvgs.ts` reading from a static folder of source SVGs the user provides. Not in this design's scope — tracked separately.

If no car SVG is available when a ticket renders, the `illustration` slot resolves to an empty SizedBox and the title block expands to fill the space.

### Ornaments

Vector ornaments rendered inline via `flutter_svg` from constant strings in `lib/components/ticket/ticket_ornament.dart`. Two values for v1:
- `crossedFlags` — chequered crossed flags above the title (vintage default)
- `none`

Future-friendly: adding a `starburst` or `laurel` means appending one constant.

### Slot specifications per variant

**`PickTicket(event, picks, score?)`**

| Slot | Source |
| --- | --- |
| `style` | `styleOverride ?? styleForEvent(event)` |
| `edgeSerial` | `'RD ${event.round} · ${event.circuitId.toUpperCase()}'` |
| `metaLeft` | `'RD ${event.round.toString().padLeft(2, '0')} · ${event.name.toUpperCase()}'` |
| `metaRight` | Localised scheduled start (e.g. `'SUN 12:00'`) |
| `title` | `event.name.toUpperCase()` (e.g. `'MONACO'`, `'BRAZIL GP'`) |
| `subtitle` | `event.circuitName.toUpperCase()` |
| `illustration` | `CarSvg(constructorId: picks.first?.constructorId)` (P1 driver's team) |
| `ornament` | preset default |
| `dataRow` | `[('P1', picks[0].driverCode), ('P2', picks[1].driverCode), …, ('STATUS', _statusCell(score))]` where `_statusCell` is `'LOCKED'` pre-race, `'+${score.points}'` post-race |
| `stub` | preset default — pre-race; `serialCode('PICK · ${event.round}')` post-race |
| `tear` | `none` |

**`SouvenirTicket(event, picks, score)`**

Same anatomy as `PickTicket`, plus:
- `title` uses the long form (`'MONACO GRAND PRIX'`) and a larger font scale
- `dataRow` last cell shows a qualitative grade (`'PODIUM CALL'`, `'SHARP'`, `'OFF-PACE'`) derived from `score.points`
- `ornament` is forced to `crossedFlags` regardless of preset, for a more decorated keepsake feel
- `tear` is `none`; the souvenir is meant to be screenshot whole

### Migration

Each migration is its own commit (one call site → one commit) so the diff is reviewable and bisectable. `TicketCard` is kept as a deprecated re-export from `lib/components/ticket/ticket_card_compat.dart` for the cutover, then removed in a final commit.

### File structure

```
lib/components/ticket/
  ticket_rohling.dart           // base widget + _TicketPainter
  ticket_style.dart             // TicketStyle enum + preset lookup table
  ticket_stub.dart              // TicketStub sealed class + renderers
  ticket_ornament.dart          // TicketOrnament enum + SVG constants
  car_svg.dart                  // illustration slot (mirrors circuit_svg.dart)
  pick_ticket.dart              // PickTicket variant
  souvenir_ticket.dart          // SouvenirTicket variant
  ticket_card_compat.dart       // temporary deprecated alias

lib/theme/
  ticket_style_for_event.dart   // heritage/night mapping table

backend/src/db/schema.ts                                   // constructor_svg table
backend/src/db/migrations/0013_*.sql                       // new table
backend/src/repo/constructorSvgs.ts                        // CRUD
backend/src/api/routes/constructorSvgs.ts                  // GET /api/constructors/:id/car-svg
```

## Out of scope

- Animated transitions / live indicators.
- Local-bundled font assets (we lean on `google_fonts`).
- Seeding the constructor SVG content. The pipeline ships; the actual SVGs are seeded in a follow-up.
- Sharing flow (image export). The souvenir variant is built; the share button is a separate task.

## Risks / open questions

- **First-launch font download** — visible 100–300 ms reflow on first use. Acceptable for v1; revisit if users complain or a screenshot flow needs deterministic rendering.
- **Heritage / night mapping is opinionated.** Easy to revise — single const set in `ticket_style_for_event.dart`. Considered driving it from the backend `circuit` table (`style: text`) but YAGNI for now.
- **`TicketCard` removal in a single release** could break a forgotten call site. The compat re-export lives in `ticket_card_compat.dart`; CI lint should flag any lingering import after migration. (No CI yet — mitigation is a final grep before deleting.)
