-- Migration: Create trigger functions for real-time table updates
-- Description: Implements all trigger logic for 9 tables across 4 dependency levels
--
-- This migration creates trigger functions that update tables in real-time as blockchain events
-- arrive from rindexer, handling out-of-order events via block/log_index comparison.
--
-- Prerequisites:
-- - 01-crypto.sql (for calculateCounterTripleId and safe_utf8_decode functions)
-- - 02-tables.sql (for all table definitions)
--
-- Usage:
-- PGPASSWORD=rindexer psql -h localhost -p 5440 -U postgres -d postgres -f migrations/03-trigger-functions.sql

-- ============================================================================
-- LEVEL 0: BASE TABLE TRIGGERS (atom, triple, position)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0.1 ATOM TRIGGER FUNCTION
-- ----------------------------------------------------------------------------
-- Triggered by: intuition_multi_vault.atom_created INSERT events
-- Updates: public.atom table
-- Complexity: Simple (1:1 transform with UTF-8 decoding)
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION update_atom()
RETURNS TRIGGER AS $$
DECLARE
    v_term_id TEXT;
    v_wallet_id TEXT;
    v_creator_id TEXT;
    v_data TEXT;
    v_raw_data TEXT;
BEGIN
    -- Generate hex-encoded IDs and trim addresses
    v_term_id := '0x' || encode(NEW.term_id, 'hex');
    v_wallet_id := TRIM(NEW.atom_wallet);
    v_creator_id := TRIM(NEW.creator);
    v_data := public.safe_utf8_decode(NEW.atom_data);
    v_raw_data := '0x' || encode(NEW.atom_data, 'hex');

    -- Insert or update atom record
    INSERT INTO public.atom (
        term_id,
        wallet_id,
        creator_id,
        data,
        raw_data,
        type,
        emoji,
        label,
        image,
        value_id,
        block_number,
        created_at,
        transaction_hash,
        resolving_status,
        log_index,
        updated_at,
        last_updated_block,
        last_updated_log_index
    ) VALUES (
        v_term_id,
        v_wallet_id,
        v_creator_id,
        v_data,
        v_raw_data,
        'Unknown',
        NULL,
        NULL,
        NULL,
        NULL,
        NEW.block_number,
        NEW.block_timestamp,
        TRIM(NEW.tx_hash),
        'Pending',
        CAST(NEW.log_index AS BIGINT),
        now(),
        NEW.block_number,
        NEW.log_index
    )
    ON CONFLICT (term_id) DO UPDATE SET
        wallet_id = EXCLUDED.wallet_id,
        creator_id = EXCLUDED.creator_id,
        data = EXCLUDED.data,
        raw_data = EXCLUDED.raw_data,
        block_number = EXCLUDED.block_number,
        created_at = EXCLUDED.created_at,
        transaction_hash = EXCLUDED.transaction_hash,
        log_index = EXCLUDED.log_index,
        updated_at = now(),
        last_updated_block = EXCLUDED.last_updated_block,
        last_updated_log_index = EXCLUDED.last_updated_log_index
    WHERE
        -- Only update if new event is later than existing
        (EXCLUDED.last_updated_block > atom.last_updated_block) OR
        (EXCLUDED.last_updated_block = atom.last_updated_block AND
         EXCLUDED.last_updated_log_index > atom.last_updated_log_index);

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger
DROP TRIGGER IF EXISTS atom_created_insert_trigger ON intuition_multi_vault.atom_created;
CREATE TRIGGER atom_created_insert_trigger
    AFTER INSERT ON intuition_multi_vault.atom_created
    FOR EACH ROW EXECUTE FUNCTION update_atom();

COMMENT ON FUNCTION update_atom() IS 'Trigger function to update atom table from atom_created events with out-of-order handling';

-- ----------------------------------------------------------------------------
-- 0.2 TRIPLE TRIGGER FUNCTION
-- ----------------------------------------------------------------------------
-- Triggered by: intuition_multi_vault.triple_created INSERT events
-- Updates: public.triple table
-- Complexity: Moderate (uses Python UDF for counter-triple ID calculation)
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION update_triple()
RETURNS TRIGGER AS $$
DECLARE
    v_term_id TEXT;
    v_creator_id TEXT;
    v_subject_id TEXT;
    v_predicate_id TEXT;
    v_object_id TEXT;
    v_counter_term_id TEXT;
