# Design — Tippspiel Excel Import (Saison-Validierung)

**Status:** Draft, awaiting user review
**Date:** 2026-05-26
**Author:** Anton + Claude

## Ziel

Die laufenden Tipps aus `Tippspiel.xlsx` als Datensatz in die Backend-Datenbank einspielen, damit Anton in der App die in der Excel berechneten Punkte gegen die in der App-Scoring-Engine berechneten Punkte vergleichen kann. Dient der Validierung der Scoring-Engine.

Out of scope:
- Produktiver Datenimport für echte User
- Backfill der `score`-Tabelle für Wettbewerbszwecke
- Excel-Schreibzugriff oder kontinuierliche Synchronisation
- Hinzufügen neuer Preseason-Kategorien zum Schema (z.B. „meiste Rennsiege" — siehe Mapping)

## Quellformat (Tippspiel.xlsx)

Ein Sheet: **„Tippspiel 2026"**, 151 Zeilen × 147 Spalten.

Drei logische Blöcke:

1. **Summary-Tabelle** (Zeilen 7–17, Spalte A = Name, Spalten C..Z = 24 Rennen, Spalte AA = Season Points, Spalte AC = WE Points). Nur für visuelle Vergleichsbasis, nicht direkt importiert (Punkte werden vom Skript neu berechnet).
2. **Preseason-Block**
   - Einzel-Kategorien (Zeilen 4–17, Spalten AI..BB): Team + Fahrer für 7 Kategorien
   - Standings-Rankings (Zeilen 30–54, je Spieler 4 Spalten: Teams, gap, Drivers, gap)
3. **Per-Race-Block** (Zeilen 68–151): 11 Spieler-Blöcke + ein „Korrekt"-Block. Jeder Block über 24 Rennen × 6 Spalten:
   - Quali-Zeile: offset 0,1 = P1, P2 (2 picks)
   - Sprint-Zeile: offset 0 = sprint_quali P1; offsets 2,3,4 = sprint race P1..P3
   - Race-Zeile: offsets 0..4 = race P1..P5
   - Offset 5: Excel-berechnete Punkte für diese Zeile

## DB-Schema (relevant)

Bereits vorhanden, nicht zu ändern:

- `user(id, email, password_hash, display_name, ...)`
- `league(id, owner_user_id, name, join_code)` + `league_member(league_id, user_id)`
- `season(year, is_current)`, `event(id, season_year, round, name, has_sprint)`, `session(id, event_id, type, ...)`
- `driver(code, ...)` mit 22 Codes (uppercase 3-letter)
- `constructor(id, name, ...)` mit 11 IDs (snake_case)
- `prediction(id, user_id, session_id)` + `prediction_pick(prediction_id, position, driver_code)`
- `preseason_pick(user_id, season_year, category, driver_code, constructor_id)`
- `preseason_pick_standings_driver(user_id, season_year, position, driver_code)`
- `preseason_pick_standings_constructor(user_id, season_year, position, constructor_id)`
- `score(user_id, session_id, points_total, breakdown, ...)`

DB hat 22 Events für 2026 (Bahrain + Saudi sind im Kalender, aber **nicht** in der DB — Excel-Picks für diese Rennen sind durchgängig ` --- ` und werden übersprungen).

## Architektur

**Skript:** `backend/src/scripts/importTippspiel.ts`
**Run:** `npm run import:tippspiel -- [pfad/zur/xlsx]` (default `~/Downloads/Tippspiel.xlsx`)
**Dependency:** `xlsx` (SheetJS) als `devDependency` in `backend/package.json`.

Operationsreihenfolge (jede Transaktions-Grenze bewahrt Konsistenz):

1. **Excel parsen** in In-Memory-Structs (`ParsedSeason`).
2. **Mapping-Validierung** (Driver-Codes, Constructor-IDs, Event-Namen) — bricht bei unbekannten Werten ab, bevor irgendwas geschrieben wird.
3. **User upsert**: 11 Test-User per Email-Lookup; existierende behalten Passwort & UUID, fehlende werden mit bcrypt-Hash von `tippspiel-test` angelegt.
4. **Liga upsert**: „Tippspiel 2026 Validation", owner = Anton-User, Join-Code = `TIPP-2026`. Find-by-name; falls Liga existiert, wird sie wiederverwendet (Owner-Update entfällt). Falls Liga nicht existiert UND Anton bereits eine andere Liga ownt (`league_owner_uq` constraint), bricht das Skript mit klarer Meldung ab. Membership: alle 11 User per insert-ignore-on-conflict.
5. **Preseason-Standings** je User: `replaceConstructorPicks(user, 2026, 11 picks)` + `replaceDriverPicks(user, 2026, 22 picks)`.
6. **Preseason-Einzel-Kategorien** je User × Kategorie: `upsertPick(user, 2026, cat, {driver_code, constructor_id})`. „meiste Rennsiege" wird übersprungen.
7. **Per-Race-Picks**: für jedes (User × Event × SessionType):
   - Event nicht in DB → skip
   - Sprint-Session aber `has_sprint=false` → skip
   - Zelle ` --- ` oder komplett leer → skip ganze Session
   - Sonst: `upsertPredictionWithPicks(user, session.id, picks)`
8. **Rescore**: für jede Session mit existierenden `session_result`-Zeilen `rescoreSession(sessionId)` aufrufen → füllt `score`-Tabelle.
9. **Validierung-Output**: Excel-Punkte vs. App-Punkte als Tabelle ins Terminal.

## Mapping

### User (Excel-Name → Email)

```
Jan, Lukas, Jakob, Simon, Juli, Jonas, Janine, Jana, Anton, David, Merlin
→ <lowercase>@tippspiel.test, displayName = Excel-Name
```

Passwort-Hash für alle: bcrypt(`tippspiel-test`).
Anton-User ist Owner der Test-Liga.

### Constructor (Excel → `constructor.id`)

```
McLaren      → mclaren
Merc         → mercedes
Ferrari      → ferrari
RedBull      → red_bull
Alpine       → alpine
Haas         → haas
Vcarb        → rb
Audi         → audi
Williams     → williams
Cadillac     → cadillac
Aston        → aston_martin
Aston Martin → aston_martin
```

### Driver (Excel 3-letter mixed case → `driver.code`)

Regel: `code.toUpperCase()`, mit Sonderfall `Hulk → HUL`.

Vollständige Liste (zur Validierung): VER, NOR, RUS, PIA, LEC, HAD, ANT, HAM, GAS, BEA, OCO, LIN, ALB, BOR, COL, LAW, HUL, SAI, BOT, PER, ALO, STR.

### Event (Excel-Spaltenkopf → DB-event.name)

Beibehaltung der DB-Round-Numbers nicht garantiert (DB-Round 5 = Kanada, Excel-Position 7 = Kanada). Mapping per Name:

```
Australia  → Australian Grand Prix
China      → Chinese Grand Prix
Japan      → Japanese Grand Prix
Bahrain    → SKIP (nicht in DB)
Saudi      → SKIP (nicht in DB)
Miami      → Miami Grand Prix
Kanada     → Canadian Grand Prix
Monaco     → Monaco Grand Prix
Barcelona  → Barcelona Grand Prix
Österreich → Austrian Grand Prix
GB         → British Grand Prix
Belgien    → Belgian Grand Prix
Ungarn     → Hungarian Grand Prix
Niederlande→ Dutch Grand Prix
Italien    → Italian Grand Prix
Spanien    → Spanish Grand Prix
Baku       → Azerbaijan Grand Prix
Singapur   → Singapore Grand Prix
USA        → United States Grand Prix
Mexiko     → Mexico City Grand Prix
Brasilien  → Brazilian Grand Prix
Las Vegas  → Las Vegas Grand Prix
Katar      → Qatar Grand Prix
Abu Dhabi  → Abu Dhabi Grand Prix
```

### Preseason-Kategorie (Excel → DB enum)

```
größte Enttäuschung → disappointment   (col 35 Team, col 36 Fahrer)
größte Überraschung → surprise         (col 38 Team, col 39 Fahrer)
meiste DNFs         → dnf              (col 41 Team, col 42 Fahrer)
meiste Poles        → poles            (col 44 Team, col 45 Fahrer)
meiste fastest laps → fastest_lap      (col 47 Team, col 48 Fahrer)
meiste Rennsiege    → SKIP (Schema hat diese Kategorie nicht)
Champions WCC / WDC → wdc_wcc          (col 53 WCC→constructor_id, col 54 WDC→driver_code)
```

## Parsing-Logik

Reine Lesefunktionen mit harten Layout-Konstanten:

```ts
const RACE_HEADER_ROW          = 4
const RACE_START_COL           = 3
const RACE_COLS_EACH           = 6
const STANDINGS_HEADER_ROW     = 30
const STANDINGS_FIRST_DATA_ROW = 33
const STANDINGS_COLS_PER_PLAYER= 4
const STANDINGS_FIRST_TEAMS_COL= 3
const PRESEASON_SINGLE_ROW_START = 7  // Jan; +1 per player
```

`PLAYER_BLOCKS` als hartkodiertes Array von `{ name, qualiRow, sprintRow, raceRow }` mit 7-Zeilen-Stride beginnend bei Jan = R72.

### Skip-Regeln pro Pick-Zelle

- `null` / leerer String → kein Pick
- ` --- ` (führendes Leerzeichen, drei Bindestriche) → kein Pick
- Wenn eine Session in der DB nicht existiert (Bahrain, Saudi) → ganze Session-Zelle übersprungen
- Sprint-Zeile bei `has_sprint=false`-Event → komplett übersprungen. Wenn die Sprint-Zeile dabei aber tatsächlich Daten enthält (nicht alle leer/` --- `), bricht das Skript mit Fehler ab (Daten-Inkonsistenz: Excel hat Sprint-Pick für Event ohne Sprint).

### Abbruch-Fälle (Skript stoppt mit Fehlermeldung, bevor irgendwas geschrieben wird)

- Driver-Kürzel nicht im Mapping (Tippfehler im Excel)
- Constructor-Name nicht im Mapping
- Event-Name nicht im Mapping (außer Bahrain/Saudi, die explizit SKIP sind)
- Unvollständige Pick-Anzahl bei vorhandenen Daten (z.B. Quali hat 1 von 2, ohne ` --- `)
- Duplikat-Driver in derselben Pick-Liste (z.B. P1=RUS, P2=RUS)

## Validierungs-Output

Am Ende des Skripts:

1. **Excel-Punkte** pro User × Event = Summe der drei Punktewerte aus Quali/Sprint/Race-Zeilen (offset 5).
2. **App-Punkte** pro User × Event = SUM(`score.points_total`) über alle Sessions eines Events. Für Sessions ohne Ergebnisse (`session_result` leer) existiert kein Score-Eintrag → App-Punkte für dieses Event werden mit `n/a` markiert (kein Mismatch, da keine Berechnung möglich).
3. **Tabelle ins Terminal**:

```
=== Validation: Excel vs. App ===
                Australia  China  Japan  Bahrain  Saudi  Miami   …   Σ Excel  Σ App  Δ
Jan              13/13     13/13  12/12   skip    skip   18/18        56       56     0
Lukas            16/16     16/16  11/11   skip    skip   14/14        57       57     0
…
Total mismatches: 0
```

`Δ ≠ 0` markiert (z.B. ANSI rot, sofern TTY).
Bei Mismatches: zusätzliche Detail-Tabelle mit Session-ID, Picks, Result, errechneter Breakdown.
Exit-Code: 0 bei keinem Mismatch, 1 sonst.

## Idempotenz

- User: find-by-email, sonst insert. UUIDs bleiben stabil über Re-Runs.
- Liga: find-by-name, sonst insert. Membership: insert ignore.
- Preseason-Standings: vollständiges Replace (delete + insert in einer TX).
- Preseason-Einzelpicks: `upsertPick` (existierendes Repo macht `ON CONFLICT DO UPDATE`).
- Predictions: `upsertPredictionWithPicks` (existierendes Repo, atomar).
- Scores: `rescoreSession` (existierendes Repo, atomar pro Session).

Re-Run mit demselben Excel ist no-op. Re-Run mit aktualisiertem Excel überschreibt Picks; gelöschte Picks aus dem Excel bleiben in der DB stehen, weil die Predictions per Session-ID upserted werden und nicht alle für einen User pauschal gelöscht werden. Akzeptables Trade-off für ein Dev-Tool.

## Unit Tests

`backend/test/scripts/importTippspiel.test.ts`:

- Driver-Mapping (uppercase + Hulk)
- Constructor-Mapping
- Event-Skip-Set (Bahrain/Saudi)
- Skip-Regel für ` --- `
- Sprint-Skip bei `has_sprint=false`
- Fehler bei unbekanntem Code
- Fehler bei unvollständigem Pick-Set
- Fehler bei Duplikat-Driver in Pick-Liste
- Roundtrip eines Mini-Sheets (in-memory xlsx-Workbook erzeugen, parsen, gegen Erwartung assert)

Integrationstests gegen die echte DB sind nicht Teil dieser Spec — der Validierungs-Output **ist** der Integrationstest (`npm run import:tippspiel` muss „Total mismatches: 0" zeigen, sobald die Crawler-Ergebnisse für die abgeschlossenen Rennen vorliegen).

## Risiken & Annahmen

- **Excel-Layout** ist hartkodiert. Wenn Anton Spalten/Zeilen einfügt, bricht der Import. Akzeptabel, da Excel statisch.
- **`xlsx`-Package** hat Sicherheitswarnungen historisch — als `devDependency` für ein lokales Dev-Tool unproblematisch.
- **Anton-User** ist Liga-Owner. Wenn ein anderer User später dieselbe Liga ownen soll, müsste die Liga manuell migriert werden (akzeptabel für Test-Daten).
- **Scoring-Diskrepanzen** sind erwartet, wenn die Crawler-Ergebnisse von den Excel-„Korrekt"-Werten abweichen. Genau das ist der Sinn des Vergleichs.
- **Bahrain/Saudi** könnten später nachgepflegt werden (Crawler oder manuell). Mapping muss dann erweitert werden — derzeit explizit SKIP statt Fehler.
