-- Migration: Create trigger-based tables (replaces materialized views)
-- Description: Creates 9 regular tables that will be updated in real-time via triggers
--
-- This migration replaces the old materialized view approach with trigger-based tables
-- for real-time data updates without manual refresh operations.
--
-- Usage:
-- PGPASSWORD=rindexer psql -h localhost -p 5440 -U postgres -d postgres -f migrations/02-tables.sql

-- ============================================================================
-- 1. CREATE ENUM TYPES
-- ============================================================================

-- Atom types
DO $$ BEGIN
    CREATE TYPE atom_type AS ENUM (
      'Unknown', 'Account', 'Thing', 'ThingPredicate', 'Person', 'PersonPredicate',
      'Organization', 'OrganizationPredicate', 'Book', 'LikeAction', 'FollowAction', 'Keywords',
      'Caip10', 'JsonObject', 'TextObject', 'ByteObject'
    );
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- Atom resolving status
DO $$ BEGIN
    CREATE TYPE atom_resolving_status AS ENUM ('Pending', 'Resolved', 'Failed');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- Vault types
DO $$ BEGIN
    CREATE TYPE vault_type AS ENUM ('Atom', 'Triple', 'CounterTriple');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- Term types
DO $$ BEGIN
    CREATE TYPE term_type AS ENUM ('Atom', 'Triple', 'CounterTriple');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- ============================================================================
-- 2. DROP EXISTING OBJECTS (for idempotency)
-- ============================================================================

DROP TABLE IF EXISTS public.atom CASCADE;
DROP TABLE IF EXISTS public.triple CASCADE;
DROP TABLE IF EXISTS public.position CASCADE;
DROP TABLE IF EXISTS public.vault CASCADE;
DROP TABLE IF EXISTS public.term CASCADE;
DROP TABLE IF EXISTS public.triple_vault CASCADE;
DROP TABLE IF EXISTS public.triple_term CASCADE;
DROP TABLE IF EXISTS public.predicate_object CASCADE;
DROP TABLE IF EXISTS public.subject_predicate CASCADE;

-- ============================================================================
-- 3. CREATE TABLES
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 3.1 ATOM TABLE (Level 0)
-- ----------------------------------------------------------------------------
CREATE TABLE public.atom (
    term_id TEXT PRIMARY KEY,
    wallet_id TEXT,
    creator_id TEXT,
    data TEXT,
    raw_data TEXT,
    type atom_type DEFAULT 'Unknown',
    emoji TEXT,
    label TEXT,
    image TEXT,
    value_id TEXT,
    block_number NUMERIC(78, 0) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE,
    transaction_hash TEXT,
    resolving_status atom_resolving_status DEFAULT 'Pending',
    log_index BIGINT NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now(),

    -- Tracking columns for out-of-order event handling
    last_updated_block NUMERIC(78, 0) NOT NULL,
    last_updated_log_index TEXT NOT NULL
);

-- Atom indexes
CREATE INDEX idx_atom_creator_id ON public.atom (creator_id);
CREATE INDEX idx_atom_wallet_id ON public.atom (wallet_id);
CREATE INDEX idx_atom_created_at ON public.atom (created_at);
CREATE INDEX idx_atom_block_number ON public.atom (block_number);
CREATE INDEX idx_atom_type ON public.atom (type);
CREATE INDEX idx_atom_resolving_status ON public.atom (resolving_status);

-- Atom comments
COMMENT ON TABLE public.atom IS 'Atoms created from atom_created events with decoded data and metadata. Updated in real-time via triggers.';
COMMENT ON COLUMN public.atom.term_id IS 'Unique identifier for the atom (hex-encoded bytes32)';
COMMENT ON COLUMN public.atom.wallet_id IS 'Ethereum address of the atom wallet';
COMMENT ON COLUMN public.atom.creator_id IS 'Ethereum address of the atom creator';
COMMENT ON COLUMN public.atom.data IS 'UTF8-decoded atom data (NULL if decode fails)';
COMMENT ON COLUMN public.atom.raw_data IS 'Hex-encoded raw atom data (always available)';
COMMENT ON COLUMN public.atom.last_updated_block IS 'Block number of the last event that updated this atom (for out-of-order handling)';
COMMENT ON COLUMN public.atom.last_updated_log_index IS 'Log index of the last event that updated this atom (for out-of-order handling)';