BEGIN
    -- Generate hex-encoded IDs and trim addresses
    v_term_id := '0x' || encode(NEW.term_id, 'hex');
    v_creator_id := TRIM(NEW.creator);
    v_subject_id := '0x' || encode(NEW.subject_id, 'hex');
    v_predicate_id := '0x' || encode(NEW.predicate_id, 'hex');
    v_object_id := '0x' || encode(NEW.object_id, 'hex');

    -- Calculate counter-triple ID using Python UDF
    v_counter_term_id := public.calculateCounterTripleId(NEW.term_id);

    -- Insert or update triple record
    INSERT INTO public.triple (
        term_id,
        creator_id,
        subject_id,
        predicate_id,
        object_id,
        counter_term_id,
        block_number,
        created_at,
        transaction_hash,
        last_updated_block,
        last_updated_log_index
    ) VALUES (
        v_term_id,
        v_creator_id,
        v_subject_id,
        v_predicate_id,
        v_object_id,
        v_counter_term_id,
        NEW.block_number,
        NEW.block_timestamp,
        TRIM(NEW.tx_hash),
        NEW.block_number,
        NEW.log_index
    )
    ON CONFLICT (term_id) DO UPDATE SET
        creator_id = EXCLUDED.creator_id,
        subject_id = EXCLUDED.subject_id,
        predicate_id = EXCLUDED.predicate_id,
        object_id = EXCLUDED.object_id,
        counter_term_id = EXCLUDED.counter_term_id,
        block_number = EXCLUDED.block_number,
        created_at = EXCLUDED.created_at,
        transaction_hash = EXCLUDED.transaction_hash,
        last_updated_block = EXCLUDED.last_updated_block,
        last_updated_log_index = EXCLUDED.last_updated_log_index
    WHERE
        -- Only update if new event is later than existing
        (EXCLUDED.last_updated_block > triple.last_updated_block) OR
        (EXCLUDED.last_updated_block = triple.last_updated_block AND
         EXCLUDED.last_updated_log_index > triple.last_updated_log_index);

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger
DROP TRIGGER IF EXISTS triple_created_insert_trigger ON intuition_multi_vault.triple_created;
CREATE TRIGGER triple_created_insert_trigger
    AFTER INSERT ON intuition_multi_vault.triple_created
    FOR EACH ROW EXECUTE FUNCTION update_triple();

COMMENT ON FUNCTION update_triple() IS 'Trigger function to update triple table from triple_created events with out-of-order handling and counter-triple ID calculation';

-- ----------------------------------------------------------------------------
-- 0.3 POSITION TRIGGER FUNCTIONS (DEPOSIT)
-- ----------------------------------------------------------------------------
-- Triggered by: intuition_multi_vault.deposited INSERT events
-- Updates: public.position table
-- Complexity: Very High (complex aggregation logic with out-of-order handling)
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION update_position_deposit()
RETURNS TRIGGER AS $$
DECLARE
    v_account_id TEXT;
    v_term_id_hex TEXT;
    v_curve_id NUMERIC(78, 0);
    v_shares NUMERIC(78, 0);
    v_assets_after_fees NUMERIC(78, 0);
    v_existing_record RECORD;
    v_is_later BOOLEAN;
BEGIN
    -- Extract and transform data
    v_account_id := TRIM(NEW.receiver);
    v_term_id_hex := '0x' || encode(NEW.term_id, 'hex');
    v_curve_id := CAST(NEW.curve_id AS NUMERIC(78, 0));
    v_shares := CAST(NEW.total_shares AS NUMERIC(78, 0));
    v_assets_after_fees := CAST(NEW.assets_after_fees AS NUMERIC(78, 0));

    -- Check if position exists
    SELECT * INTO v_existing_record
    FROM public.position
    WHERE account_id = v_account_id
      AND term_id = v_term_id_hex
      AND curve_id = v_curve_id;

    -- Determine if this event is later than existing
    IF v_existing_record IS NULL THEN
        v_is_later := TRUE;
    ELSE
        v_is_later := (NEW.block_number > v_existing_record.last_updated_block) OR
                      (NEW.block_number = v_existing_record.last_updated_block AND
                       NEW.log_index > v_existing_record.last_updated_log_index);
    END IF;

    -- Insert or update position
    IF v_existing_record IS NULL THEN
        -- New position: INSERT
        INSERT INTO public.position (
            account_id,
            term_id,
            curve_id,
            shares,
            total_deposit_assets_after_total_fees,
            total_redeem_assets_for_receiver,
            created_at,
            updated_at,
            block_number,
            log_index,
            transaction_hash,
            transaction_index,
            last_updated_block,
            last_updated_log_index
        ) VALUES (
            v_account_id,
            v_term_id_hex,
            v_curve_id,
            v_shares,
            v_assets_after_fees,
            0,
            NEW.block_timestamp,
            NEW.block_timestamp,
            NEW.block_number,
            CAST(NEW.log_index AS BIGINT),
            TRIM(NEW.tx_hash),
            NEW.tx_index,
            NEW.block_number,
            NEW.log_index
        );
    ELSE
        -- Existing position: UPDATE
        IF v_is_later THEN
            -- Update shares AND add to totals (chronologically later event)
            UPDATE public.position SET
                shares = v_shares,
                total_deposit_assets_after_total_fees = total_deposit_assets_after_total_fees + v_assets_after_fees,
                updated_at = NEW.block_timestamp,
                block_number = NEW.block_number,
                log_index = CAST(NEW.log_index AS BIGINT),
                transaction_hash = TRIM(NEW.tx_hash),
                transaction_index = NEW.tx_index,
                last_updated_block = NEW.block_number,
                last_updated_log_index = NEW.log_index
            WHERE account_id = v_account_id
              AND term_id = v_term_id_hex
              AND curve_id = v_curve_id;
        ELSE
            -- Only update totals (out-of-order event, older than current shares)
            UPDATE public.position SET
                total_deposit_assets_after_total_fees = total_deposit_assets_after_total_fees + v_assets_after_fees
            WHERE account_id = v_account_id
              AND term_id = v_term_id_hex
              AND curve_id = v_curve_id;
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create deposit trigger
DROP TRIGGER IF EXISTS deposited_insert_trigger ON intuition_multi_vault.deposited;
CREATE TRIGGER deposited_insert_trigger
    AFTER INSERT ON intuition_multi_vault.deposited
    FOR EACH ROW EXECUTE FUNCTION update_position_deposit();

