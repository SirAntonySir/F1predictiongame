CREATE TYPE "public"."preseason_category" AS ENUM('surprise', 'disappointment', 'dnf', 'poles', 'fastest_lap', 'wdc_wcc');--> statement-breakpoint
CREATE TABLE "preseason_pick" (
	"user_id" uuid NOT NULL,
	"season_year" integer NOT NULL,
	"category" "preseason_category" NOT NULL,
	"driver_code" text,
	"constructor_id" text,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "preseason_pick_pk" PRIMARY KEY ("user_id", "season_year", "category"),
	CONSTRAINT "preseason_pick_user_fk" FOREIGN KEY ("user_id") REFERENCES "user"("id") ON DELETE CASCADE,
	CONSTRAINT "preseason_pick_season_fk" FOREIGN KEY ("season_year") REFERENCES "season"("year") ON DELETE CASCADE,
	CONSTRAINT "preseason_pick_driver_fk" FOREIGN KEY ("driver_code") REFERENCES "driver"("code"),
	CONSTRAINT "preseason_pick_constructor_fk" FOREIGN KEY ("constructor_id") REFERENCES "constructor"("id")
);
--> statement-breakpoint
CREATE INDEX "preseason_pick_season_category_idx" ON "preseason_pick" ("season_year", "category");--> statement-breakpoint
CREATE TABLE "preseason_pick_standings_driver" (
	"user_id" uuid NOT NULL,
	"season_year" integer NOT NULL,
	"position" integer NOT NULL,
	"driver_code" text NOT NULL,
	CONSTRAINT "preseason_psd_pk" PRIMARY KEY ("user_id", "season_year", "position"),
	CONSTRAINT "preseason_psd_user_fk" FOREIGN KEY ("user_id") REFERENCES "user"("id") ON DELETE CASCADE,
	CONSTRAINT "preseason_psd_season_fk" FOREIGN KEY ("season_year") REFERENCES "season"("year") ON DELETE CASCADE,
	CONSTRAINT "preseason_psd_driver_fk" FOREIGN KEY ("driver_code") REFERENCES "driver"("code")
);
--> statement-breakpoint
CREATE UNIQUE INDEX "preseason_psd_driver_uq" ON "preseason_pick_standings_driver" ("user_id", "season_year", "driver_code");--> statement-breakpoint
CREATE INDEX "preseason_psd_season_idx" ON "preseason_pick_standings_driver" ("season_year");--> statement-breakpoint
CREATE TABLE "preseason_pick_standings_constructor" (
	"user_id" uuid NOT NULL,
	"season_year" integer NOT NULL,
	"position" integer NOT NULL,
	"constructor_id" text NOT NULL,
	CONSTRAINT "preseason_psc_pk" PRIMARY KEY ("user_id", "season_year", "position"),
	CONSTRAINT "preseason_psc_user_fk" FOREIGN KEY ("user_id") REFERENCES "user"("id") ON DELETE CASCADE,
	CONSTRAINT "preseason_psc_season_fk" FOREIGN KEY ("season_year") REFERENCES "season"("year") ON DELETE CASCADE,
	CONSTRAINT "preseason_psc_constructor_fk" FOREIGN KEY ("constructor_id") REFERENCES "constructor"("id")
);
--> statement-breakpoint
CREATE UNIQUE INDEX "preseason_psc_constructor_uq" ON "preseason_pick_standings_constructor" ("user_id", "season_year", "constructor_id");--> statement-breakpoint
CREATE INDEX "preseason_psc_season_idx" ON "preseason_pick_standings_constructor" ("season_year");--> statement-breakpoint
CREATE TABLE "subjective_truth" (
	"season_year" integer PRIMARY KEY NOT NULL,
	"surprise_driver_code" text,
	"surprise_constructor_id" text,
	"disappointment_driver_code" text,
	"disappointment_constructor_id" text,
	"set_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "subjective_truth_season_fk" FOREIGN KEY ("season_year") REFERENCES "season"("year") ON DELETE CASCADE,
	CONSTRAINT "subjective_truth_sdriver_fk" FOREIGN KEY ("surprise_driver_code") REFERENCES "driver"("code"),
	CONSTRAINT "subjective_truth_sctor_fk" FOREIGN KEY ("surprise_constructor_id") REFERENCES "constructor"("id"),
	CONSTRAINT "subjective_truth_ddriver_fk" FOREIGN KEY ("disappointment_driver_code") REFERENCES "driver"("code"),
	CONSTRAINT "subjective_truth_dctor_fk" FOREIGN KEY ("disappointment_constructor_id") REFERENCES "constructor"("id")
);
--> statement-breakpoint
ALTER TABLE "score" ADD COLUMN "kind" text NOT NULL DEFAULT 'session';--> statement-breakpoint
ALTER TABLE "score" ADD COLUMN "season_year" integer;--> statement-breakpoint
ALTER TABLE "score" ADD COLUMN "preseason_category" text;--> statement-breakpoint
ALTER TABLE "score" ADD CONSTRAINT "score_seasonyear_fk" FOREIGN KEY ("season_year") REFERENCES "season"("year") ON DELETE CASCADE;--> statement-breakpoint
ALTER TABLE "score" DROP CONSTRAINT "score_pk";--> statement-breakpoint
ALTER TABLE "score" ALTER COLUMN "session_id" DROP NOT NULL;--> statement-breakpoint
CREATE UNIQUE INDEX "score_session_uq" ON "score" ("user_id", "session_id") WHERE kind = 'session';--> statement-breakpoint
CREATE UNIQUE INDEX "score_preseason_uq" ON "score" ("user_id", "season_year", "preseason_category") WHERE kind = 'preseason';
