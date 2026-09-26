ALTER TABLE "session" ADD COLUMN "jokers_applied_at" timestamp with time zone;--> statement-breakpoint
-- Backfill: mark already-locked race sessions as applied so the joker pass
-- only ever fires for races that lock after this migration ran. Without this,
-- deploying would retroactively spend jokers on every past race.
UPDATE "session" SET "jokers_applied_at" = "scheduled_start"
WHERE "type" = 'race' AND "scheduled_start" <= now();