COMMENT ON FUNCTION update_position_deposit() IS 'Trigger function to update position table from deposited events. Updates current shares if event is chronologically later, always accumulates deposit totals.';

-- ----------------------------------------------------------------------------
-- 0.4 POSITION TRIGGER FUNCTIONS (REDEEM)
-- ----------------------------------------------------------------------------
-- Triggered by: intuition_multi_vault.redeemed INSERT events
-- Updates: public.position table
-- Complexity: Very High (similar to deposit but for redemptions)
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION update_position_redeem()
RETURNS TRIGGER AS $$
DECLARE
    v_account_id TEXT;
    v_term_id_hex TEXT;
    v_curve_id NUMERIC(78, 0);
    v_shares NUMERIC(78, 0);
    v_assets NUMERIC(78, 0);
    v_existing_record RECORD;
    v_is_later BOOLEAN;
BEGIN
    -- Extract and transform data
    v_account_id := TRIM(NEW.sender);
    v_term_id_hex := '0x' || encode(NEW.term_id, 'hex');
    v_curve_id := CAST(NEW.curve_id AS NUMERIC(78, 0));
    v_shares := CAST(NEW.total_shares AS NUMERIC(78, 0));
    v_assets := CAST(NEW.assets AS NUMERIC(78, 0));

    -- Check if position exists
    SELECT * INTO v_existing_record
    FROM public.position
    WHERE account_id = v_account_id
      AND term_id = v_term_id_hex
      AND curve_id = v_curve_id;

    -- Determine if this event is later than existing
    IF v_existing_record IS NULL THEN
        v_is_later := TRUE;
    ELSE
        v_is_later := (NEW.block_number > v_existing_record.last_updated_block) OR
                      (NEW.block_number = v_existing_record.last_updated_block AND
                       NEW.log_index > v_existing_record.last_updated_log_index);
    END IF;

    -- Insert or update position
    IF v_existing_record IS NULL THEN
        -- New position (rare case - redeem without deposit): INSERT
        INSERT INTO public.position (
            account_id,
            term_id,
            curve_id,
            shares,
            total_deposit_assets_after_total_fees,
            total_redeem_assets_for_receiver,
            created_at,
            updated_at,
            block_number,
            log_index,
            transaction_hash,
            transaction_index,
            last_updated_block,
            last_updated_log_index
        ) VALUES (
            v_account_id,
            v_term_id_hex,
            v_curve_id,
            v_shares,
            0,
            v_assets,
            NEW.block_timestamp,
            NEW.block_timestamp,
            NEW.block_number,
            CAST(NEW.log_index AS BIGINT),
            TRIM(NEW.tx_hash),
            NEW.tx_index,
            NEW.block_number,
            NEW.log_index
        );
    ELSE
        -- Existing position: UPDATE
        IF v_is_later THEN
            -- Update shares AND add to totals (chronologically later event)
            UPDATE public.position SET
                shares = v_shares,
                total_redeem_assets_for_receiver = total_redeem_assets_for_receiver + v_assets,
                updated_at = NEW.block_timestamp,
                block_number = NEW.block_number,
                log_index = CAST(NEW.log_index AS BIGINT),
                transaction_hash = TRIM(NEW.tx_hash),
                transaction_index = NEW.tx_index,
                last_updated_block = NEW.block_number,
                last_updated_log_index = NEW.log_index
            WHERE account_id = v_account_id
              AND term_id = v_term_id_hex
              AND curve_id = v_curve_id;
        ELSE
            -- Only update totals (out-of-order event, older than current shares)
            UPDATE public.position SET
                total_redeem_assets_for_receiver = total_redeem_assets_for_receiver + v_assets
            WHERE account_id = v_account_id
              AND term_id = v_term_id_hex
              AND curve_id = v_curve_id;
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create redeem trigger
DROP TRIGGER IF EXISTS redeemed_insert_trigger ON intuition_multi_vault.redeemed;
CREATE TRIGGER redeemed_insert_trigger
    AFTER INSERT ON intuition_multi_vault.redeemed
    FOR EACH ROW EXECUTE FUNCTION update_position_redeem();

COMMENT ON FUNCTION update_position_redeem() IS 'Trigger function to update position table from redeemed events. Updates current shares if event is chronologically later, always accumulates redeem totals.';

-- ============================================================================
-- LEVEL 1: DEPENDENT TABLE TRIGGERS (vault, triple_vault)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1.1 VAULT TRIGGER FUNCTION (from share_price_changed events)
-- ----------------------------------------------------------------------------
-- Triggered by: intuition_multi_vault.share_price_changed INSERT events
-- Updates: public.vault table
-- Complexity: Moderate (market cap calculation, vault type mapping)
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION update_vault_from_share_price()
RETURNS TRIGGER AS $$
DECLARE
    v_term_id_hex TEXT;
    v_curve_id NUMERIC(78, 0);
    v_share_price NUMERIC(78, 0);
    v_total_assets NUMERIC(78, 0);
    v_total_shares NUMERIC(78, 0);
    v_market_cap NUMERIC(78, 0);
    v_vault_type vault_type;
    v_existing_record RECORD;
    v_is_later BOOLEAN;
