CREATE TABLE "prediction_import" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"league_id" uuid NOT NULL,
	"season_year" integer NOT NULL,
	"uploaded_by" uuid NOT NULL,
	"uploaded_at" timestamp with time zone DEFAULT now() NOT NULL,
	"schema_version" integer NOT NULL,
	"applied_count" integer NOT NULL,
	"skipped_count" integer NOT NULL,
	"raw_filename" text
);
--> statement-breakpoint
ALTER TABLE "prediction" ADD COLUMN "source" text DEFAULT 'app' NOT NULL;--> statement-breakpoint
ALTER TABLE "prediction" ADD COLUMN "imported_by" uuid;--> statement-breakpoint
ALTER TABLE "prediction" ADD COLUMN "imported_at" timestamp with time zone;--> statement-breakpoint
ALTER TABLE "prediction_import" ADD CONSTRAINT "prediction_import_league_id_league_id_fk" FOREIGN KEY ("league_id") REFERENCES "public"."league"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "prediction_import" ADD CONSTRAINT "prediction_import_season_year_season_year_fk" FOREIGN KEY ("season_year") REFERENCES "public"."season"("year") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "prediction_import" ADD CONSTRAINT "prediction_import_uploaded_by_user_id_fk" FOREIGN KEY ("uploaded_by") REFERENCES "public"."user"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "prediction_import_league_idx" ON "prediction_import" USING btree ("league_id","uploaded_at");--> statement-breakpoint
ALTER TABLE "prediction" ADD CONSTRAINT "prediction_imported_by_user_id_fk" FOREIGN KEY ("imported_by") REFERENCES "public"."user"("id") ON DELETE no action ON UPDATE no action;