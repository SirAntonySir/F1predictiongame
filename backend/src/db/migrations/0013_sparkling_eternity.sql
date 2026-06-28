CREATE TYPE "public"."notify_platform" AS ENUM('ios', 'android');--> statement-breakpoint
CREATE TABLE "device_token" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" uuid NOT NULL,
	"token" text NOT NULL,
	"platform" "notify_platform" NOT NULL,
	"timezone" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"last_seen_at" timestamp with time zone DEFAULT now() NOT NULL,
	"disabled_at" timestamp with time zone
);
--> statement-breakpoint
CREATE TABLE "notification_log" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"dedupe_key" text NOT NULL,
	"user_id" uuid NOT NULL,
	"kind" text NOT NULL,
	"session_id" integer,
	"sent_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "notification_pref" (
	"user_id" uuid PRIMARY KEY NOT NULL,
	"enabled" boolean DEFAULT true NOT NULL,
	"quiet_enabled" boolean DEFAULT false NOT NULL,
	"quiet_start_min" integer DEFAULT 1320 NOT NULL,
	"quiet_end_min" integer DEFAULT 480 NOT NULL,
	"timezone" text,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "device_token" ADD CONSTRAINT "device_token_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "notification_log" ADD CONSTRAINT "notification_log_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "notification_log" ADD CONSTRAINT "notification_log_session_id_session_id_fk" FOREIGN KEY ("session_id") REFERENCES "public"."session"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "notification_pref" ADD CONSTRAINT "notification_pref_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "device_token_token_uq" ON "device_token" USING btree ("token");--> statement-breakpoint
CREATE INDEX "device_token_user_idx" ON "device_token" USING btree ("user_id");--> statement-breakpoint
CREATE UNIQUE INDEX "notification_log_dedupe_uq" ON "notification_log" USING btree ("dedupe_key");--> statement-breakpoint
CREATE INDEX "notification_log_user_idx" ON "notification_log" USING btree ("user_id");