BEGIN
    -- Extract and transform data
    v_term_id_hex := '0x' || encode(NEW.term_id, 'hex');
    v_curve_id := CAST(NEW.curve_id AS NUMERIC(78, 0));
    v_share_price := CAST(NEW.share_price AS NUMERIC(78, 0));
    v_total_assets := CAST(NEW.total_assets AS NUMERIC(78, 0));
    v_total_shares := CAST(NEW.total_shares AS NUMERIC(78, 0));

    -- Calculate market cap: (total_shares * current_share_price) / 1e18
    v_market_cap := CAST((v_total_shares * v_share_price / 1000000000000000000) AS NUMERIC(78, 0));

    -- Map vault type enum
    v_vault_type := CASE NEW.vault_type
        WHEN 0 THEN 'Atom'::vault_type
        WHEN 1 THEN 'Triple'::vault_type
        WHEN 2 THEN 'CounterTriple'::vault_type
    END;

    -- Check if vault exists
    SELECT * INTO v_existing_record
    FROM public.vault
    WHERE term_id = v_term_id_hex
      AND curve_id = v_curve_id;

    -- Determine if this event is later than existing
    IF v_existing_record IS NULL THEN
        v_is_later := TRUE;
    ELSE
        v_is_later := (NEW.block_number > v_existing_record.last_updated_block) OR
                      (NEW.block_number = v_existing_record.last_updated_block AND
                       NEW.log_index > v_existing_record.last_updated_log_index);
    END IF;

    -- Insert or update vault
    IF v_existing_record IS NULL THEN
        -- New vault: INSERT with position_count = 0 (will be updated by position trigger)
        INSERT INTO public.vault (
            term_id,
            curve_id,
            total_shares,
            current_share_price,
            total_assets,
            market_cap,
            position_count,
            vault_type,
            block_number,
            log_index,
            transaction_hash,
            transaction_index,
            created_at,
            updated_at,
            last_updated_block,
            last_updated_log_index
        ) VALUES (
            v_term_id_hex,
            v_curve_id,
            v_total_shares,
            v_share_price,
            v_total_assets,
            v_market_cap,
            0,
            v_vault_type,
            NEW.block_number,
            CAST(NEW.log_index AS BIGINT),
            TRIM(NEW.tx_hash),
            NEW.tx_index,
            NEW.block_timestamp,
            NEW.block_timestamp,
            NEW.block_number,
            NEW.log_index
        );
    ELSIF v_is_later THEN
        -- Existing vault and later event: UPDATE
        UPDATE public.vault SET
            total_shares = v_total_shares,
            current_share_price = v_share_price,
            total_assets = v_total_assets,
            market_cap = v_market_cap,
            vault_type = v_vault_type,
            block_number = NEW.block_number,
            log_index = CAST(NEW.log_index AS BIGINT),
            transaction_hash = TRIM(NEW.tx_hash),
            transaction_index = NEW.tx_index,
            updated_at = NEW.block_timestamp,
            last_updated_block = NEW.block_number,
            last_updated_log_index = NEW.log_index
        WHERE term_id = v_term_id_hex
          AND curve_id = v_curve_id;
    END IF;
    -- If event is older (out-of-order), do nothing for share price data

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create share price trigger
DROP TRIGGER IF EXISTS share_price_changed_insert_trigger ON intuition_multi_vault.share_price_changed;
CREATE TRIGGER share_price_changed_insert_trigger
    AFTER INSERT ON intuition_multi_vault.share_price_changed
    FOR EACH ROW EXECUTE FUNCTION update_vault_from_share_price();

COMMENT ON FUNCTION update_vault_from_share_price() IS 'Trigger function to update vault table from share_price_changed events with market cap calculation and out-of-order handling';

-- ----------------------------------------------------------------------------
-- 1.2 VAULT TRIGGER FUNCTION (from position changes)
-- ----------------------------------------------------------------------------
-- Triggered by: public.position INSERT/UPDATE events
-- Updates: public.vault table (position_count only)
-- Complexity: Moderate (recalculate count from positions)
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION update_vault_position_count()
RETURNS TRIGGER AS $$
DECLARE
    v_position_count BIGINT;
BEGIN
    -- Recalculate position count for this vault
    SELECT COUNT(*) INTO v_position_count
    FROM public.position
    WHERE term_id = NEW.term_id
      AND curve_id = NEW.curve_id
      AND shares > 0;

    -- Update vault position_count
    UPDATE public.vault SET
        position_count = v_position_count
    WHERE term_id = NEW.term_id
      AND curve_id = NEW.curve_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create position change trigger
DROP TRIGGER IF EXISTS position_change_trigger ON public.position;
CREATE TRIGGER position_change_trigger
    AFTER INSERT OR UPDATE ON public.position
    FOR EACH ROW EXECUTE FUNCTION update_vault_position_count();

COMMENT ON FUNCTION update_vault_position_count() IS 'Trigger function to update vault position_count when position table changes';

-- ----------------------------------------------------------------------------
-- 1.3 TRIPLE_VAULT TRIGGER FUNCTION (from vault changes)
-- ----------------------------------------------------------------------------
-- Triggered by: public.vault INSERT/UPDATE events
-- Updates: public.triple_vault table
-- Complexity: High (aggregate pro + counter vaults per triple)
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION update_triple_vault_from_vault()
RETURNS TRIGGER AS $$
DECLARE
    v_triple_record RECORD;
    v_aggregated RECORD;
