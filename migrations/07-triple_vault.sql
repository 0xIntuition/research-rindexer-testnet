-- Migration: Create triple_vault materialized view
-- Description: Aggregates vault data for both pro (term_id) and counter (counter_term_id) vaults per triple
--
-- Prerequisites:
-- This migration requires:
-- - 01-crypto.sql (for calculateCounterTripleId function)
-- - 03-vault.sql (vault materialized view)
-- - 06-triple.sql (triple materialized view)
--
-- Usage:
-- PGPASSWORD=rindexer psql -h localhost -p 5440 -U postgres -d postgres -f migrations/01-crypto.sql
-- PGPASSWORD=rindexer psql -h localhost -p 5440 -U postgres -d postgres -f migrations/02-position.sql
-- PGPASSWORD=rindexer psql -h localhost -p 5440 -U postgres -d postgres -f migrations/03-vault.sql
-- PGPASSWORD=rindexer psql -h localhost -p 5440 -U postgres -d postgres -f migrations/06-triple.sql
-- PGPASSWORD=rindexer psql -h localhost -p 5440 -U postgres -d postgres -f migrations/07-triple_vault.sql
--
-- Refresh:
-- SELECT refresh_triple_vault_view();

-- 1. DROP EXISTING OBJECTS (for idempotency)
DROP MATERIALIZED VIEW IF EXISTS public.triple_vault CASCADE;
DROP FUNCTION IF EXISTS refresh_triple_vault_view() CASCADE;

-- 2. CREATE MATERIALIZED VIEW
CREATE MATERIALIZED VIEW public.triple_vault AS
WITH vault_combined AS (
    -- Pro vaults: match on triple.term_id
    SELECT
        t.term_id,
        t.counter_term_id,
        t.created_at AS triple_created_at,
        t.block_number AS triple_block_number,
        v.curve_id,
        v.total_shares,
        v.total_assets,
        v.position_count,
        v.market_cap,
        v.block_number AS vault_block_number,
        v.log_index,
        v.updated_at
    FROM public.triple t
    INNER JOIN public.vault v
        ON t.term_id = v.term_id
        AND v.vault_type = 'Triple'

    UNION ALL

    -- Counter vaults: match on triple.counter_term_id
    SELECT
        t.term_id,
        t.counter_term_id,
        t.created_at AS triple_created_at,
        t.block_number AS triple_block_number,
        v.curve_id,
        v.total_shares,
        v.total_assets,
        v.position_count,
        v.market_cap,
        v.block_number AS vault_block_number,
        v.log_index,
        v.updated_at
    FROM public.triple t
    INNER JOIN public.vault v
        ON t.counter_term_id = v.term_id
        AND v.vault_type = 'CounterTriple'
)

SELECT
    term_id,
    counter_term_id,
    curve_id,

    -- Aggregated metrics
    CAST(SUM(total_shares) AS NUMERIC(78, 0)) AS total_shares,
    CAST(SUM(total_assets) AS NUMERIC(78, 0)) AS total_assets,
    CAST(SUM(position_count) AS BIGINT) AS position_count,
    CAST(SUM(market_cap) AS NUMERIC(78, 0)) AS market_cap,

    -- Most recent block and timestamp
    CAST(MAX(GREATEST(vault_block_number, triple_block_number)) AS NUMERIC(78, 0)) AS block_number,
    CAST(MAX(log_index) AS BIGINT) AS log_index,
    MAX(GREATEST(updated_at, triple_created_at)) AS updated_at

FROM vault_combined
GROUP BY term_id, counter_term_id, curve_id;

-- 3. CREATE INDEXES

-- Primary index (unique identifier) - required for CONCURRENT refresh
CREATE UNIQUE INDEX triple_vault_pkey
    ON public.triple_vault (term_id, curve_id);

-- Triple identifier indexes
CREATE INDEX idx_triple_vault_term_id
    ON public.triple_vault (term_id);

CREATE INDEX idx_triple_vault_counter_term_id
    ON public.triple_vault (counter_term_id);

-- Market cap indexes (for ranking and filtering)
CREATE INDEX idx_triple_vault_market_cap
    ON public.triple_vault (market_cap DESC);

-- Position count indexes (for popularity ranking)
CREATE INDEX idx_triple_vault_position_count
    ON public.triple_vault (position_count DESC);

-- Temporal indexes (for time-based queries and ordering)
CREATE INDEX idx_triple_vault_updated_at
    ON public.triple_vault (updated_at DESC);

-- Composite indexes for common query patterns
-- Most active triples by market cap and recent updates
CREATE INDEX idx_triple_vault_market_cap_updated
    ON public.triple_vault (market_cap DESC, updated_at DESC);

-- 4. CREATE REFRESH FUNCTION
-- This function can be called manually or scheduled via pg_cron
CREATE OR REPLACE FUNCTION refresh_triple_vault_view()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY public.triple_vault;
END;
$$;

-- 5. ADD COMMENTS FOR DOCUMENTATION

COMMENT ON MATERIALIZED VIEW public.triple_vault IS
'Aggregated triple vault data combining metrics from both pro (term_id) and counter (counter_term_id) vaults. Shows combined totals across both vaults. Updated via refresh_triple_vault_view().';

COMMENT ON FUNCTION refresh_triple_vault_view() IS
'Refreshes the triple_vault materialized view using CONCURRENT mode. Can be called manually or scheduled via pg_cron for periodic updates.';

-- Triple identifier columns
COMMENT ON COLUMN public.triple_vault.term_id IS
'Unique identifier for the triple (hex-encoded bytes32). This is the "pro" (for) vault term ID.';

COMMENT ON COLUMN public.triple_vault.counter_term_id IS
'Term ID of the counter-triple (the "con" or against position). Calculated using keccak256(abi.encodePacked(COUNTER_SALT, term_id)).';

COMMENT ON COLUMN public.triple_vault.curve_id IS
'Bonding curve identifier for the vault (typically 0 for standard curve).';

-- Combined metric columns
COMMENT ON COLUMN public.triple_vault.total_shares IS
'Combined total shares across both pro and counter vaults.';

COMMENT ON COLUMN public.triple_vault.total_assets IS
'Combined total assets across both pro and counter vaults (in wei).';

COMMENT ON COLUMN public.triple_vault.position_count IS
'Combined count of active positions across both pro and counter vaults.';

COMMENT ON COLUMN public.triple_vault.market_cap IS
'Combined market capitalization across both pro and counter vaults. Represents total economic activity for this triple.';

-- Block and transaction columns
COMMENT ON COLUMN public.triple_vault.block_number IS
'Most recent block number from either vault update or triple creation.';

COMMENT ON COLUMN public.triple_vault.log_index IS
'Log index from the most recent vault event (prioritizes pro vault).';

-- Timestamp column
COMMENT ON COLUMN public.triple_vault.updated_at IS
'Timestamp of the most recent vault update from either pro or counter vault.';
