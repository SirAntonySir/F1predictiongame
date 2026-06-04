# Font Awesome iconography — gossip, stats, locks, password reveal

**Date:** 2026-06-04
**Status:** Design — awaiting approval

## Goal

Adopt **Font Awesome** (monochrome, minimal) as the icon set for the League Gossip
feed and a handful of adjacent surfaces, replacing the current mix of unicode/emoji
glyphs (`🏆 ✗ ✕ ↑ ↓ ★ ≈ ?`) and Material lock icons. Also add a password
**show/hide** toggle, which does not exist today.

## Non-goals

- Not a wholesale Material-icon migration. Navigation chevrons, `close`, `copy`,
  `edit`, `search`, etc. stay Material. Scope is the gossip feed + the named
  stat / countdown / lock / password targets only.
- No colour icons or emoji retained anywhere in the swapped surfaces.

## Dependency

Add `font_awesome_flutter` to `pubspec.yaml` (latest compatible with Dart `^3.5.4`;
exact version resolved at install).

## Rendering convention

- New code renders via `FaIcon(glyph, size: …, color: …)`.
- Modern `font_awesome_flutter` `IconData` carries its own `fontFamily`/`fontPackage`,
  so **existing** `Icon(...)` / `_ActionPill(icon:)` sites can take an FA constant
  directly. Switch those to `FaIcon` only if the installed version needs it —
  `flutter analyze` + a visual pass are the safety net.
- The **FA glyphs below (by CSS class) are the source of truth.** Exact Dart symbol
  names (solid vs regular prefixing; `fa-1` → numeral constant) are resolved against
  the installed package and verified by `flutter analyze`.

## Mapping

15 distinct FA glyphs (your 12 selections — the duplicate `fa-angle-up` collapses to
one — plus `fa-lock`, `fa-lock-open`, `fa-eye`, `fa-eye-slash`; `fa-clock` is reused
across two surfaces).

### Gossip feed — `insights_tab.dart` `_Fact` sites + `FactCard` + `_h` header
| Line (current glyph) | Glyph |
|---|---|
| `LEAGUE GOSSIP` header | `fa-comments` *(regular)* |
| 🏆 Best player topped the race | `fa-flag-checkered` |
| ★ Leads the league | `fa-1` |
| ≈ Gap between 1st & 2nd | `fa-angle-up` |
| ↑ Driver = league's best call | `fa-angles-up` |
| ↓ Driver cost the league | `fa-angles-down` |
| ✗ Worst / finished last | `fa-xmark` |
| ✕ No-show / forgot to pick | `fa-clock` *(regular)* |
| ? Empty state | `fa-info` |

### YOUR SEASON tiles — `_stat`
| Tile | Glyph |
|---|---|
| `HIT RATE` | `fa-check` |
| `PRESEASON Δ` (projection) | `fa-chart-line` |

### Tipping screen — `Countdown`
| Target | Glyph |
|---|---|
| Live countdown | `fa-clock` *(regular, reused)* |

### Locks
| Site | Today | Glyph |
|---|---|---|
| `settings_screen.dart:500` league-password badge | `lock` / `lock_open_outlined` | `fa-lock` / `fa-lock-open` |
| `settings_screen.dart:167` "Password-protected" | `lock_outline` | `fa-lock` |
| `predict_screen.dart:379` "LOCK PICK" pill | `lock_outline` | `fa-lock` |

### Password reveal (new behavior)
| Field | Glyph |
|---|---|
| All obscured password inputs | `fa-eye` / `fa-eye-slash` *(solid)* |

## Component changes

1. **`pubspec.yaml`** — add `font_awesome_flutter`.
2. **`lib/components/fact_card.dart`** — `emblem` `String` → `IconData`; render
   `FaIcon(emblem, size: 15, color: Colors.white)` inside the black chip instead of `Text`.
3. **`lib/screens/standings/insights_tab.dart`**
   - 8 `_Fact(...)` call sites: glyph strings → `FontAwesomeIcons.*` per the table.
   - `_h()` — add optional `IconData? icon`; render a leading `FaIcon` only on the
     `LEAGUE GOSSIP` header (`fa-comments`). Other `_h` headers unchanged.
   - `_stat()` — add optional `IconData? icon`; used on `HIT RATE` (`fa-check`) and
     `PRESEASON Δ` (`fa-chart-line`). The other 6 tiles pass nothing and are unchanged.
4. **`lib/components/countdown.dart`** — add an opt-in leading-icon flag (default
   **off**, so home / preseason / session-results / card usages stay identical);
   render `FaIcon(fa-clock)` when enabled.
5. **`lib/screens/predict_screen.dart`** — enable the countdown clock; `LOCK PICK`
   `_ActionPill` icon → `fa-lock`.
6. **`lib/screens/settings_screen.dart`** — two lock `Icon` sites → `fa-lock` /
   `fa-lock-open`; the Set/Change league-password `AlertDialog` (already stateful)
   gains a `_reveal` flag + `fa-eye` / `fa-eye-slash` `suffixIcon`.
7. **`lib/components/branded_field.dart`** — convert `StatelessWidget` →
   `StatefulWidget`; hold a `_reveal` flag; when `obscure: true`, render a tappable
   `fa-eye` / `fa-eye-slash` suffix tinted to `boxText` that toggles `obscureText`.
   This auto-covers signup, league join/create, and change-password fields.

## Decisions & caveats

- **`fa-clock` reused** for the no-show gossip line and the Tipping countdown —
  both are deadline/time semantics. Intentional.
- The original glyph list contained **`fa-angle-up` twice**; treated as a paste
  duplicate and used once (the gap line). Not placed elsewhere.
- **Eye style:** solid `fa-eye` / `fa-eye-slash` for legibility at small sizes.

## Verification

- `flutter analyze` clean.
- Run the app and visually confirm: Insights (gossip chips + `HIT RATE` / `PRESEASON Δ`
  tiles), Tipping (countdown clock + `LOCK PICK`), an auth screen (eye toggle reveals/hides),
  Settings (lock badges + password-dialog eye).
