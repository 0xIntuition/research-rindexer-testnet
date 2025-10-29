-- Create custom enum types
DO $$ BEGIN
    CREATE TYPE vault_type AS ENUM ('Triple', 'CounterTriple', 'Atom');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;
DO $$ BEGIN
    CREATE TYPE account_type AS ENUM ('Default', 'AtomWallet', 'ProtocolVault');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;
DO $$ BEGIN
    CREATE TYPE event_type AS ENUM ('AtomCreated', 'TripleCreated', 'Deposited', 'Redeemed', 'FeesTransfered', 'Initialized');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;
DO $$ BEGIN
    CREATE TYPE atom_type AS ENUM (
      'Unknown', 'Account', 'Thing', 'ThingPredicate', 'Person', 'PersonPredicate',
      'Organization', 'OrganizationPredicate', 'Book', 'LikeAction', 'FollowAction', 'Keywords',
      'Caip10', 'JsonObject', 'TextObject', 'ByteObject'
    );
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;
DO $$ BEGIN
    CREATE TYPE atom_resolving_status AS ENUM ('Pending', 'Resolved', 'Failed');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;
DO $$ BEGIN
    CREATE TYPE image_classification AS ENUM ('Safe', 'Unsafe', 'Unknown');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;
DO $$ BEGIN
    CREATE TYPE term_type AS ENUM ('Atom', 'Triple', 'CounterTriple');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;


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

CREATE TABLE IF NOT EXISTS term (
  id TEXT PRIMARY KEY,
  type term_type NOT NULL,
  atom_id TEXT,
  triple_id TEXT,
  total_assets NUMERIC(78, 0),
  total_market_cap NUMERIC(78, 0),
  created_at TIMESTAMP WITH TIME ZONE NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);



CREATE TABLE IF NOT EXISTS atom (
  term_id TEXT PRIMARY KEY NOT NULL,
  wallet_id TEXT NOT NULL,
  creator_id TEXT NOT NULL,
  data TEXT, -- utf8 encoded string
  raw_data TEXT NOT NULL, -- bytes encoded as hex string
  type atom_type NOT NULL, -- Unknown as default
  emoji TEXT,
  label TEXT,
  image TEXT,
  value_id TEXT,
  block_number NUMERIC(78, 0) NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL,
  transaction_hash TEXT NOT NULL,
  resolving_status atom_resolving_status NOT NULL DEFAULT 'Pending',
  log_index BIGINT NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS triple (
  term_id TEXT PRIMARY KEY NOT NULL,
  creator_id TEXT NOT NULL,
  subject_id TEXT NOT NULL,
  predicate_id TEXT NOT NULL,
  object_id TEXT NOT NULL,
  counter_term_id TEXT NOT NULL, -- 'Pending' as default
  block_number NUMERIC(78, 0) NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL,
  transaction_hash TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS triple_vault (
  term_id TEXT NOT NULL,
  counter_term_id TEXT NOT NULL,
  curve_id NUMERIC(78, 0) NOT NULL,
  total_shares NUMERIC(78, 0) NOT NULL,
  total_assets NUMERIC(78, 0) NOT NULL,
  position_count BIGINT NOT NULL,
  market_cap NUMERIC(78, 0) NOT NULL,
  block_number NUMERIC(78, 0) NOT NULL,
  log_index BIGINT NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  PRIMARY KEY (term_id, curve_id)
);