BEGIN
    -- Find which triple(s) this vault belongs to
    -- Check if this vault's term_id matches any triple.term_id (pro vault)
    FOR v_triple_record IN
        SELECT term_id, counter_term_id
        FROM public.triple
        WHERE term_id = NEW.term_id OR counter_term_id = NEW.term_id
    LOOP
        -- Aggregate metrics from both pro and counter vaults for this triple
        SELECT
            v_triple_record.term_id AS term_id,
            v_triple_record.counter_term_id AS counter_term_id,
            NEW.curve_id AS curve_id,
            COALESCE(SUM(v.total_shares), 0) AS total_shares,
            COALESCE(SUM(v.total_assets), 0) AS total_assets,
            COALESCE(SUM(v.position_count), 0) AS position_count,
            COALESCE(SUM(v.market_cap), 0) AS market_cap,
            MAX(v.block_number) AS block_number,
            MAX(v.log_index) AS log_index,
            MAX(v.updated_at) AS updated_at
        INTO v_aggregated
        FROM public.vault v
        WHERE v.curve_id = NEW.curve_id
          AND (v.term_id = v_triple_record.term_id OR v.term_id = v_triple_record.counter_term_id)
          AND (v.vault_type = 'Triple' OR v.vault_type = 'CounterTriple');

        -- Insert or update triple_vault
        INSERT INTO public.triple_vault (
            term_id,
            counter_term_id,
            curve_id,
            total_shares,
            total_assets,
            position_count,
            market_cap,
            block_number,
            log_index,
            updated_at
        ) VALUES (
            v_aggregated.term_id,
            v_aggregated.counter_term_id,
            v_aggregated.curve_id,
            v_aggregated.total_shares,
            v_aggregated.total_assets,
            v_aggregated.position_count,
            v_aggregated.market_cap,
            v_aggregated.block_number,
            v_aggregated.log_index,
            v_aggregated.updated_at
        )
        ON CONFLICT (term_id, curve_id) DO UPDATE SET
            counter_term_id = EXCLUDED.counter_term_id,
            total_shares = EXCLUDED.total_shares,
            total_assets = EXCLUDED.total_assets,
            position_count = EXCLUDED.position_count,
            market_cap = EXCLUDED.market_cap,
            block_number = EXCLUDED.block_number,
            log_index = EXCLUDED.log_index,
            updated_at = EXCLUDED.updated_at;
    END LOOP;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create vault change trigger for triple_vault
DROP TRIGGER IF EXISTS vault_change_trigger_for_triple_vault ON public.vault;
CREATE TRIGGER vault_change_trigger_for_triple_vault
    AFTER INSERT OR UPDATE ON public.vault
    FOR EACH ROW EXECUTE FUNCTION update_triple_vault_from_vault();

COMMENT ON FUNCTION update_triple_vault_from_vault() IS 'Trigger function to update triple_vault table when vault table changes, aggregating pro + counter vault data';

-- ----------------------------------------------------------------------------
-- 1.4 TRIPLE_VAULT TRIGGER FUNCTION (from triple changes)
-- ----------------------------------------------------------------------------
-- Triggered by: public.triple INSERT/UPDATE events
-- Updates: public.triple_vault table
-- Complexity: High (find all vaults for new triple and aggregate)
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION update_triple_vault_from_triple()
RETURNS TRIGGER AS $$
DECLARE
    v_curve_record RECORD;
    v_aggregated RECORD;
BEGIN
    -- For each curve_id that has vaults for this triple
    FOR v_curve_record IN
        SELECT DISTINCT curve_id
        FROM public.vault
        WHERE term_id = NEW.term_id OR term_id = NEW.counter_term_id
    LOOP
        -- Aggregate metrics from both pro and counter vaults
        SELECT
            NEW.term_id AS term_id,
            NEW.counter_term_id AS counter_term_id,
            v_curve_record.curve_id AS curve_id,
            COALESCE(SUM(v.total_shares), 0) AS total_shares,
            COALESCE(SUM(v.total_assets), 0) AS total_assets,
            COALESCE(SUM(v.position_count), 0) AS position_count,
            COALESCE(SUM(v.market_cap), 0) AS market_cap,
            MAX(v.block_number) AS block_number,
            MAX(v.log_index) AS log_index,
            MAX(v.updated_at) AS updated_at
        INTO v_aggregated
        FROM public.vault v
        WHERE v.curve_id = v_curve_record.curve_id
          AND (v.term_id = NEW.term_id OR v.term_id = NEW.counter_term_id)
          AND (v.vault_type = 'Triple' OR v.vault_type = 'CounterTriple');

        -- Insert or update triple_vault
        INSERT INTO public.triple_vault (
            term_id,
            counter_term_id,
            curve_id,
            total_shares,
            total_assets,
            position_count,
            market_cap,
            block_number,
            log_index,
            updated_at
        ) VALUES (
            v_aggregated.term_id,
            v_aggregated.counter_term_id,
            v_aggregated.curve_id,
            v_aggregated.total_shares,
            v_aggregated.total_assets,
            v_aggregated.position_count,
            v_aggregated.market_cap,
            v_aggregated.block_number,
            v_aggregated.log_index,
            v_aggregated.updated_at
        )
        ON CONFLICT (term_id, curve_id) DO UPDATE SET
            counter_term_id = EXCLUDED.counter_term_id,
            total_shares = EXCLUDED.total_shares,
            total_assets = EXCLUDED.total_assets,
            position_count = EXCLUDED.position_count,
            market_cap = EXCLUDED.market_cap,
            block_number = EXCLUDED.block_number,
            log_index = EXCLUDED.log_index,
            updated_at = EXCLUDED.updated_at;
    END LOOP;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create triple change trigger for triple_vault
