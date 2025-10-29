
CREATE TABLE "public"."position" (
    "account_id" text NOT NULL,
    "term_id" text NOT NULL,
    "curve_id" numeric(78,0) NOT NULL,
    "shares" numeric(78,0) NOT NULL,
    "total_deposit_assets_after_total_fees" numeric(78,0) NOT NULL DEFAULT 0,
    "total_redeem_assets_for_receiver" numeric(78,0) NOT NULL DEFAULT 0,
    "updated_at" timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY ("account_id", "term_id", "curve_id")
);



