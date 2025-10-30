# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an **Intuition Testnet Real-Time Indexer** project that indexes blockchain data from the Intuition protocol's MultiVault smart contract and transforms it into optimized PostgreSQL tables with real-time updates via triggers.

**Stack**: Rindexer (v0.27.0) + PostgreSQL 16 + Docker + Drizzle ORM + Database Triggers

**Contract**: MultiVault at `0x2Ece8D4dEdcB9918A398528f3fa4688b1d2CAB91` on testnet (chain ID 13579)

## Essential Commands

### Initial Setup

```bash
# Start services (PostgreSQL on port 5440, Drizzle Studio on 4983)
docker compose up -d

# Import data (first time only - migrations must run in order)
gunzip -c migrations/rindexer-data.sql.gz > migrations/rindexer-data.sql

# Run migrations sequentially
PGPASSWORD=rindexer psql -h localhost -p 5440 -U postgres -d postgres -f migrations/rindexer-schema.sql
PGPASSWORD=rindexer psql -h localhost -p 5440 -U postgres -d postgres -f migrations/rindexer-data.sql
PGPASSWORD=rindexer psql -h localhost -p 5440 -U postgres -d postgres -f migrations/01-crypto.sql
PGPASSWORD=rindexer psql -h localhost -p 5440 -U postgres -d postgres -f migrations/02-tables.sql
PGPASSWORD=rindexer psql -h localhost -p 5440 -U postgres -d postgres -f migrations/03-trigger-functions.sql
```

**Note**: With trigger-based tables, data updates happen automatically in real-time as rindexer inserts events. No manual refresh operations are required.

### Rindexer Indexing

```bash
# Install rindexer (specific version required)
curl -L https://rindexer.xyz/install.sh | bash -s -- --version 0.27.0

# Start indexing from blockchain (starts at block 8092570)
rindexer start indexer
```

### Database Access

```bash
# Drizzle Studio UI
open http://localhost:4983

# Direct psql connection
PGPASSWORD=rindexer psql -h localhost -p 5440 -U postgres -d postgres
```

### Data Export/Backup

```bash
# Dump schema only
PGPASSWORD=rindexer pg_dump --dbname=postgres --host=localhost --port=5440 \
  --username=postgres --schema=intuition_multi_vault --schema-only \
  --file=migrations/rindexer-schema.sql

# Dump data only
PGPASSWORD=rindexer pg_dump --dbname=postgres --host=localhost --port=5440 \
  --username=postgres --schema=intuition_multi_vault --data-only \
  --file=migrations/rindexer-data.sql

# Compress large data dumps
gzip migrations/rindexer-data.sql
```

## Architecture

### Data Flow Pipeline

```
Blockchain Events (MultiVault Contract)
    ↓
Rindexer Indexer (indexes 5 event types)
    ↓
Raw Event Tables (intuition_multi_vault schema)
    ├── atom_created       → triggers update_atom()
    ├── triple_created     → triggers update_triple()
    ├── deposited          → triggers update_position_deposit()
    ├── redeemed           → triggers update_position_redeem()
    └── share_price_changed → triggers update_vault_from_share_price()
    ↓
Trigger Functions (cascade updates through 4 levels)
    ↓
Analytics Tables (public schema) - Real-time, no manual refresh
```

### Trigger-Based Table Dependency Hierarchy

**Level 0 (Base tables - triggered by raw events):**
- `atom` - Entities in knowledge graph (triggered by atom_created)
- `triple` - Relationships between atoms (triggered by triple_created, uses Python UDF)
- `position` - User holdings (triggered by deposited + redeemed events)

**Level 1 (Cascading triggers from Level 0):**
- `vault` - Vault state and metrics (triggered by share_price_changed + position changes)
- `triple_vault` - Triple vault aggregations (triggered by triple + vault changes)

**Level 2 (Cascading triggers from Level 1):**
- `term` - Term-level aggregations (triggered by vault changes)
- `triple_term` - Triple term aggregations (triggered by triple_vault changes)

