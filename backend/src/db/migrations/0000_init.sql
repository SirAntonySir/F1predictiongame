CREATE TYPE "public"."session_status" AS ENUM('scheduled', 'finished');--> statement-breakpoint
CREATE TYPE "public"."session_type" AS ENUM('fp1', 'fp2', 'fp3', 'qualifying', 'sprint_quali', 'sprint', 'race');--> statement-breakpoint
CREATE TABLE "constructor" (
	"id" text PRIMARY KEY NOT NULL,
	"name" text NOT NULL,
	"nationality" text,
	"wikipedia_url" text,
	"image_url" text,
	"image_url_override" text
);
--> statement-breakpoint
CREATE TABLE "constructor_standing" (
	"season_year" integer NOT NULL,
	"constructor_id" text NOT NULL,
	"position" integer NOT NULL,
	"points" integer NOT NULL,
	"wins" integer NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "constructor_standing_season_year_constructor_id_pk" PRIMARY KEY("season_year","constructor_id")
);
--> statement-breakpoint
CREATE TABLE "driver" (
	"code" text PRIMARY KEY NOT NULL,
	"given_name" text NOT NULL,
	"family_name" text NOT NULL,
	"nationality" text,
	"permanent_number" integer,
	"wikipedia_url" text,
	"image_url" text,
	"image_url_override" text
);
--> statement-breakpoint
CREATE TABLE "driver_standing" (
	"season_year" integer NOT NULL,
	"driver_code" text NOT NULL,
	"position" integer NOT NULL,
	"points" integer NOT NULL,
	"wins" integer NOT NULL,
	"constructor_id" text NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "driver_standing_season_year_driver_code_pk" PRIMARY KEY("season_year","driver_code")
);
--> statement-breakpoint
CREATE TABLE "event" (
	"id" integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY (sequence name "event_id_seq" INCREMENT BY 1 MINVALUE 1 MAXVALUE 2147483647 START WITH 1 CACHE 1),
	"season_year" integer NOT NULL,
	"round" integer NOT NULL,
	"name" text NOT NULL,
	"circuit_name" text NOT NULL,
	"country" text NOT NULL,
	"has_sprint" boolean DEFAULT false NOT NULL
);
--> statement-breakpoint
CREATE TABLE "season" (
	"year" integer PRIMARY KEY NOT NULL,
	"is_current" boolean DEFAULT false NOT NULL
);
--> statement-breakpoint
CREATE TABLE "session" (
	"id" integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY (sequence name "session_id_seq" INCREMENT BY 1 MINVALUE 1 MAXVALUE 2147483647 START WITH 1 CACHE 1),
	"event_id" integer NOT NULL,
	"type" "session_type" NOT NULL,
	"scheduled_start" timestamp with time zone NOT NULL,
	"scheduled_end" timestamp with time zone NOT NULL,
	"status" "session_status" DEFAULT 'scheduled' NOT NULL
);
--> statement-breakpoint
CREATE TABLE "session_result" (
	"session_id" integer NOT NULL,
	"position" integer NOT NULL,
	"driver_code" text NOT NULL,
	"driver_name" text NOT NULL,
	"constructor_id" text NOT NULL,
	"constructor_name" text NOT NULL,
	"race_time" text,
	"status" text,
	"points" integer,
	"fastest_lap" text,
	"fastest_lap_time" text,
	"fastest_lap_speed" text,
	"q1" text,
	"q2" text,
	"q3" text,
	CONSTRAINT "session_result_session_id_position_pk" PRIMARY KEY("session_id","position")
);
--> statement-breakpoint
ALTER TABLE "constructor_standing" ADD CONSTRAINT "constructor_standing_season_year_season_year_fk" FOREIGN KEY ("season_year") REFERENCES "public"."season"("year") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "constructor_standing" ADD CONSTRAINT "constructor_standing_constructor_id_constructor_id_fk" FOREIGN KEY ("constructor_id") REFERENCES "public"."constructor"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "driver_standing" ADD CONSTRAINT "driver_standing_season_year_season_year_fk" FOREIGN KEY ("season_year") REFERENCES "public"."season"("year") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "driver_standing" ADD CONSTRAINT "driver_standing_driver_code_driver_code_fk" FOREIGN KEY ("driver_code") REFERENCES "public"."driver"("code") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "driver_standing" ADD CONSTRAINT "driver_standing_constructor_id_constructor_id_fk" FOREIGN KEY ("constructor_id") REFERENCES "public"."constructor"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "event" ADD CONSTRAINT "event_season_year_season_year_fk" FOREIGN KEY ("season_year") REFERENCES "public"."season"("year") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "session" ADD CONSTRAINT "session_event_id_event_id_fk" FOREIGN KEY ("event_id") REFERENCES "public"."event"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "session_result" ADD CONSTRAINT "session_result_session_id_session_id_fk" FOREIGN KEY ("session_id") REFERENCES "public"."session"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "session_result" ADD CONSTRAINT "session_result_driver_code_driver_code_fk" FOREIGN KEY ("driver_code") REFERENCES "public"."driver"("code") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "session_result" ADD CONSTRAINT "session_result_constructor_id_constructor_id_fk" FOREIGN KEY ("constructor_id") REFERENCES "public"."constructor"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "event_season_round_uq" ON "event" USING btree ("season_year","round");--> statement-breakpoint
CREATE UNIQUE INDEX "session_event_type_uq" ON "session" USING btree ("event_id","type");