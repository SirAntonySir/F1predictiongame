# Calendar: highlight the live event, move NEXT forward

**Date:** 2026-06-07
**Status:** Approved (Approach A)

## Problem

`calendar_screen.dart` only ever assigns `RaceState.past / next / future`
([calendar_screen.dart:131-138](../../../lib/screens/calendar_screen.dart)) —
it never marks an in-progress event as live. So during a race weekend the
current event shows as `past` (its race start is behind `now`) and `NEXT`
already points at the following round, with no "live" indication.

`RaceTile` **already renders** `RaceState.live` (red LIVE badge + red stripe,
[race_tile.dart:8,39,126](../../../lib/components/race_tile.dart)). The gap is
purely the calendar's selection logic.

## Goal

While an event's weekend is underway, mark it `RaceState.live` and keep `NEXT`
on the next not-yet-started event. The screen also auto-scrolls to the live
event (instead of past it to NEXT).

## Definition of "live": whole race weekend

For each event, weekend window = `[min(session.scheduledStart), max(session.scheduledEnd))`.
`max(end)` equals the race end (race is the last session). Verified against
real data (Monaco: FP1 11:30 → race end 15:00).

Per event vs `now`:
- `now` in `[start, end)` → **live**
- `now < start` (not started) and earliest such event → **next**; other not-started → **future**
- `now >= end` (race ended) → **past**

A live event's weekend has already started, so it is never a "next" candidate —
`NEXT` therefore lands on the earliest not-yet-started event automatically, i.e.
moves past the live one. Holds all weekend (during Saturday qualifying the event
is live and the following round is next).

## Approach A — pure classifier in domain

### 1. New `lib/domain/race_phase.dart`
- Move `enum RaceState { past, next, live, future }` here (was in `race_tile.dart`).
- Add pure:
  ```dart
  Map<int, RaceState> classifyCalendar(List<Event> events, DateTime now)
  ```
  keyed by `event.round`, implementing the windows above. At most one live event
  is assumed (weekends don't overlap); if several match, the last wins.

### 2. `lib/components/race_tile.dart`
Import `RaceState` from `../domain/race_phase.dart`; drop the local enum.
No widget change.

### 3. `lib/screens/calendar_screen.dart`
- Replace the inline `firstFutureRound` + state branching with a single
  `classifyCalendar(events, now)` call; look up each tile's state by round.
- Auto-scroll target: the live round if present, else the next round (so the
  list lands on the live event rather than scrolling past it).

## Tests (test-first) — `classifyCalendar`

- During the race → that event `live`, following event `next`, prior `past`.
- During Saturday qualifying (race still future) → still `live`, next advanced
  to the following event (the key whole-weekend case).
- Before the weekend starts → that event `next`, no live.
- After the race ends, before next weekend → `past` + following `next`.
- All events in the future → earliest is `next`, rest `future`.

## Out of scope

- Any change to `RaceTile`'s visuals (already done).
- A "live" indicator anywhere other than the calendar.
- Backend changes.
