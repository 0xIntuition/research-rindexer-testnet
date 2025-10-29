
CREATE TABLE "public"."position" (
    "account_id" text NOT NULL,
    "term_id" text NOT NULL,
    "curve_id" numeric(78,0) NOT NULL,
    "shares" numeric(78,0) NOT NULL,
    "total_deposit_assets_after_total_fees" numeric(78,0) NOT NULL DEFAULT 0,
    "total_redeem_assets_for_receiver" numeric(78,0) NOT NULL DEFAULT 0,
    "updated_at" timestamptz NOT NULL DEFAULT now(),
    "created_at" timestamptz NOT NULL DEFAULT now(),
  block_number BIGINT NOT NULL,
  log_index BIGINT NOT NULL,
  transaction_hash TEXT NOT NULL,
  transaction_index BIGINT NOT NULL,
    PRIMARY KEY ("account_id", "term_id", "curve_id")
);



CREATE TABLE IF NOT EXISTS vault (
  term_id TEXT NOT NULL,
  curve_id NUMERIC(78, 0) NOT NULL,
  total_shares NUMERIC(78, 0) NOT NULL,
  current_share_price NUMERIC(78, 0) NOT NULL,
  total_assets NUMERIC(78, 0) NOT NULL DEFAULT 0,
  market_cap NUMERIC(78, 0) NOT NULL DEFAULT 0,
  position_count INTEGER NOT NULL,
  block_number BIGINT NOT NULL,
  log_index BIGINT NOT NULL,
  transaction_hash TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  PRIMARY KEY (term_id, curve_id)
);

