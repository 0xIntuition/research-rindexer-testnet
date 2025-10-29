-- Migration: Create triple materialized view
-- Description: Transforms triple_created events into a triple view with calculated counter_term_id
--
-- Prerequisites:
-- This migration requires the crypto.sql migration to be run first for the keccak256() function.
--
-- Usage:
-- PGPASSWORD=rindexer psql -h localhost -p 5440 -U postgres -d postgres -f migrations/crypto.sql
-- PGPASSWORD=rindexer psql -h localhost -p 5440 -U postgres -d postgres -f migrations/triple.sql
--
-- Refresh:
-- SELECT refresh_triple_view();

-- 1. DROP EXISTING OBJECTS (for idempotency)
DROP MATERIALIZED VIEW IF EXISTS public.triple CASCADE;
DROP FUNCTION IF EXISTS refresh_triple_view() CASCADE;

-- 2. CREATE MATERIALIZED VIEW
CREATE MATERIALIZED VIEW public.triple AS
WITH triple_events AS (
    SELECT
        '0x' || encode(tc.term_id, 'hex') AS term_id,
        TRIM(tc.creator) AS creator_id,
        '0x' || encode(tc.subject_id, 'hex') AS subject_id,
        '0x' || encode(tc.predicate_id, 'hex') AS predicate_id,
        '0x' || encode(tc.object_id, 'hex') AS object_id,
        -- Calculate counter-triple ID using COUNTER_SALT
        -- Matches Solidity: keccak256(abi.encodePacked(COUNTER_SALT, tripleId))
        calculateCounterTripleId(tc.term_id) AS counter_term_id,
        CAST(tc.block_number AS NUMERIC(78, 0)) AS block_number,
        tc.block_timestamp AS created_at,
        TRIM(tc.tx_hash) AS transaction_hash
    FROM intuition_multi_vault.triple_created tc
)
SELECT * FROM triple_events;

-- 3. CREATE INDEXES

-- Primary index (unique identifier)
CREATE UNIQUE INDEX triple_pkey ON public.triple (term_id);

-- Creator index (for user queries - "show me all triples created by user X")
CREATE INDEX idx_triple_creator_id ON public.triple (creator_id);

-- Atom reference indexes (for foreign key joins with atom table)
CREATE INDEX idx_triple_subject_id ON public.triple (subject_id);
CREATE INDEX idx_triple_predicate_id ON public.triple (predicate_id);
CREATE INDEX idx_triple_object_id ON public.triple (object_id);

-- Counter triple index (for pro/con relationship queries)
CREATE INDEX idx_triple_counter_term_id ON public.triple (counter_term_id);

-- Temporal indexes (for time-based queries and ordering)
CREATE INDEX idx_triple_created_at ON public.triple (created_at);
CREATE INDEX idx_triple_block_number ON public.triple (block_number);

-- Composite index (for subject-predicate relationship queries)
CREATE INDEX idx_triple_subject_predicate ON public.triple (subject_id, predicate_id);

-- 4. CREATE REFRESH FUNCTION
CREATE OR REPLACE FUNCTION refresh_triple_view()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY public.triple;
END;
$$;

-- 5. ADD COMMENTS

COMMENT ON MATERIALIZED VIEW public.triple IS 'Materialized view of triples created from triple_created events with calculated counter-triple IDs';
COMMENT ON FUNCTION refresh_triple_view() IS 'Refreshes the triple materialized view concurrently';

COMMENT ON COLUMN public.triple.term_id IS 'Unique identifier for the triple (hex-encoded bytes32). This is the "pro" (for) vault term ID.';
COMMENT ON COLUMN public.triple.creator_id IS 'Ethereum address of the account that created the triple';
COMMENT ON COLUMN public.triple.subject_id IS 'Term ID of the subject atom (the entity the statement is about)';
COMMENT ON COLUMN public.triple.predicate_id IS 'Term ID of the predicate atom (the relationship or property being asserted)';
COMMENT ON COLUMN public.triple.object_id IS 'Term ID of the object atom (the value or target of the relationship)';
COMMENT ON COLUMN public.triple.counter_term_id IS 'Term ID of the counter-triple (the "con" or against position). Calculated using keccak256(abi.encodePacked(COUNTER_SALT, term_id)) where COUNTER_SALT = keccak256("COUNTER_SALT"). Each triple has two vaults: one for the statement (term_id) and one against it (counter_term_id).';
COMMENT ON COLUMN public.triple.block_number IS 'Block number when the triple was created';
COMMENT ON COLUMN public.triple.created_at IS 'Timestamp when the triple was created (from block timestamp)';
COMMENT ON COLUMN public.triple.transaction_hash IS 'Transaction hash of the creation event';
