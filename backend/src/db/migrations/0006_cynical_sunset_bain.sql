CREATE TABLE "preseason_projection_snapshot" (
	"user_id" uuid NOT NULL,
	"season_year" integer NOT NULL,
	"after_session_id" integer NOT NULL,
	"projected_points" integer NOT NULL,
	"computed_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "preseason_projection_snapshot_user_id_season_year_after_session_id_pk" PRIMARY KEY("user_id","season_year","after_session_id")
);
--> statement-breakpoint
ALTER TABLE "preseason_projection_snapshot" ADD CONSTRAINT "preseason_projection_snapshot_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "preseason_projection_snapshot" ADD CONSTRAINT "preseason_projection_snapshot_season_year_season_year_fk" FOREIGN KEY ("season_year") REFERENCES "public"."season"("year") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "preseason_projection_snapshot" ADD CONSTRAINT "preseason_projection_snapshot_after_session_id_session_id_fk" FOREIGN KEY ("after_session_id") REFERENCES "public"."session"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "preseason_proj_snapshot_user_season_idx" ON "preseason_projection_snapshot" USING btree ("user_id","season_year");