DROP TRIGGER IF EXISTS triple_change_trigger_for_triple_vault ON public.triple;
CREATE TRIGGER triple_change_trigger_for_triple_vault
    AFTER INSERT OR UPDATE ON public.triple
    FOR EACH ROW EXECUTE FUNCTION update_triple_vault_from_triple();

COMMENT ON FUNCTION update_triple_vault_from_triple() IS 'Trigger function to update triple_vault table when triple table changes, creating entries for all curve_ids';

-- ============================================================================
-- LEVEL 2: AGGREGATION TABLE TRIGGERS (term, triple_term)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 2.1 TERM TRIGGER FUNCTION
-- ----------------------------------------------------------------------------
-- Triggered by: public.vault INSERT/UPDATE events
-- Updates: public.term table
-- Complexity: Moderate (aggregate vaults by term_id)
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION update_term_from_vault()
RETURNS TRIGGER AS $$
DECLARE
    v_aggregated RECORD;
    v_term_type term_type;
    v_atom_id TEXT;
    v_triple_id TEXT;
BEGIN
    -- Aggregate all vaults for this term_id
    SELECT
        NEW.term_id AS id,
        NEW.vault_type,
        SUM(v.total_assets) AS total_assets,
        SUM(v.market_cap) AS total_market_cap,
        MIN(v.created_at) AS created_at,
        MAX(v.updated_at) AS updated_at
    INTO v_aggregated
    FROM public.vault v
    WHERE v.term_id = NEW.term_id
    GROUP BY NEW.term_id, NEW.vault_type;

    -- Map vault_type to term_type
    v_term_type := CASE v_aggregated.vault_type
        WHEN 'Atom' THEN 'Atom'::term_type
        WHEN 'Triple' THEN 'Triple'::term_type
        WHEN 'CounterTriple' THEN 'CounterTriple'::term_type
    END;

    -- Set atom_id or triple_id based on type
    IF v_term_type = 'Atom' THEN
        v_atom_id := v_aggregated.id;
        v_triple_id := NULL;
    ELSE
        v_atom_id := NULL;
        v_triple_id := v_aggregated.id;
    END IF;

    -- Insert or update term
    INSERT INTO public.term (
        id,
        type,
        atom_id,
        triple_id,
        total_assets,
        total_market_cap,
        created_at,
        updated_at
    ) VALUES (
        v_aggregated.id,
        v_term_type,
        v_atom_id,
        v_triple_id,
        v_aggregated.total_assets,
        v_aggregated.total_market_cap,
        v_aggregated.created_at,
        v_aggregated.updated_at
    )
    ON CONFLICT (id) DO UPDATE SET
        type = EXCLUDED.type,
        atom_id = EXCLUDED.atom_id,
        triple_id = EXCLUDED.triple_id,
        total_assets = EXCLUDED.total_assets,
        total_market_cap = EXCLUDED.total_market_cap,
        created_at = EXCLUDED.created_at,
        updated_at = EXCLUDED.updated_at;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create vault change trigger for term
DROP TRIGGER IF EXISTS vault_change_trigger_for_term ON public.vault;
CREATE TRIGGER vault_change_trigger_for_term
    AFTER INSERT OR UPDATE ON public.vault
    FOR EACH ROW EXECUTE FUNCTION update_term_from_vault();

COMMENT ON FUNCTION update_term_from_vault() IS 'Trigger function to update term table when vault table changes, aggregating across all curve_ids';

-- ----------------------------------------------------------------------------
-- 2.2 TRIPLE_TERM TRIGGER FUNCTION
-- ----------------------------------------------------------------------------
-- Triggered by: public.triple_vault INSERT/UPDATE events
-- Updates: public.triple_term table
-- Complexity: Moderate (aggregate triple_vaults by term_id)
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION update_triple_term_from_triple_vault()
RETURNS TRIGGER AS $$
DECLARE
    v_aggregated RECORD;
BEGIN
    -- Aggregate all triple_vaults for this term_id (across all curve_ids)
    SELECT
        NEW.term_id AS term_id,
        NEW.counter_term_id AS counter_term_id,
        SUM(tv.total_assets) AS total_assets,
        SUM(tv.market_cap) AS total_market_cap,
        SUM(tv.position_count) AS total_position_count,
        MAX(tv.updated_at) AS updated_at
    INTO v_aggregated
    FROM public.triple_vault tv
    WHERE tv.term_id = NEW.term_id;

    -- Insert or update triple_term
    INSERT INTO public.triple_term (
        term_id,
        counter_term_id,
        total_assets,
        total_market_cap,
        total_position_count,
        updated_at
    ) VALUES (
        v_aggregated.term_id,
        v_aggregated.counter_term_id,
        v_aggregated.total_assets,
        v_aggregated.total_market_cap,
        v_aggregated.total_position_count,
        v_aggregated.updated_at
    )
    ON CONFLICT (term_id) DO UPDATE SET
        counter_term_id = EXCLUDED.counter_term_id,
        total_assets = EXCLUDED.total_assets,
        total_market_cap = EXCLUDED.total_market_cap,
        total_position_count = EXCLUDED.total_position_count,
        updated_at = EXCLUDED.updated_at;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create triple_vault change trigger for triple_term
DROP TRIGGER IF EXISTS triple_vault_change_trigger_for_triple_term ON public.triple_vault;
CREATE TRIGGER triple_vault_change_trigger_for_triple_term
    AFTER INSERT OR UPDATE ON public.triple_vault
    FOR EACH ROW EXECUTE FUNCTION update_triple_term_from_triple_vault();

