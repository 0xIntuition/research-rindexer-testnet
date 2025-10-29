--
-- PostgreSQL database dump
--

-- Dumped from database version 16.9 (Debian 16.9-1.pgdg120+1)
-- Dumped by pg_dump version 17.2

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: intuition_multi_vault; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA intuition_multi_vault;


ALTER SCHEMA intuition_multi_vault OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: atom_created; Type: TABLE; Schema: intuition_multi_vault; Owner: postgres
--

CREATE TABLE intuition_multi_vault.atom_created (
    rindexer_id integer NOT NULL,
    contract_address character(42) NOT NULL,
    creator character(42),
    term_id bytea,
    atom_data bytea,
    atom_wallet character(42),
    tx_hash character(66) NOT NULL,
    block_number numeric NOT NULL,
    block_timestamp timestamp with time zone,
    block_hash character(66) NOT NULL,
    network character varying(50) NOT NULL,
    tx_index numeric NOT NULL,
    log_index character varying(78) NOT NULL
);


ALTER TABLE intuition_multi_vault.atom_created OWNER TO postgres;

--
-- Name: atom_created_rindexer_id_seq; Type: SEQUENCE; Schema: intuition_multi_vault; Owner: postgres
--

CREATE SEQUENCE intuition_multi_vault.atom_created_rindexer_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE intuition_multi_vault.atom_created_rindexer_id_seq OWNER TO postgres;

--
-- Name: atom_created_rindexer_id_seq; Type: SEQUENCE OWNED BY; Schema: intuition_multi_vault; Owner: postgres
--

ALTER SEQUENCE intuition_multi_vault.atom_created_rindexer_id_seq OWNED BY intuition_multi_vault.atom_created.rindexer_id;


--
-- Name: deposited; Type: TABLE; Schema: intuition_multi_vault; Owner: postgres
--

CREATE TABLE intuition_multi_vault.deposited (
    rindexer_id integer NOT NULL,
    contract_address character(42) NOT NULL,
    sender character(42),
    receiver character(42),
    term_id bytea,
    curve_id character varying(78),
    assets character varying(78),
    assets_after_fees character varying(78),
    shares character varying(78),
    total_shares character varying(78),
    vault_type smallint,
    tx_hash character(66) NOT NULL,
    block_number numeric NOT NULL,
    block_timestamp timestamp with time zone,
    block_hash character(66) NOT NULL,
    network character varying(50) NOT NULL,
    tx_index numeric NOT NULL,
    log_index character varying(78) NOT NULL
);


ALTER TABLE intuition_multi_vault.deposited OWNER TO postgres;

--
-- Name: deposited_rindexer_id_seq; Type: SEQUENCE; Schema: intuition_multi_vault; Owner: postgres
--

CREATE SEQUENCE intuition_multi_vault.deposited_rindexer_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE intuition_multi_vault.deposited_rindexer_id_seq OWNER TO postgres;

--
-- Name: deposited_rindexer_id_seq; Type: SEQUENCE OWNED BY; Schema: intuition_multi_vault; Owner: postgres
--

ALTER SEQUENCE intuition_multi_vault.deposited_rindexer_id_seq OWNED BY intuition_multi_vault.deposited.rindexer_id;


--
-- Name: redeemed; Type: TABLE; Schema: intuition_multi_vault; Owner: postgres
--

CREATE TABLE intuition_multi_vault.redeemed (
    rindexer_id integer NOT NULL,
    contract_address character(42) NOT NULL,
    sender character(42),
    receiver character(42),
    term_id bytea,
    curve_id character varying(78),
    shares character varying(78),
    total_shares character varying(78),
    assets character varying(78),
    fees character varying(78),
    vault_type smallint,
    tx_hash character(66) NOT NULL,
    block_number numeric NOT NULL,
    block_timestamp timestamp with time zone,
    block_hash character(66) NOT NULL,
    network character varying(50) NOT NULL,
    tx_index numeric NOT NULL,
    log_index character varying(78) NOT NULL
);


ALTER TABLE intuition_multi_vault.redeemed OWNER TO postgres;

--
-- Name: redeemed_rindexer_id_seq; Type: SEQUENCE; Schema: intuition_multi_vault; Owner: postgres
--

CREATE SEQUENCE intuition_multi_vault.redeemed_rindexer_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE intuition_multi_vault.redeemed_rindexer_id_seq OWNER TO postgres;

--
-- Name: redeemed_rindexer_id_seq; Type: SEQUENCE OWNED BY; Schema: intuition_multi_vault; Owner: postgres
--

ALTER SEQUENCE intuition_multi_vault.redeemed_rindexer_id_seq OWNED BY intuition_multi_vault.redeemed.rindexer_id;


--
-- Name: share_price_changed; Type: TABLE; Schema: intuition_multi_vault; Owner: postgres
--

CREATE TABLE intuition_multi_vault.share_price_changed (
    rindexer_id integer NOT NULL,
    contract_address character(42) NOT NULL,
    term_id bytea,
    curve_id character varying(78),
    share_price character varying(78),
    total_assets character varying(78),
    total_shares character varying(78),
    vault_type smallint,
    tx_hash character(66) NOT NULL,
    block_number numeric NOT NULL,
    block_timestamp timestamp with time zone,
    block_hash character(66) NOT NULL,
    network character varying(50) NOT NULL,
    tx_index numeric NOT NULL,
    log_index character varying(78) NOT NULL
);