-- ----------------------------------------------------------------------------
-- 3.2 TRIPLE TABLE (Level 0)
-- ----------------------------------------------------------------------------
CREATE TABLE public.triple (
    term_id TEXT PRIMARY KEY,
    creator_id TEXT,
    subject_id TEXT NOT NULL,
    predicate_id TEXT NOT NULL,
    object_id TEXT NOT NULL,
    counter_term_id TEXT NOT NULL,
    block_number NUMERIC(78, 0) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE,
    transaction_hash TEXT,

    -- Tracking columns for out-of-order event handling
    last_updated_block NUMERIC(78, 0) NOT NULL,
    last_updated_log_index TEXT NOT NULL
);

-- Triple indexes
CREATE INDEX idx_triple_creator_id ON public.triple (creator_id);
CREATE INDEX idx_triple_subject_id ON public.triple (subject_id);
CREATE INDEX idx_triple_predicate_id ON public.triple (predicate_id);
CREATE INDEX idx_triple_object_id ON public.triple (object_id);
CREATE INDEX idx_triple_counter_term_id ON public.triple (counter_term_id);
CREATE INDEX idx_triple_created_at ON public.triple (created_at);
CREATE INDEX idx_triple_block_number ON public.triple (block_number);
CREATE INDEX idx_triple_subject_predicate ON public.triple (subject_id, predicate_id);

-- Triple comments
COMMENT ON TABLE public.triple IS 'Triples created from triple_created events with calculated counter-triple IDs. Updated in real-time via triggers.';
COMMENT ON COLUMN public.triple.term_id IS 'Unique identifier for the triple (hex-encoded bytes32). This is the "pro" (for) vault term ID.';
COMMENT ON COLUMN public.triple.counter_term_id IS 'Term ID of the counter-triple (the "con" or against position). Calculated using keccak256(abi.encodePacked(COUNTER_SALT, term_id)).';
COMMENT ON COLUMN public.triple.last_updated_block IS 'Block number of the last event that updated this triple (for out-of-order handling)';
COMMENT ON COLUMN public.triple.last_updated_log_index IS 'Log index of the last event that updated this triple (for out-of-order handling)';

-- ----------------------------------------------------------------------------
-- 3.3 POSITION TABLE (Level 0)
-- ----------------------------------------------------------------------------
CREATE TABLE public.position (
    account_id TEXT NOT NULL,
    term_id TEXT NOT NULL,
    curve_id NUMERIC(78, 0) NOT NULL,
    shares NUMERIC(78, 0) NOT NULL DEFAULT 0,
    total_deposit_assets_after_total_fees NUMERIC(78, 0) NOT NULL DEFAULT 0,
    total_redeem_assets_for_receiver NUMERIC(78, 0) NOT NULL DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE,
    updated_at TIMESTAMP WITH TIME ZONE,
    block_number BIGINT NOT NULL,
    log_index BIGINT NOT NULL,
    transaction_hash TEXT,
    transaction_index BIGINT,

    -- Tracking columns for out-of-order event handling
    last_updated_block NUMERIC(78, 0) NOT NULL,
    last_updated_log_index TEXT NOT NULL,

    PRIMARY KEY (account_id, term_id, curve_id)
);

-- Position indexes
CREATE INDEX idx_position_account_id ON public.position (account_id);
CREATE INDEX idx_position_term_id ON public.position (term_id);
CREATE INDEX idx_position_updated_at ON public.position (updated_at);
CREATE INDEX idx_position_created_at ON public.position (created_at);
CREATE INDEX idx_position_active_account ON public.position (account_id) WHERE shares > 0;
CREATE INDEX idx_position_active_term ON public.position (term_id) WHERE shares > 0;
CREATE INDEX idx_position_active_account_term ON public.position (account_id, term_id) WHERE shares > 0;
CREATE INDEX idx_position_significant ON public.position (account_id, term_id, curve_id) WHERE total_deposit_assets_after_total_fees > 1000000000000000000;

-- Position comments
COMMENT ON TABLE public.position IS 'Aggregated position data from deposited and redeemed events. Shows current shares and cumulative deposit/redeem totals. Updated in real-time via triggers.';
COMMENT ON COLUMN public.position.shares IS 'Current shares in the vault (from most recent deposit or redeem event)';
COMMENT ON COLUMN public.position.total_deposit_assets_after_total_fees IS 'Cumulative total assets deposited across all historical deposit events';
COMMENT ON COLUMN public.position.total_redeem_assets_for_receiver IS 'Cumulative total assets redeemed across all historical redeem events';
COMMENT ON COLUMN public.position.last_updated_block IS 'Block number of the last event that updated current shares (for out-of-order handling)';
COMMENT ON COLUMN public.position.last_updated_log_index IS 'Log index of the last event that updated current shares (for out-of-order handling)';