**Level 3 (Analytics tables - triggered by Level 2):**
- `predicate_object` - Predicate-object relationship analytics (triggered by triple + triple_term changes)
- `subject_predicate` - Subject-predicate relationship analytics (triggered by triple + triple_term changes)

**Critical**: All updates happen automatically via cascading triggers. Tables are always up-to-date with latest blockchain events, with out-of-order event handling via block/log_index comparison.

### Key Architectural Patterns

1. **Real-Time Trigger Updates**: PostgreSQL triggers automatically update analytics tables as raw events arrive. No manual refresh operations required. Updates cascade through 4 dependency levels.

2. **Out-of-Order Event Handling**: All tables include `last_updated_block` and `last_updated_log_index` tracking columns. Triggers use conditional logic to only update if new events are chronologically later: `(block_number, log_index)` tuple comparison.

3. **Aggregation Triggers**: Higher-level tables (term, triple_term, analytics) use triggers that recalculate GROUP BY aggregations when upstream tables change. Ensures consistency across dependency hierarchy.

4. **Position Table Complexity**: Separate triggers for deposit and redeem events. Maintains both "current shares" (from latest event) and "historical totals" (accumulated across all events), handling out-of-order arrivals correctly.

5. **Python UDFs**: Cryptographic functions (Keccak-256) implemented as PostgreSQL functions using Python's `eth_hash` library. Called from triggers for counter-triple ID calculation. See `migrations/01-crypto.sql`.

6. **Idempotent Migrations**: All migrations use `DROP IF EXISTS` and `ON CONFLICT DO UPDATE` for safe re-runs and upserts.

## Database Schema Organization

### `intuition_multi_vault` Schema (Raw Events)
Auto-generated by rindexer. Contains 5 event tables:
- Each has `rindexer_id` (primary key), blockchain metadata (tx_hash, block_number, log_index, etc.)
- Data characteristics: deposited (3M+ rows), share_price_changed (278k+ rows), redeemed (~10 rows)

### `public` Schema (Analytics)
Contains 9 regular tables updated in real-time via triggers. See dependency hierarchy above.

Custom types defined:
- `vault_type`: ENUM('Atom', 'Triple', 'CounterTriple')
- `term_type`: ENUM('Atom', 'Triple', 'CounterTriple')
- `atom_type`: ENUM('Unknown', 'Account', 'Thing', 'Person', 'Organization', etc.)
- `atom_resolving_status`: ENUM('Pending', 'Resolved', 'Failed')

Helper functions:
- `keccak256(bytea)` - Compute Keccak-256 hash (Python UDF)
- `calculateCounterTripleId(bytea)` - Calculate counter-triple vault ID (Python UDF)
- `safe_utf8_decode(bytea)` - Decode bytea to UTF-8 with error handling (PL/pgSQL)

Trigger functions (see `migrations/03-trigger-functions.sql`):
- Level 0: `update_atom()`, `update_triple()`, `update_position_deposit()`, `update_position_redeem()`
- Level 1: `update_vault_from_share_price()`, `update_vault_position_count()`, `update_triple_vault_from_vault()`, `update_triple_vault_from_triple()`
- Level 2: `update_term_from_vault()`, `update_triple_term_from_triple_vault()`
- Level 3: `update_predicate_object_from_triple()`, `update_predicate_object_from_triple_term()`, `update_subject_predicate_from_triple()`, `update_subject_predicate_from_triple_term()`

## Domain Model

**Core Concepts** (see `docs/multivault.md` for full details):

- **Atoms**: Individual entities in the knowledge graph (nodes). Each atom has a vault.
- **Triples**: Relationships between atoms in subject-predicate-object format (edges). Each triple has two vaults:
  - Type 1: "pro" or "for" the relationship
  - Type 2: "con" or "against" the relationship (counter-triple)
- **Vaults**: ERC4626-style vaults with bonding curves. Each atom/triple has associated vault(s).
- **Positions**: User holdings (shares) in vaults. Users deposit assets to mint shares, redeem shares to receive assets.

