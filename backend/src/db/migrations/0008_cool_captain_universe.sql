CREATE TABLE "session_best_lap" (
	"session_id" integer NOT NULL,
	"driver_code" text NOT NULL,
	"lap_ms" integer NOT NULL,
	"s1_ms" integer,
	"s2_ms" integer,
	"s3_ms" integer,
	"lap_number" integer,
	"computed_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "session_best_lap_session_id_driver_code_pk" PRIMARY KEY("session_id","driver_code")
);
--> statement-breakpoint
ALTER TABLE "session_best_lap" ADD CONSTRAINT "session_best_lap_session_id_session_id_fk" FOREIGN KEY ("session_id") REFERENCES "public"."session"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "session_best_lap" ADD CONSTRAINT "session_best_lap_driver_code_driver_code_fk" FOREIGN KEY ("driver_code") REFERENCES "public"."driver"("code") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "session_best_lap_session_idx" ON "session_best_lap" USING btree ("session_id");