-- ----------------------------------------------------------------------------
-- 3.4 VAULT TABLE (Level 1)
-- ----------------------------------------------------------------------------
CREATE TABLE public.vault (
    term_id TEXT NOT NULL,
    curve_id NUMERIC(78, 0) NOT NULL,
    total_shares NUMERIC(78, 0) NOT NULL DEFAULT 0,
    current_share_price NUMERIC(78, 0) NOT NULL DEFAULT 0,
    total_assets NUMERIC(78, 0) NOT NULL DEFAULT 0,
    market_cap NUMERIC(78, 0) NOT NULL DEFAULT 0,
    position_count BIGINT NOT NULL DEFAULT 0,
    vault_type vault_type,
    block_number BIGINT NOT NULL,
    log_index BIGINT NOT NULL,
    transaction_hash TEXT,
    transaction_index BIGINT,
    created_at TIMESTAMP WITH TIME ZONE,
    updated_at TIMESTAMP WITH TIME ZONE,

    -- Tracking columns for out-of-order event handling
    last_updated_block NUMERIC(78, 0) NOT NULL,
    last_updated_log_index TEXT NOT NULL,

    PRIMARY KEY (term_id, curve_id)
);

-- Vault indexes
CREATE INDEX idx_vault_term_id ON public.vault (term_id);
CREATE INDEX idx_vault_vault_type ON public.vault (vault_type);
CREATE INDEX idx_vault_updated_at ON public.vault (updated_at);
CREATE INDEX idx_vault_market_cap ON public.vault (market_cap DESC);
CREATE INDEX idx_vault_position_count ON public.vault (position_count DESC);

-- Vault comments
COMMENT ON TABLE public.vault IS 'Aggregated vault data from SharePriceChanged events. Shows current state including total assets, total shares, share price, market cap, and position count. Updated in real-time via triggers.';
COMMENT ON COLUMN public.vault.market_cap IS 'Calculated market capitalization: (total_shares * current_share_price) / 1e18';
COMMENT ON COLUMN public.vault.position_count IS 'Number of active positions (accounts with shares > 0) in this vault';
COMMENT ON COLUMN public.vault.last_updated_block IS 'Block number of the last event that updated this vault (for out-of-order handling)';
COMMENT ON COLUMN public.vault.last_updated_log_index IS 'Log index of the last event that updated this vault (for out-of-order handling)';

-- ----------------------------------------------------------------------------
-- 3.5 TERM TABLE (Level 2)
-- ----------------------------------------------------------------------------
CREATE TABLE public.term (
    id TEXT PRIMARY KEY,
    type term_type NOT NULL,
    atom_id TEXT,
    triple_id TEXT,
    total_assets NUMERIC(78, 0) NOT NULL DEFAULT 0,
    total_market_cap NUMERIC(78, 0) NOT NULL DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE,
    updated_at TIMESTAMP WITH TIME ZONE
);

-- Term indexes
CREATE INDEX idx_term_type ON public.term (type);
CREATE INDEX idx_term_updated_at ON public.term (updated_at);
CREATE INDEX idx_term_total_market_cap ON public.term (total_market_cap DESC);
CREATE INDEX idx_term_total_assets ON public.term (total_assets DESC);
CREATE INDEX idx_term_atom_id ON public.term (atom_id) WHERE atom_id IS NOT NULL;
CREATE INDEX idx_term_triple_id ON public.term (triple_id) WHERE triple_id IS NOT NULL;

-- Term comments
COMMENT ON TABLE public.term IS 'Aggregated term data from vault table. Shows totals across all curve_ids for each term. Updated in real-time via triggers.';
COMMENT ON COLUMN public.term.id IS 'Unique identifier for the term (atom or triple) as hex-encoded bytes32';
COMMENT ON COLUMN public.term.atom_id IS 'Set to term_id when type is Atom, NULL otherwise';
COMMENT ON COLUMN public.term.triple_id IS 'Set to term_id when type is Triple or CounterTriple, NULL otherwise';

