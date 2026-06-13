CREATE TABLE "circuit" (
	"id" text PRIMARY KEY NOT NULL,
	"name" text NOT NULL,
	"country_id" text,
	"latitude" double precision,
	"longitude" double precision,
	"current_layout_id" text,
	"fetched_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "circuit_svg" (
	"circuit_id" text NOT NULL,
	"layout_id" text NOT NULL,
	"detail" text NOT NULL,
	"variant" text NOT NULL,
	"svg" text NOT NULL,
	"fetched_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "circuit_svg_circuit_id_layout_id_detail_variant_pk" PRIMARY KEY("circuit_id","layout_id","detail","variant")
);
--> statement-breakpoint
ALTER TABLE "circuit_svg" ADD CONSTRAINT "circuit_svg_circuit_id_circuit_id_fk" FOREIGN KEY ("circuit_id") REFERENCES "public"."circuit"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "circuit_svg_layout_idx" ON "circuit_svg" USING btree ("layout_id");