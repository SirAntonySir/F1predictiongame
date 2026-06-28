# Admin Tool — Plan 7: Users & Predictions edit/delete

> REQUIRED SUB-SKILL: superpowers:executing-plans (inline).

**Goal:** Inline edit + delete for Users (name, email, set password, guarded delete) and Predictions (edit picks, delete). New token-gated backend write endpoints + frontend dialogs/confirms.

## Global Constraints
- Concurrency: file-scoped commits only. Backend ESM `.js`; `ApiError`; repo layer; token preHandler covers `/admin/*` (register on root app); integration tests (`local-dev-token`, `buildApp({scheduler:null})`, Postgres up). Frontend TS strict, build gate, no new deps, Radix Select/overlay tests need `<Theme>`.
- User FKs are mostly `onDelete: cascade` (incl. owned league), EXCEPT `prediction_import.uploadedBy` / `prediction.importedBy` (no cascade) → deleting a user who uploaded/imported fails; map that to a clear 409.

## Tasks

### Task 1 — Backend user writes
- `users.updateEmail(id, email)` repo fn.
- `adminUsers.ts` → register after `registerAdminLeagueRoutes`:
  - `PATCH /admin/users/:id` `{ displayName?(1..80), email?(email) }`: 404 if missing; if email taken by another user → 409; apply; return updated user.
  - `POST /admin/users/:id/set-password` `{ password(min 8) }`: hashPassword + updatePasswordHash; `{ ok }`.
  - `DELETE /admin/users/:id`: 404 if missing; `try deleteById catch → ApiError('CONFLICT', "Couldn't delete — user has protected records (e.g. uploaded imports). Reassign/remove those first.")`; `{ ok }`.
- Tests: token gate, rename+email, email-conflict 409, set-password, delete, delete-blocked-by-import 409, 404.

### Task 2 — Backend prediction writes
- `scores.deleteSessionScore(userId, sessionId)` repo fn (delete from score where user+session, kind='session').
- `adminPredictions.ts` → register:
  - `DELETE /admin/predictions/:userId/:sessionId`: `deleteByUserAndSession` + `deleteSessionScore` + `rescoreSession`; `{ ok, rescored }`.
  - `PUT /admin/predictions/:userId/:sessionId/picks` `{ picks: {position,driverCode}[] }`: 404 if session missing; positions contiguous 1..N + no dup drivers + each `driversRepo.exists`; `upsertPredictionWithPicks` + `rescoreSession`; `{ ok, rescored }`.
- Tests: token gate, edit picks (read back), delete (gone), unknown driver 422, bad positions 422.

### Task 3 — Frontend Users edit/delete
- `admin.ts`: `useUpdateUser(id)`, `useSetUserPassword(id)`, `useDeleteUser()` (invalidate `['admin-users']`, toast).
- `Users.tsx`: Actions column → **Edit** (dialog: name, email, set-password) + **Delete** (AlertDialog spelling out the cascade).
- Test: edit sends PATCH; delete confirm sends DELETE.

### Task 4 — Frontend Predictions edit/delete
- `admin.ts`: `useSavePrediction(sessionId)` (PUT picks), `useDeletePrediction(sessionId)` (DELETE); invalidate `['admin-predictions', sessionId]`, toast.
- `Predictions.tsx`: per-row **Edit** (dialog: a driverCode TextField per existing position) + **Delete** (confirm).
- Test: edit sends PUT with picks; delete confirm sends DELETE.

## Self-Review
- Destructive ops confirmed in UI; user-delete cascade mapped to a 409 when blocked; prediction delete cleans the score; edits rescore. Backend deploy required for the new endpoints.