-- ----------------------------------------------------------------------------
-- 3.6 TRIPLE_VAULT TABLE (Level 1)
-- ----------------------------------------------------------------------------
CREATE TABLE public.triple_vault (
    term_id TEXT NOT NULL,
    counter_term_id TEXT NOT NULL,
    curve_id NUMERIC(78, 0) NOT NULL,
    total_shares NUMERIC(78, 0) NOT NULL DEFAULT 0,
    total_assets NUMERIC(78, 0) NOT NULL DEFAULT 0,
    position_count BIGINT NOT NULL DEFAULT 0,
    market_cap NUMERIC(78, 0) NOT NULL DEFAULT 0,
    block_number NUMERIC(78, 0) NOT NULL,
    log_index BIGINT NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE,

    PRIMARY KEY (term_id, curve_id)
);

-- Triple vault indexes
CREATE INDEX idx_triple_vault_term_id ON public.triple_vault (term_id);
CREATE INDEX idx_triple_vault_counter_term_id ON public.triple_vault (counter_term_id);
CREATE INDEX idx_triple_vault_market_cap ON public.triple_vault (market_cap DESC);
CREATE INDEX idx_triple_vault_position_count ON public.triple_vault (position_count DESC);
CREATE INDEX idx_triple_vault_updated_at ON public.triple_vault (updated_at DESC);
CREATE INDEX idx_triple_vault_market_cap_updated ON public.triple_vault (market_cap DESC, updated_at DESC);

-- Triple vault comments
COMMENT ON TABLE public.triple_vault IS 'Aggregated triple vault data combining metrics from both pro (term_id) and counter (counter_term_id) vaults. Updated in real-time via triggers.';
COMMENT ON COLUMN public.triple_vault.term_id IS 'Unique identifier for the triple (hex-encoded bytes32). This is the "pro" (for) vault term ID.';
COMMENT ON COLUMN public.triple_vault.counter_term_id IS 'Term ID of the counter-triple (the "con" or against position)';
COMMENT ON COLUMN public.triple_vault.total_shares IS 'Combined total shares across both pro and counter vaults';
COMMENT ON COLUMN public.triple_vault.total_assets IS 'Combined total assets across both pro and counter vaults';
COMMENT ON COLUMN public.triple_vault.position_count IS 'Combined count of active positions across both pro and counter vaults';
COMMENT ON COLUMN public.triple_vault.market_cap IS 'Combined market capitalization across both pro and counter vaults';

-- ----------------------------------------------------------------------------
-- 3.7 TRIPLE_TERM TABLE (Level 2)
-- ----------------------------------------------------------------------------
CREATE TABLE public.triple_term (
    term_id TEXT PRIMARY KEY,
    counter_term_id TEXT NOT NULL,
    total_assets NUMERIC(78, 0) NOT NULL DEFAULT 0,
    total_market_cap NUMERIC(78, 0) NOT NULL DEFAULT 0,
    total_position_count BIGINT NOT NULL DEFAULT 0,
    updated_at TIMESTAMP WITH TIME ZONE
);

-- Triple term indexes
CREATE INDEX idx_triple_term_counter_term_id ON public.triple_term (counter_term_id);
CREATE INDEX idx_triple_term_updated_at ON public.triple_term (updated_at DESC);
CREATE INDEX idx_triple_term_total_market_cap ON public.triple_term (total_market_cap DESC);
CREATE INDEX idx_triple_term_total_assets ON public.triple_term (total_assets DESC);
CREATE INDEX idx_triple_term_total_position_count ON public.triple_term (total_position_count DESC);
CREATE INDEX idx_triple_term_market_cap_updated ON public.triple_term (total_market_cap DESC, updated_at DESC);

-- Triple term comments
COMMENT ON TABLE public.triple_term IS 'Aggregated triple term data from triple_vault table. Shows combined totals across all curve_ids for each triple. Updated in real-time via triggers.';
COMMENT ON COLUMN public.triple_term.term_id IS 'Unique identifier for the triple (hex-encoded bytes32). This is the primary term ID for the triple (the "pro" vault).';
COMMENT ON COLUMN public.triple_term.counter_term_id IS 'Term ID of the counter-triple (the "con" or against position)';
COMMENT ON COLUMN public.triple_term.total_assets IS 'Sum of total_assets across all vaults (all curve_ids, both pro and counter) for this triple';
COMMENT ON COLUMN public.triple_term.total_market_cap IS 'Sum of market_cap across all vaults (all curve_ids, both pro and counter) for this triple';
COMMENT ON COLUMN public.triple_term.total_position_count IS 'Sum of position_count across all vaults (all curve_ids, both pro and counter) for this triple';

