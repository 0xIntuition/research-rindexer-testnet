-- Migration: Create position materialized view
-- This view aggregates deposited and redeemed events to track current positions

-- Drop existing objects if they exist (for idempotency)
DROP MATERIALIZED VIEW IF EXISTS public.position CASCADE;
DROP FUNCTION IF EXISTS refresh_position_view() CASCADE;

-- Create the position materialized view
CREATE MATERIALIZED VIEW public.position AS
WITH
-- Get all deposited events with standardized columns
deposited_events AS (
    SELECT
        TRIM(receiver) AS account_id,
        '0x' || encode(term_id, 'hex') AS term_id,
        CAST(curve_id AS numeric(78,0)) AS curve_id,
        CAST(total_shares AS numeric(78,0)) AS total_shares,
        block_number,
        log_index,
        block_timestamp
    FROM intuition_multi_vault.deposited
),

-- Get all redeemed events with standardized columns
redeemed_events AS (
    SELECT
        TRIM(sender) AS account_id,
        '0x' || encode(term_id, 'hex') AS term_id,
        CAST(curve_id AS numeric(78,0)) AS curve_id,
        CAST(total_shares AS numeric(78,0)) AS total_shares,
        block_number,
        log_index,
        block_timestamp
    FROM intuition_multi_vault.redeemed
),

-- Union all events and get the latest total_shares per position
all_events AS (
    SELECT * FROM deposited_events
    UNION ALL
    SELECT * FROM redeemed_events
),

latest_shares AS (
    SELECT DISTINCT ON (account_id, term_id, curve_id)
        account_id,
        term_id,
        curve_id,
        total_shares AS shares,
        block_timestamp AS updated_at
    FROM all_events
    ORDER BY account_id, term_id, curve_id, block_number DESC, log_index DESC
),

-- Aggregate total deposit assets after fees
deposit_totals AS (
    SELECT
        TRIM(receiver) AS account_id,
        '0x' || encode(term_id, 'hex') AS term_id,
        CAST(curve_id AS numeric(78,0)) AS curve_id,
        COALESCE(SUM(CAST(assets_after_fees AS numeric(78,0))), 0) AS total_deposit_assets_after_total_fees
    FROM intuition_multi_vault.deposited
    GROUP BY TRIM(receiver), term_id, curve_id
),

-- Aggregate total redeem assets received
redeem_totals AS (
    SELECT
        TRIM(sender) AS account_id,
        '0x' || encode(term_id, 'hex') AS term_id,
        CAST(curve_id AS numeric(78,0)) AS curve_id,
        COALESCE(SUM(CAST(assets AS numeric(78,0))), 0) AS total_redeem_assets_for_receiver
    FROM intuition_multi_vault.redeemed
    GROUP BY TRIM(sender), term_id, curve_id
)

-- Final join to create the position view
SELECT
    ls.account_id,
    ls.term_id,
    ls.curve_id,
    ls.shares,
    COALESCE(dt.total_deposit_assets_after_total_fees, 0) AS total_deposit_assets_after_total_fees,
    COALESCE(rt.total_redeem_assets_for_receiver, 0) AS total_redeem_assets_for_receiver,
    ls.updated_at
FROM latest_shares ls
LEFT JOIN deposit_totals dt
    ON ls.account_id = dt.account_id
    AND ls.term_id = dt.term_id
    AND ls.curve_id = dt.curve_id
LEFT JOIN redeem_totals rt
    ON ls.account_id = rt.account_id
    AND ls.term_id = rt.term_id
    AND ls.curve_id = rt.curve_id;

-- Create indexes for optimized queries
CREATE UNIQUE INDEX position_pkey
    ON public.position (account_id, term_id, curve_id);

CREATE INDEX idx_position_account_id
    ON public.position (account_id);

CREATE INDEX idx_position_term_id
    ON public.position (term_id);

CREATE INDEX idx_position_updated_at
    ON public.position (updated_at);

-- Create refresh function for the materialized view
CREATE OR REPLACE FUNCTION refresh_position_view()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    -- CONCURRENTLY allows queries during refresh (requires unique index)
    REFRESH MATERIALIZED VIEW CONCURRENTLY public.position;
END;
$$;

COMMENT ON MATERIALIZED VIEW public.position IS
'Aggregated position data from deposited and redeemed events. Shows current shares and cumulative deposit/redeem totals per (account_id, term_id, curve_id).';

COMMENT ON FUNCTION refresh_position_view() IS
'Refreshes the position materialized view. Can be called manually or scheduled via pg_cron.';

-- Example usage for manual refresh:
-- SELECT refresh_position_view();

-- Example usage for scheduled refresh (requires pg_cron extension):
-- SELECT cron.schedule('refresh-position', '*/5 * * * *', 'SELECT refresh_position_view();');
