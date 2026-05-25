CREATE TABLE "prediction" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" uuid NOT NULL,
	"session_id" integer NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "prediction_user_fk" FOREIGN KEY ("user_id") REFERENCES "user"("id") ON DELETE CASCADE,
	CONSTRAINT "prediction_session_fk" FOREIGN KEY ("session_id") REFERENCES "session"("id") ON DELETE CASCADE
);
--> statement-breakpoint
CREATE UNIQUE INDEX "prediction_user_session_uq" ON "prediction" ("user_id", "session_id");--> statement-breakpoint
CREATE INDEX "prediction_session_idx" ON "prediction" ("session_id");--> statement-breakpoint
CREATE TABLE "prediction_pick" (
	"prediction_id" uuid NOT NULL,
	"position" integer NOT NULL,
	"driver_code" text NOT NULL,
	CONSTRAINT "prediction_pick_pk" PRIMARY KEY ("prediction_id", "position"),
	CONSTRAINT "prediction_pick_prediction_fk" FOREIGN KEY ("prediction_id") REFERENCES "prediction"("id") ON DELETE CASCADE,
	CONSTRAINT "prediction_pick_driver_fk" FOREIGN KEY ("driver_code") REFERENCES "driver"("code")
);
--> statement-breakpoint
CREATE INDEX "prediction_pick_driver_idx" ON "prediction_pick" ("driver_code");--> statement-breakpoint
CREATE TABLE "score" (
	"user_id" uuid NOT NULL,
	"session_id" integer NOT NULL,
	"points_total" integer NOT NULL,
	"breakdown" jsonb NOT NULL,
	"computed_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "score_pk" PRIMARY KEY ("user_id", "session_id"),
	CONSTRAINT "score_user_fk" FOREIGN KEY ("user_id") REFERENCES "user"("id") ON DELETE CASCADE,
	CONSTRAINT "score_session_fk" FOREIGN KEY ("session_id") REFERENCES "session"("id") ON DELETE CASCADE
);
--> statement-breakpoint
CREATE INDEX "score_session_idx" ON "score" ("session_id");--> statement-breakpoint
CREATE INDEX "score_user_idx" ON "score" ("user_id");
