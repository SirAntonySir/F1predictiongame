ALTER TABLE "session" ADD COLUMN "last_reconciled_at" timestamp with time zone;--> statement-breakpoint
ALTER TABLE "session_result" ADD COLUMN "source" text DEFAULT 'jolpica' NOT NULL;