ALTER TABLE intuition_multi_vault.share_price_changed OWNER TO postgres;

--
-- Name: share_price_changed_rindexer_id_seq; Type: SEQUENCE; Schema: intuition_multi_vault; Owner: postgres
--

CREATE SEQUENCE intuition_multi_vault.share_price_changed_rindexer_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE intuition_multi_vault.share_price_changed_rindexer_id_seq OWNER TO postgres;

--
-- Name: share_price_changed_rindexer_id_seq; Type: SEQUENCE OWNED BY; Schema: intuition_multi_vault; Owner: postgres
--

ALTER SEQUENCE intuition_multi_vault.share_price_changed_rindexer_id_seq OWNED BY intuition_multi_vault.share_price_changed.rindexer_id;


--
-- Name: triple_created; Type: TABLE; Schema: intuition_multi_vault; Owner: postgres
--

CREATE TABLE intuition_multi_vault.triple_created (
    rindexer_id integer NOT NULL,
    contract_address character(42) NOT NULL,
    creator character(42),
    term_id bytea,
    subject_id bytea,
    predicate_id bytea,
    object_id bytea,
    tx_hash character(66) NOT NULL,
    block_number numeric NOT NULL,
    block_timestamp timestamp with time zone,
    block_hash character(66) NOT NULL,
    network character varying(50) NOT NULL,
    tx_index numeric NOT NULL,
    log_index character varying(78) NOT NULL
);


ALTER TABLE intuition_multi_vault.triple_created OWNER TO postgres;

--
-- Name: triple_created_rindexer_id_seq; Type: SEQUENCE; Schema: intuition_multi_vault; Owner: postgres
--

CREATE SEQUENCE intuition_multi_vault.triple_created_rindexer_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE intuition_multi_vault.triple_created_rindexer_id_seq OWNER TO postgres;

--
-- Name: triple_created_rindexer_id_seq; Type: SEQUENCE OWNED BY; Schema: intuition_multi_vault; Owner: postgres
--

ALTER SEQUENCE intuition_multi_vault.triple_created_rindexer_id_seq OWNED BY intuition_multi_vault.triple_created.rindexer_id;


--
-- Name: atom_created rindexer_id; Type: DEFAULT; Schema: intuition_multi_vault; Owner: postgres
--

ALTER TABLE ONLY intuition_multi_vault.atom_created ALTER COLUMN rindexer_id SET DEFAULT nextval('intuition_multi_vault.atom_created_rindexer_id_seq'::regclass);


--
-- Name: deposited rindexer_id; Type: DEFAULT; Schema: intuition_multi_vault; Owner: postgres
--

ALTER TABLE ONLY intuition_multi_vault.deposited ALTER COLUMN rindexer_id SET DEFAULT nextval('intuition_multi_vault.deposited_rindexer_id_seq'::regclass);


--
-- Name: redeemed rindexer_id; Type: DEFAULT; Schema: intuition_multi_vault; Owner: postgres
--

ALTER TABLE ONLY intuition_multi_vault.redeemed ALTER COLUMN rindexer_id SET DEFAULT nextval('intuition_multi_vault.redeemed_rindexer_id_seq'::regclass);


--
-- Name: share_price_changed rindexer_id; Type: DEFAULT; Schema: intuition_multi_vault; Owner: postgres
--

ALTER TABLE ONLY intuition_multi_vault.share_price_changed ALTER COLUMN rindexer_id SET DEFAULT nextval('intuition_multi_vault.share_price_changed_rindexer_id_seq'::regclass);


--
-- Name: triple_created rindexer_id; Type: DEFAULT; Schema: intuition_multi_vault; Owner: postgres
--

ALTER TABLE ONLY intuition_multi_vault.triple_created ALTER COLUMN rindexer_id SET DEFAULT nextval('intuition_multi_vault.triple_created_rindexer_id_seq'::regclass);


--
-- Name: atom_created atom_created_pkey; Type: CONSTRAINT; Schema: intuition_multi_vault; Owner: postgres
--

ALTER TABLE ONLY intuition_multi_vault.atom_created
    ADD CONSTRAINT atom_created_pkey PRIMARY KEY (rindexer_id);


--
-- Name: deposited deposited_pkey; Type: CONSTRAINT; Schema: intuition_multi_vault; Owner: postgres
--

ALTER TABLE ONLY intuition_multi_vault.deposited
    ADD CONSTRAINT deposited_pkey PRIMARY KEY (rindexer_id);


--
-- Name: redeemed redeemed_pkey; Type: CONSTRAINT; Schema: intuition_multi_vault; Owner: postgres
--

ALTER TABLE ONLY intuition_multi_vault.redeemed
    ADD CONSTRAINT redeemed_pkey PRIMARY KEY (rindexer_id);


--
-- Name: share_price_changed share_price_changed_pkey; Type: CONSTRAINT; Schema: intuition_multi_vault; Owner: postgres
--

ALTER TABLE ONLY intuition_multi_vault.share_price_changed
    ADD CONSTRAINT share_price_changed_pkey PRIMARY KEY (rindexer_id);


--
-- Name: triple_created triple_created_pkey; Type: CONSTRAINT; Schema: intuition_multi_vault; Owner: postgres
--

ALTER TABLE ONLY intuition_multi_vault.triple_created
    ADD CONSTRAINT triple_created_pkey PRIMARY KEY (rindexer_id);


--
-- PostgreSQL database dump complete
--

