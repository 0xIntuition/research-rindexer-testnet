-- Migration: Create atom materialized view
-- Description: Transforms atom_created events into an atom view with decoded data and metadata
--
-- Usage:
-- PGPASSWORD=rindexer psql -h localhost -p 5440 -U postgres -d postgres -f migrations/atom.sql
--
-- Refresh:
-- SELECT refresh_atom_view();

-- 1. CREATE ENUM TYPES
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

-- 2. DROP EXISTING OBJECTS (for idempotency)
DROP MATERIALIZED VIEW IF EXISTS public.atom CASCADE;
DROP FUNCTION IF EXISTS refresh_atom_view() CASCADE;
DROP FUNCTION IF EXISTS safe_utf8_decode(bytea) CASCADE;

-- 3. CREATE HELPER FUNCTION FOR SAFE UTF8 DECODING
CREATE OR REPLACE FUNCTION safe_utf8_decode(data bytea)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
    RETURN convert_from(data, 'UTF8');
EXCEPTION
    WHEN OTHERS THEN
        RETURN NULL;
END;
$$;

-- 4. CREATE MATERIALIZED VIEW
CREATE MATERIALIZED VIEW public.atom AS
WITH atom_events AS (
    SELECT
        '0x' || encode(term_id, 'hex') AS term_id,
        TRIM(atom_wallet) AS wallet_id,
        TRIM(creator) AS creator_id,
        safe_utf8_decode(atom_data) AS data,
        '0x' || encode(atom_data, 'hex') AS raw_data,
        'Unknown'::atom_type AS type,
        NULL::TEXT AS emoji,
        NULL::TEXT AS label,
        NULL::TEXT AS image,
        NULL::TEXT AS value_id,
        CAST(block_number AS NUMERIC(78, 0)) AS block_number,
        block_timestamp AS created_at,
        TRIM(tx_hash) AS transaction_hash,
        'Pending'::atom_resolving_status AS resolving_status,
        CAST(log_index AS BIGINT) AS log_index,
        now() AS updated_at
    FROM intuition_multi_vault.atom_created
)
SELECT * FROM atom_events;

-- 5. CREATE INDEXES
CREATE UNIQUE INDEX atom_pkey ON public.atom (term_id);
CREATE INDEX idx_atom_creator_id ON public.atom (creator_id);
CREATE INDEX idx_atom_wallet_id ON public.atom (wallet_id);
CREATE INDEX idx_atom_created_at ON public.atom (created_at);
CREATE INDEX idx_atom_block_number ON public.atom (block_number);
CREATE INDEX idx_atom_type ON public.atom (type);
CREATE INDEX idx_atom_resolving_status ON public.atom (resolving_status);

-- 6. CREATE REFRESH FUNCTION
CREATE OR REPLACE FUNCTION refresh_atom_view()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY public.atom;
END;
$$;

-- 7. ADD COMMENTS
COMMENT ON FUNCTION safe_utf8_decode(bytea) IS 'Safely decodes bytea to UTF8 text, returns NULL if decode fails';
COMMENT ON MATERIALIZED VIEW public.atom IS 'Materialized view of atoms created from atom_created events with decoded data and metadata';
COMMENT ON FUNCTION refresh_atom_view() IS 'Refreshes the atom materialized view concurrently';
COMMENT ON COLUMN public.atom.term_id IS 'Unique identifier for the atom (hex-encoded bytes32)';
COMMENT ON COLUMN public.atom.wallet_id IS 'Ethereum address of the atom wallet';
COMMENT ON COLUMN public.atom.creator_id IS 'Ethereum address of the atom creator';
COMMENT ON COLUMN public.atom.data IS 'UTF8-decoded atom data (NULL if decode fails)';
COMMENT ON COLUMN public.atom.raw_data IS 'Hex-encoded raw atom data (always available)';
COMMENT ON COLUMN public.atom.type IS 'Atom type classification (defaults to Unknown)';
COMMENT ON COLUMN public.atom.emoji IS 'Optional emoji representation (enriched later)';
COMMENT ON COLUMN public.atom.label IS 'Optional human-readable label (enriched later)';
COMMENT ON COLUMN public.atom.image IS 'Optional image URL (enriched later)';
COMMENT ON COLUMN public.atom.value_id IS 'Optional reference to value data (enriched later)';
COMMENT ON COLUMN public.atom.block_number IS 'Block number when the atom was created';
COMMENT ON COLUMN public.atom.created_at IS 'Timestamp when the atom was created';
COMMENT ON COLUMN public.atom.transaction_hash IS 'Transaction hash of the creation event';
COMMENT ON COLUMN public.atom.resolving_status IS 'Status of atom metadata resolution (Pending, Resolved, Failed)';
COMMENT ON COLUMN public.atom.log_index IS 'Log index of the creation event within the transaction';
COMMENT ON COLUMN public.atom.updated_at IS 'Timestamp when the record was last updated';
