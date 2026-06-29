# Weekend Souvenir Ticket — Design Spec

**Date:** 2026-06-29
**Status:** Approved

## Purpose

A full-GP souvenir card summarising a whole weekend's score, instead of one
ticket per session. Replaces the plain "Your weekend" recap `AppCard` in the
race-detail Full-GP view.

## Component — `WeekendSouvenirTicket`

`lib/components/ticket/weekend_souvenir_ticket.dart`. Built on `TicketRohling`,
mirroring `SouvenirTicket`'s shell (style-for-event, long title, circuit
watermark, illustration, edge serials) so it reads as a real souvenir.

- Inputs: `event` (Event), `sessions` (`List<({SessionType type, int points})>`,
  already in chronological order), `total` (int), `circuitWatermark` (Widget?),
  `onTap` (VoidCallback?), `onLongPress` (VoidCallback?).
- `dataRow`: one `TicketDataCell(label: shortLabel(type), value: '+$points')`
  per session, then a final `TicketDataCell(label: 'TOTAL', value: '+$total')`.
  Short labels: qualifying→`Q`, sprint_quali→`SQ`, sprint→`SPRINT`, race→`RACE`,
  fp1/2/3→uppercase name (won't normally appear).
- `leftEdgeSerial`: `'WEEKEND'`.
- Long-press → branded-PNG share (mirrors `SouvenirTicket._showActions` /
  `_shareDefault`: clone with `onLongPress: () {}`, `shareBrandedTicket`,
  shareText `My F1 weekend · {event} · +{total}`).

## Integration — Full-GP view (`session_results_screen.dart`)

In `_fullGpView`, replace the "Your weekend" recap `AppCard` (total + chips):
- When the user has scored sessions this weekend (`mine` non-empty): render
  `WeekendSouvenirTicket(event: event, sessions: [for s in mine (s.sessionType, s.pointsTotal)], total: myTotal, circuitWatermark: CircuitSvg(event: event))`.
- When `mine` is empty: keep the "No scored sessions this weekend yet." text.

`mine` is already sorted by `sessionScheduledStart` (chronological).

## Constraints / non-goals
- No backend changes; data from already-loaded `MyScore`s for the round.
- Calendar-wallet weekend souvenirs are out of scope (per-session wallet stays).

## Testing
- `flutter analyze` clean; existing tests stay green.
