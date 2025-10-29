--
-- Index definitions for intuition_multi_vault schema
-- This migration adds performance indexes based on query patterns in materialized views
--

-- ============================================================================
-- TABLE: intuition_multi_vault.deposited
-- ============================================================================

-- CRITICAL: Composite index for DISTINCT ON query pattern
-- Supports: Finding latest total_shares per position (02-position.sql:60)
CREATE INDEX idx_deposited_receiver_term_curve_block_log
    ON intuition_multi_vault.deposited (receiver, term_id, curve_id, block_number DESC, log_index DESC);

-- HIGH PRIORITY: Composite index for GROUP BY aggregations
-- Supports: Calculating total deposits per position (02-position.sql:71)
CREATE INDEX idx_deposited_receiver_term_curve
    ON intuition_multi_vault.deposited (receiver, term_id, curve_id);

-- Individual column indexes for filtering and joins
CREATE INDEX idx_deposited_receiver
    ON intuition_multi_vault.deposited (receiver);

CREATE INDEX idx_deposited_term_id
    ON intuition_multi_vault.deposited (term_id);

CREATE INDEX idx_deposited_curve_id
    ON intuition_multi_vault.deposited (curve_id);

-- Temporal indexes for time-based queries and MIN aggregations
CREATE INDEX idx_deposited_block_timestamp
    ON intuition_multi_vault.deposited (block_timestamp);

CREATE INDEX idx_deposited_block_number
    ON intuition_multi_vault.deposited (block_number DESC);


-- ============================================================================
-- TABLE: intuition_multi_vault.redeemed
-- ============================================================================

-- CRITICAL: Composite index for DISTINCT ON query pattern
-- Supports: Finding latest total_shares per position (02-position.sql:60)
CREATE INDEX idx_redeemed_sender_term_curve_block_log
    ON intuition_multi_vault.redeemed (sender, term_id, curve_id, block_number DESC, log_index DESC);

-- HIGH PRIORITY: Composite index for GROUP BY aggregations
-- Supports: Calculating total redeems per position (02-position.sql:82)
CREATE INDEX idx_redeemed_sender_term_curve
    ON intuition_multi_vault.redeemed (sender, term_id, curve_id);

-- Individual column indexes for filtering and joins
CREATE INDEX idx_redeemed_sender
    ON intuition_multi_vault.redeemed (sender);

CREATE INDEX idx_redeemed_term_id
    ON intuition_multi_vault.redeemed (term_id);

CREATE INDEX idx_redeemed_curve_id
    ON intuition_multi_vault.redeemed (curve_id);

-- Temporal indexes for time-based queries and MIN aggregations
CREATE INDEX idx_redeemed_block_timestamp
    ON intuition_multi_vault.redeemed (block_timestamp);

CREATE INDEX idx_redeemed_block_number
    ON intuition_multi_vault.redeemed (block_number DESC);


-- ============================================================================
-- TABLE: intuition_multi_vault.share_price_changed
-- ============================================================================

-- CRITICAL: Composite index for DISTINCT ON query pattern
-- Supports: Finding latest share price per vault (03-vault.sql:47)
CREATE INDEX idx_share_price_term_curve_block_log
    ON intuition_multi_vault.share_price_changed (term_id, curve_id, block_number DESC, log_index DESC);

-- HIGH PRIORITY: Index for vault type filtering combined with term_id
-- Supports: JOIN queries in triple_vault view (07-triple_vault.sql:43-44, 63-65)
CREATE INDEX idx_share_price_term_vault_type
    ON intuition_multi_vault.share_price_changed (term_id, vault_type);

-- Individual column indexes for filtering and joins
CREATE INDEX idx_share_price_term_id
    ON intuition_multi_vault.share_price_changed (term_id);

CREATE INDEX idx_share_price_curve_id
    ON intuition_multi_vault.share_price_changed (curve_id);

CREATE INDEX idx_share_price_vault_type
    ON intuition_multi_vault.share_price_changed (vault_type);

-- Temporal indexes for time-based queries and MIN aggregations
CREATE INDEX idx_share_price_block_timestamp
    ON intuition_multi_vault.share_price_changed (block_timestamp);

CREATE INDEX idx_share_price_block_number
    ON intuition_multi_vault.share_price_changed (block_number DESC);


-- ============================================================================
-- TABLE: intuition_multi_vault.atom_created
-- ============================================================================

-- Primary lookup index for atom view
CREATE INDEX idx_atom_created_term_id
    ON intuition_multi_vault.atom_created (term_id);

-- Creator index for user-specific queries
CREATE INDEX idx_atom_created_creator
    ON intuition_multi_vault.atom_created (creator);

-- Wallet index for wallet-based lookups
CREATE INDEX idx_atom_created_atom_wallet
    ON intuition_multi_vault.atom_created (atom_wallet);

-- Temporal indexes
CREATE INDEX idx_atom_created_block_timestamp
    ON intuition_multi_vault.atom_created (block_timestamp);

CREATE INDEX idx_atom_created_block_number
    ON intuition_multi_vault.atom_created (block_number);


-- ============================================================================
-- TABLE: intuition_multi_vault.triple_created
-- ============================================================================

-- Primary lookup index for triple view
CREATE INDEX idx_triple_created_term_id
    ON intuition_multi_vault.triple_created (term_id);

-- Creator index for user-specific queries
CREATE INDEX idx_triple_created_creator
    ON intuition_multi_vault.triple_created (creator);

-- Atom relationship indexes for foreign key lookups
CREATE INDEX idx_triple_created_subject_id
    ON intuition_multi_vault.triple_created (subject_id);

CREATE INDEX idx_triple_created_predicate_id
    ON intuition_multi_vault.triple_created (predicate_id);

CREATE INDEX idx_triple_created_object_id
    ON intuition_multi_vault.triple_created (object_id);

-- Composite index for subject-predicate relationship queries
CREATE INDEX idx_triple_created_subject_predicate
    ON intuition_multi_vault.triple_created (subject_id, predicate_id);

-- Temporal indexes
CREATE INDEX idx_triple_created_block_timestamp
    ON intuition_multi_vault.triple_created (block_timestamp);

CREATE INDEX idx_triple_created_block_number
    ON intuition_multi_vault.triple_created (block_number);


-- ============================================================================
-- PERFORMANCE NOTES
-- ============================================================================
--
-- Priority 1 (CRITICAL): Indexes ending in _block_log support DISTINCT ON
-- queries that find the "latest" record per composite key. These are essential
-- for materialized view performance.
--
-- Priority 2 (HIGH): Composite indexes without _block_log support GROUP BY
-- aggregations for calculating totals and counts.
--
-- Priority 3 (MEDIUM): Individual term_id and vault_type indexes support
-- JOIN operations between materialized views and base tables.
--
-- Priority 4 (LOWER): Individual column and temporal indexes support general
-- filtering, sorting, and time-based queries.
--
-- CONSIDERATIONS:
-- - For very large tables (millions of rows), consider BRIN indexes for
--   block_number and block_timestamp as these are naturally ordered
-- - Ensure VACUUM and ANALYZE run regularly, especially after bulk data loads
-- - Monitor index usage with pg_stat_user_indexes to identify unused indexes
-- - Consider partitioning tables by block_number for extremely large datasets
--
