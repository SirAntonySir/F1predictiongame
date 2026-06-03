# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Flutter app (`pubspec.yaml` name: `predictiongame`) for an F1 prediction game. Currently a thin client over the public Ergast F1 API — no backend, no persistence, no auth. Prediction-related "user data" (leaderboards, selected predictions) is in-memory mock data only.

SDK: Dart `^3.5.4`. Single runtime dependency beyond Flutter is `http: ^0.13.3`.

## Commands

```bash
flutter pub get                          # install deps
flutter run                              # run on default device
flutter run -d chrome                    # web target (also: macos, ios, android, linux, windows)
flutter analyze                          # lints (flutter_lints via analysis_options.yaml)
flutter test                             # all tests
flutter test test/widget_test.dart       # single test file
flutter test --name "<substring>"        # filter by test name
```

Build targets are scaffolded for every platform Flutter supports (android, ios, web, macos, linux, windows). There is no CI configured.

## Architecture

Three-tab `BottomNavigationBar` shell in `lib/main.dart` → `HomeScreen`, kept alive via `IndexedStack`. Each tab is a self-contained screen that fetches its own data directly from Ergast on `initState`:

- `lib/Screens/prediction_input_screen.dart` — "Tipping" tab. Finds the next upcoming race in the current season, runs a 1Hz countdown timer, and lets the user pick a Top-1 / Top-2 driver. Selections are local state and are not submitted anywhere.
- `lib/Screens/live_table_screen.dart` — "Leaderboard" tab. Two sub-tabs: real driver standings from Ergast, and a **hardcoded mock prediction leaderboard** (Anton/Lukas/Simon/Paul/Peter). The mock is the only place prediction "scores" exist.
- `lib/Screens/live_data_screen.dart` — "Live Data" tab. Season/race/session-type dropdowns (results, qualifying, sprint where available). Sprint availability is detected by N parallel `GET /sprint.json` probes — touch this carefully, it's the only place that fans out requests.

Components in `lib/Components/` are presentation-only (`CountdownWidget`, `PredictionInputWidget`).

### Cross-cutting things to know

- **Ergast API** (`https://ergast.com/api/f1/...`) is the single data source. All HTTP lives inline in screen widgets — there is no service/repository layer. If you add a new data source or auth, that's the moment to introduce one.
- **Team color map** (`_teamColors`) is duplicated verbatim in three files. If you add/rename a team (e.g. `alphatauri` → `rb`, missing `kick_sauber`), update all three: `live_data_screen.dart`, `live_table_screen.dart`, `prediction_input_widget.dart`.
- **Race status** in `live_data_screen.dart` (`_getRaceStatus`) classifies a race as "live" for the 2 hours after its scheduled start — it's a heuristic, not a real session-state check.
- **No state management library** (no Provider/Riverpod/Bloc) — everything is `setState`. Don't introduce one casually; match the existing style unless the change actually requires it.
