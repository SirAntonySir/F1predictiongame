# Backfilling the 2025 season into The Box — production runbook

`src/scripts/backfillSeason.ts` loads a full past season into the same database
the app uses, end to end:

1. 2025 events / sessions / results / driver+constructor standings from the F1
   API (Jolpica + OpenF1),
2. The Box's 2025 picks from the Excel sheet,
3. the after-season subjective truth (surprise = Sauber / Hadjar, disappointment
   = Alpine / Hamilton),
4. canonical scoring of every session + the preseason.

It is **additive, idempotent, and current-season-safe**: it never deletes, it
upserts the 2025 season with `is_current = false` (2026 stays current), and
re-running is safe (upserts / replace-for-session).

## Identity mapping

- **Julius** (2025 sheet) → the existing **Juli** account
- **Manu** → a **new** account is created and added to The Box
- the other ten match by display name

The dry run prints the resolved mapping against the *live* accounts — review it
before applying. One pick list is intentionally skipped: Julius's Belgium sprint
(he entered only 2 of 3 places; the canonical engine scores complete sets only).

## Prerequisites

- The sheet at `~/Downloads/Tippspiel-25.xlsx` (or pass another path).
- The **production** `DATABASE_URL` (Render → `f1pg-db` → connection string).
- `cd backend && npm ci`.

The script talks to the DB directly — it does not need the deployed server, so
you can run it locally against the prod connection string.

## Step 1 — dry run (no writes)

```bash
cd backend
DATABASE_URL='<PROD_DATABASE_URL>' NODE_ENV=production \
  npx tsx src/scripts/backfillSeason.ts 2025 ~/Downloads/Tippspiel-25.xlsx --dry-run
```

Confirm in the output:
- `League "The Box" in DB: yes`
- the name → account mapping (Manu = NEW, Julius → Juli EXISTING, the rest EXISTING)
- `Predictions to import: 567 complete · 1 partial (skipped)`

## Step 2 — apply

```bash
cd backend
DATABASE_URL='<PROD_DATABASE_URL>' NODE_ENV=production \
  npx tsx src/scripts/backfillSeason.ts 2025 ~/Downloads/Tippspiel-25.xlsx
```

Expected (matches the dev run): `events=24 sessions=120 finished=60 … predictions=567 … sessionsRescored=60`.

## Step 3 — verify

2025 weekend totals should match the audit:

| Lukas | Jan | Simon | Janine | Juli | Jana | Anton | Jonas | Jakob | David | Manu | Merlin |
|------:|----:|------:|-------:|-----:|-----:|------:|------:|------:|------:|-----:|-------:|
| 323   | 316 | 303   | 287    | 284  | 278  | 252   | 228   | 205   | 170   | 48   | 48     |

Via the API (after deploy): `GET /api/seasons` lists 2025;
`GET /api/standings/drivers?season=2025` → NOR / VER / PIA on top; in the app,
Standings → the season pill → 2025.

## Deploy

- Deploy the backend (new `?season` params + `GET /api/seasons`).
- Ship the app build (season switcher in Standings).
- 2026 stays the current season throughout.

## Rollback

Additive only. To remove the season entirely:

```sql
DELETE FROM season WHERE year = 2025;
```

FK `ON DELETE CASCADE` removes all 2025 events, sessions, results, standings,
predictions, preseason picks and scores. The new **Manu** account and its league
membership are not season-scoped and remain — delete them by hand if desired.