COMMENT ON FUNCTION update_triple_term_from_triple_vault() IS 'Trigger function to update triple_term table when triple_vault table changes, aggregating across all curve_ids';

-- ============================================================================
-- LEVEL 3: ANALYTICS TABLE TRIGGERS (predicate_object, subject_predicate)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 3.1 PREDICATE_OBJECT TRIGGER FUNCTION (from triple changes)
-- ----------------------------------------------------------------------------
-- Triggered by: public.triple INSERT/UPDATE/DELETE events
-- Updates: public.predicate_object table
-- Complexity: Moderate (aggregate triples by predicate-object pair)
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION update_predicate_object_from_triple()
RETURNS TRIGGER AS $$
DECLARE
    v_predicate_id TEXT;
    v_object_id TEXT;
    v_aggregated RECORD;
BEGIN
    -- Get predicate_id and object_id from trigger
    IF TG_OP = 'DELETE' THEN
        v_predicate_id := OLD.predicate_id;
        v_object_id := OLD.object_id;
    ELSE
        v_predicate_id := NEW.predicate_id;
        v_object_id := NEW.object_id;
    END IF;

    -- Aggregate all triples for this predicate-object pair
    SELECT
        COUNT(DISTINCT t.term_id)::INTEGER AS triple_count,
        COALESCE(SUM(tt.total_position_count), 0)::INTEGER AS total_position_count,
        COALESCE(SUM(tt.total_market_cap), 0) AS total_market_cap
    INTO v_aggregated
    FROM public.triple t
    LEFT JOIN public.triple_term tt ON tt.term_id = t.term_id
    WHERE t.predicate_id = v_predicate_id
      AND t.object_id = v_object_id;

    -- Insert or update predicate_object
    IF v_aggregated.triple_count > 0 THEN
        INSERT INTO public.predicate_object (
            predicate_id,
            object_id,
            triple_count,
            total_position_count,
            total_market_cap
        ) VALUES (
            v_predicate_id,
            v_object_id,
            v_aggregated.triple_count,
            v_aggregated.total_position_count,
            v_aggregated.total_market_cap
        )
        ON CONFLICT (predicate_id, object_id) DO UPDATE SET
            triple_count = EXCLUDED.triple_count,
            total_position_count = EXCLUDED.total_position_count,
            total_market_cap = EXCLUDED.total_market_cap;
    ELSE
        -- No triples left, delete the record
        DELETE FROM public.predicate_object
        WHERE predicate_id = v_predicate_id
          AND object_id = v_object_id;
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Create triple change trigger for predicate_object
DROP TRIGGER IF EXISTS triple_change_trigger_for_predicate_object ON public.triple;
CREATE TRIGGER triple_change_trigger_for_predicate_object
    AFTER INSERT OR UPDATE OR DELETE ON public.triple
    FOR EACH ROW EXECUTE FUNCTION update_predicate_object_from_triple();

COMMENT ON FUNCTION update_predicate_object_from_triple() IS 'Trigger function to update predicate_object table when triple table changes';

-- ----------------------------------------------------------------------------
-- 3.2 PREDICATE_OBJECT TRIGGER FUNCTION (from triple_term changes)
-- ----------------------------------------------------------------------------
-- Triggered by: public.triple_term INSERT/UPDATE events
-- Updates: public.predicate_object table
-- Complexity: Moderate (update aggregates when triple_term changes)
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION update_predicate_object_from_triple_term()
RETURNS TRIGGER AS $$
DECLARE
    v_triple_record RECORD;
    v_aggregated RECORD;
BEGIN
    -- Find the triple for this triple_term
    SELECT predicate_id, object_id INTO v_triple_record
    FROM public.triple
    WHERE term_id = NEW.term_id;

    IF v_triple_record IS NOT NULL THEN
        -- Aggregate all triples for this predicate-object pair
        SELECT
            COUNT(DISTINCT t.term_id)::INTEGER AS triple_count,
            COALESCE(SUM(tt.total_position_count), 0)::INTEGER AS total_position_count,
            COALESCE(SUM(tt.total_market_cap), 0) AS total_market_cap
        INTO v_aggregated
        FROM public.triple t
        LEFT JOIN public.triple_term tt ON tt.term_id = t.term_id
        WHERE t.predicate_id = v_triple_record.predicate_id
          AND t.object_id = v_triple_record.object_id;

        -- Insert or update predicate_object
        INSERT INTO public.predicate_object (
            predicate_id,
            object_id,
            triple_count,
            total_position_count,
            total_market_cap
        ) VALUES (
            v_triple_record.predicate_id,
            v_triple_record.object_id,
            v_aggregated.triple_count,
            v_aggregated.total_position_count,
            v_aggregated.total_market_cap
        )
        ON CONFLICT (predicate_id, object_id) DO UPDATE SET
            triple_count = EXCLUDED.triple_count,
            total_position_count = EXCLUDED.total_position_count,
            total_market_cap = EXCLUDED.total_market_cap;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create triple_term change trigger for predicate_object
DROP TRIGGER IF EXISTS triple_term_change_trigger_for_predicate_object ON public.triple_term;
CREATE TRIGGER triple_term_change_trigger_for_predicate_object
    AFTER INSERT OR UPDATE ON public.triple_term
    FOR EACH ROW EXECUTE FUNCTION update_predicate_object_from_triple_term();

COMMENT ON FUNCTION update_predicate_object_from_triple_term() IS 'Trigger function to update predicate_object table when triple_term table changes';

