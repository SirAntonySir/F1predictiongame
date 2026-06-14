ALTER TABLE "session_best_lap" DROP CONSTRAINT "session_best_lap_session_id_driver_code_pk";--> statement-breakpoint
ALTER TABLE "session_best_lap" ADD COLUMN "knockout" integer DEFAULT 0 NOT NULL;--> statement-breakpoint
ALTER TABLE "session_best_lap" ADD CONSTRAINT "session_best_lap_session_id_driver_code_knockout_pk" PRIMARY KEY("session_id","driver_code","knockout");