-- ----------------------------------------------------------------------------
-- 3.8 PREDICATE_OBJECT TABLE (Level 3)
-- ----------------------------------------------------------------------------
CREATE TABLE public.predicate_object (
    predicate_id TEXT NOT NULL,
    object_id TEXT NOT NULL,
    triple_count INTEGER NOT NULL DEFAULT 0,
    total_position_count INTEGER NOT NULL DEFAULT 0,
    total_market_cap NUMERIC(78, 0) NOT NULL DEFAULT 0,

    PRIMARY KEY (predicate_id, object_id)
);

-- Predicate object indexes
CREATE INDEX idx_predicate_object_predicate_id ON public.predicate_object (predicate_id);
CREATE INDEX idx_predicate_object_object_id ON public.predicate_object (object_id);
CREATE INDEX idx_predicate_object_triple_count ON public.predicate_object (triple_count DESC);
CREATE INDEX idx_predicate_object_total_market_cap ON public.predicate_object (total_market_cap DESC);
CREATE INDEX idx_predicate_object_total_position_count ON public.predicate_object (total_position_count DESC);

-- Predicate object comments
COMMENT ON TABLE public.predicate_object IS 'Aggregated triple data grouped by predicate_id and object_id. Shows count of unique triples, total position count, and total market cap. Updated in real-time via triggers.';
COMMENT ON COLUMN public.predicate_object.predicate_id IS 'Identifier for the predicate (relationship type) in the triple';
COMMENT ON COLUMN public.predicate_object.object_id IS 'Identifier for the object (target entity) in the triple';
COMMENT ON COLUMN public.predicate_object.triple_count IS 'Number of distinct triples that have this predicate-object combination';
COMMENT ON COLUMN public.predicate_object.total_position_count IS 'Sum of position counts across all triples with this predicate-object pair';
COMMENT ON COLUMN public.predicate_object.total_market_cap IS 'Sum of market capitalization across all triples with this predicate-object pair';

-- ----------------------------------------------------------------------------
-- 3.9 SUBJECT_PREDICATE TABLE (Level 3)
-- ----------------------------------------------------------------------------
CREATE TABLE public.subject_predicate (
    subject_id TEXT NOT NULL,
    predicate_id TEXT NOT NULL,
    triple_count INTEGER NOT NULL DEFAULT 0,
    total_position_count INTEGER NOT NULL DEFAULT 0,
    total_market_cap NUMERIC(78, 0) NOT NULL DEFAULT 0,

    PRIMARY KEY (subject_id, predicate_id)
);

-- Subject predicate indexes
CREATE INDEX idx_subject_predicate_subject_id ON public.subject_predicate (subject_id);
CREATE INDEX idx_subject_predicate_predicate_id ON public.subject_predicate (predicate_id);
CREATE INDEX idx_subject_predicate_triple_count ON public.subject_predicate (triple_count DESC);
CREATE INDEX idx_subject_predicate_total_market_cap ON public.subject_predicate (total_market_cap DESC);
CREATE INDEX idx_subject_predicate_total_position_count ON public.subject_predicate (total_position_count DESC);

-- Subject predicate comments
COMMENT ON TABLE public.subject_predicate IS 'Aggregated triple data grouped by subject_id and predicate_id. Shows count of unique triples, total position count, and total market cap. Updated in real-time via triggers.';
COMMENT ON COLUMN public.subject_predicate.subject_id IS 'Identifier for the subject (source entity) in the triple';
COMMENT ON COLUMN public.subject_predicate.predicate_id IS 'Identifier for the predicate (relationship type) in the triple';
COMMENT ON COLUMN public.subject_predicate.triple_count IS 'Number of distinct triples that have this subject-predicate combination';
COMMENT ON COLUMN public.subject_predicate.total_position_count IS 'Sum of position counts across all triples with this subject-predicate pair';
COMMENT ON COLUMN public.subject_predicate.total_market_cap IS 'Sum of market capitalization across all triples with this subject-predicate pair';

-- ============================================================================
-- END OF MIGRATION
-- ============================================================================