-- ----------------------------------------------------------------------------
-- 3.3 SUBJECT_PREDICATE TRIGGER FUNCTION (from triple changes)
-- ----------------------------------------------------------------------------
-- Triggered by: public.triple INSERT/UPDATE/DELETE events
-- Updates: public.subject_predicate table
-- Complexity: Moderate (aggregate triples by subject-predicate pair)
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION update_subject_predicate_from_triple()
RETURNS TRIGGER AS $$
DECLARE
    v_subject_id TEXT;
    v_predicate_id TEXT;
    v_aggregated RECORD;
BEGIN
    -- Get subject_id and predicate_id from trigger
    IF TG_OP = 'DELETE' THEN
        v_subject_id := OLD.subject_id;
        v_predicate_id := OLD.predicate_id;
    ELSE
        v_subject_id := NEW.subject_id;
        v_predicate_id := NEW.predicate_id;
    END IF;

    -- Aggregate all triples for this subject-predicate pair
    SELECT
        COUNT(DISTINCT t.term_id)::INTEGER AS triple_count,
        COALESCE(SUM(tt.total_position_count), 0)::INTEGER AS total_position_count,
        COALESCE(SUM(tt.total_market_cap), 0) AS total_market_cap
    INTO v_aggregated
    FROM public.triple t
    LEFT JOIN public.triple_term tt ON tt.term_id = t.term_id
    WHERE t.subject_id = v_subject_id
      AND t.predicate_id = v_predicate_id;

    -- Insert or update subject_predicate
    IF v_aggregated.triple_count > 0 THEN
        INSERT INTO public.subject_predicate (
            subject_id,
            predicate_id,
            triple_count,
            total_position_count,
            total_market_cap
        ) VALUES (
            v_subject_id,
            v_predicate_id,
            v_aggregated.triple_count,
            v_aggregated.total_position_count,
            v_aggregated.total_market_cap
        )
        ON CONFLICT (subject_id, predicate_id) DO UPDATE SET
            triple_count = EXCLUDED.triple_count,
            total_position_count = EXCLUDED.total_position_count,
            total_market_cap = EXCLUDED.total_market_cap;
    ELSE
        -- No triples left, delete the record
        DELETE FROM public.subject_predicate
        WHERE subject_id = v_subject_id
          AND predicate_id = v_predicate_id;
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Create triple change trigger for subject_predicate
DROP TRIGGER IF EXISTS triple_change_trigger_for_subject_predicate ON public.triple;
CREATE TRIGGER triple_change_trigger_for_subject_predicate
    AFTER INSERT OR UPDATE OR DELETE ON public.triple
    FOR EACH ROW EXECUTE FUNCTION update_subject_predicate_from_triple();

COMMENT ON FUNCTION update_subject_predicate_from_triple() IS 'Trigger function to update subject_predicate table when triple table changes';

-- ----------------------------------------------------------------------------
-- 3.4 SUBJECT_PREDICATE TRIGGER FUNCTION (from triple_term changes)
-- ----------------------------------------------------------------------------
-- Triggered by: public.triple_term INSERT/UPDATE events
-- Updates: public.subject_predicate table
-- Complexity: Moderate (update aggregates when triple_term changes)
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION update_subject_predicate_from_triple_term()
RETURNS TRIGGER AS $$
DECLARE
    v_triple_record RECORD;
    v_aggregated RECORD;
BEGIN
    -- Find the triple for this triple_term
    SELECT subject_id, predicate_id INTO v_triple_record
    FROM public.triple
    WHERE term_id = NEW.term_id;

    IF v_triple_record IS NOT NULL THEN
        -- Aggregate all triples for this subject-predicate pair
        SELECT
            COUNT(DISTINCT t.term_id)::INTEGER AS triple_count,
            COALESCE(SUM(tt.total_position_count), 0)::INTEGER AS total_position_count,
            COALESCE(SUM(tt.total_market_cap), 0) AS total_market_cap
        INTO v_aggregated
        FROM public.triple t
        LEFT JOIN public.triple_term tt ON tt.term_id = t.term_id
        WHERE t.subject_id = v_triple_record.subject_id
          AND t.predicate_id = v_triple_record.predicate_id;

        -- Insert or update subject_predicate
        INSERT INTO public.subject_predicate (
            subject_id,
            predicate_id,
            triple_count,
            total_position_count,
            total_market_cap
        ) VALUES (
            v_triple_record.subject_id,
            v_triple_record.predicate_id,
            v_aggregated.triple_count,
            v_aggregated.total_position_count,
            v_aggregated.total_market_cap
        )
        ON CONFLICT (subject_id, predicate_id) DO UPDATE SET
            triple_count = EXCLUDED.triple_count,
            total_position_count = EXCLUDED.total_position_count,
            total_market_cap = EXCLUDED.total_market_cap;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create triple_term change trigger for subject_predicate
DROP TRIGGER IF EXISTS triple_term_change_trigger_for_subject_predicate ON public.triple_term;
CREATE TRIGGER triple_term_change_trigger_for_subject_predicate
    AFTER INSERT OR UPDATE ON public.triple_term
    FOR EACH ROW EXECUTE FUNCTION update_subject_predicate_from_triple_term();

COMMENT ON FUNCTION update_subject_predicate_from_triple_term() IS 'Trigger function to update subject_predicate table when triple_term table changes';

-- ============================================================================
-- END OF MIGRATION
-- ============================================================================