**Vault Operations**:
- Create atoms/triples with initial deposits
- Deposit assets → mint shares (bonding curve pricing)
- Redeem shares → receive assets (minus fees)
- Fee structure: protocol fee, entry fee, exit fee, atom wallet fee

## Performance Considerations

### Large Dataset Characteristics
- **deposited table**: 3M+ rows (largest table)
- **share_price_changed table**: 278k+ rows
- **redeemed table**: ~10 rows (very small)

### Index Strategy

See `migrations/00-indexes.sql` for detailed documentation on raw event table indexes.
See `migrations/02-tables.sql` for analytics table indexes.

Index types used:

1. **Composite Indexes on Raw Events**: For efficient DISTINCT ON queries in original trigger logic
   - Example: `(receiver, term_id, curve_id, block_number DESC, log_index DESC)` on deposited table
   - Critical for position calculation triggers

2. **Primary Key Indexes on Analytics Tables**: Enable efficient ON CONFLICT DO UPDATE in triggers
   - Example: `(account_id, term_id, curve_id)` on position table
   - Example: `(term_id, curve_id)` on vault table

3. **Partial Indexes**: For active positions and significant holdings
   - Example: `WHERE shares > 0` on position table
   - Reduces index size by 20-50%

4. **Covering Indexes**: For analytics queries (market cap, position counts)
   - Example: `(market_cap DESC)` on vault table
   - Example: `(total_market_cap DESC)` on term table

5. **Expression Indexes on Raw Events**: For hex-encoded lookups
   - Example: `encode(term_id, 'hex')` for term ID queries

### Trigger Performance Considerations

**Per-Event Overhead**:
- Each raw event triggers 1-7 function executions cascading through dependency hierarchy
- Worst case: `deposited` event on triple vault executes 7 triggers (position → vault → term + triple_vault → triple_term → analytics)
- Average case: ~2-3 trigger executions per event

**Optimization**:
- Triggers use conditional logic to skip unnecessary updates (out-of-order events)
- Aggregation queries are kept simple (avoid complex CTEs in trigger context)
- Indexes on primary keys enable fast ON CONFLICT lookups
- Position count recalculations use covering indexes

**Monitoring**:
```sql
-- Check trigger execution (if performance issues arise)
SELECT schemaname, tablename, n_tup_ins, n_tup_upd
FROM pg_stat_user_tables
WHERE schemaname = 'public'
ORDER BY n_tup_ins + n_tup_upd DESC;
```

### PostgreSQL Tuning (docker-compose.yml)

Performance-tuned for analytics workloads:
- `work_mem=256MB` - Large sort/hash operations
- `shared_buffers=2GB` - Cache frequently accessed data
- `effective_cache_size=6GB` - Query planner optimization
- `max_parallel_workers=8` - Parallel query execution

### Custom PostgreSQL Image

See `postgres/Dockerfile`. Custom build includes:
- PL/Python3 extension for cryptographic functions
- Based on official postgres:16 image

## Configuration

### Environment Variables (.env)
```
DATABASE_URL=postgresql://postgres:rindexer@localhost:5440/postgres
POSTGRES_PASSWORD=rindexer
```

### Rindexer Configuration (rindexer.yaml)
- Project: `intuition`
- Type: `no-code` (YAML-configured, no custom Rust code)
- Network: testnet (chain ID 13579)
- Contract: MultiVault at `0x2Ece8D4dEdcB9918A398528f3fa4688b1d2CAB91`
- Start Block: 8092570
- Events Indexed: AtomCreated, TripleCreated, Deposited, Redeemed, SharePriceChanged
- Health Check: Port 8888

## Git LFS

Large compressed data files tracked with Git LFS. See `.gitattributes` for configuration.

```bash
# Files tracked: migrations/*.gz (~184MB compressed)
# Ensure Git LFS is installed before cloning
git lfs install
```
