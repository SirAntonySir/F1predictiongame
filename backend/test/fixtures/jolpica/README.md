# Jolpica fixtures

Captured 2026-05-25 from https://api.jolpi.ca/ergast/f1.
Re-capture by running the curl commands in Task 8 of the data-foundation plan.

## Files

| File | Endpoint | Notes |
|------|----------|-------|
| schedule-2024.json | /f1/2024.json | Full 2024 calendar (24 races) |
| race-2024-1.json | /f1/2024/1/results.json | Bahrain GP results |
| qualifying-2024-1.json | /f1/2024/1/qualifying.json | Bahrain GP qualifying |
| sprint-2024-5.json | /f1/2024/5/sprint.json | Chinese GP sprint results (round 5) |
| driver-standings-2024.json | /f1/2024/driverStandings.json | End-of-season driver standings |
| constructor-standings-2024.json | /f1/2024/constructorStandings.json | End-of-season constructor standings |
| sprint-quali-2024-5.json | /f1/2024/5/sprintQualifying.json | See "Sprint Qualifying" below |

The 2024 season had sprint weekends at rounds 5 (China), 6 (Miami), 11 (Austria), 19 (USA), 21 (São Paulo), 23 (Qatar). Round 5 (China) was the first.

## Sprint Qualifying endpoint

Probed 2026-05-25. Result: **HTTP 400** with body `{"detail":"Bad Request: Endpoint does not support final filter."}` for round 5 (and also probed at the season scope `/f1/2024/sprintQualifying.json` and `/f1/2024/5/sprint_qualifying.json` — same response).

Jolpica does not expose Sprint Qualifying as a distinct endpoint. The crawler must no-op gracefully on this session type until a source becomes available; see `src/crawler/tick.ts` (Task 16) and `src/repo/sessions.ts.listCandidates` (Task 12) for how this is handled (7-day cap on retries). Treat HTTP 400/404 from this endpoint as "no data available" rather than a fatal error.
