# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an **Intuition Testnet Materialized Views** project that indexes blockchain data from the Intuition protocol's MultiVault smart contract and transforms it into optimized PostgreSQL materialized views for efficient querying.

**Stack**: Rindexer (v0.27.0) + PostgreSQL 16 + Docker + Drizzle ORM

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
PGPASSWORD=rindexer psql -h localhost -p 5440 -U postgres -d postgres -f migrations/00-indexes.sql
PGPASSWORD=rindexer psql -h localhost -p 5440 -U postgres -d postgres -f migrations/01-crypto.sql
PGPASSWORD=rindexer psql -h localhost -p 5440 -U postgres -d postgres -f migrations/02-position.sql
PGPASSWORD=rindexer psql -h localhost -p 5440 -U postgres -d postgres -f migrations/03-vault.sql
PGPASSWORD=rindexer psql -h localhost -p 5440 -U postgres -d postgres -f migrations/04-term.sql
PGPASSWORD=rindexer psql -h localhost -p 5440 -U postgres -d postgres -f migrations/05-atom.sql
PGPASSWORD=rindexer psql -h localhost -p 5440 -U postgres -d postgres -f migrations/06-triple.sql
PGPASSWORD=rindexer psql -h localhost -p 5440 -U postgres -d postgres -f migrations/07-triple_vault.sql
PGPASSWORD=rindexer psql -h localhost -p 5440 -U postgres -d postgres -f migrations/08-triple_term.sql
PGPASSWORD=rindexer psql -h localhost -p 5440 -U postgres -d postgres -f migrations/09-predicate-aggregates.sql
PGPASSWORD=rindexer psql -h localhost -p 5440 -U postgres -d postgres -f migrations/99-refresh.sql
```

### Refresh Materialized Views

```sql
-- Refresh all views in dependency order
SELECT * FROM refresh_all_views();

-- Or refresh individual views (must follow dependency order)
SELECT refresh_position_view();
SELECT refresh_vault_view();
SELECT refresh_term_view();
SELECT refresh_atom_view();
SELECT refresh_triple_view();
SELECT refresh_triple_vault_view();
SELECT refresh_triple_term_view();
SELECT refresh_predicate_object_view();
SELECT refresh_subject_predicate_view();
```

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
    ├── atom_created
    ├── triple_created
    ├── deposited
    ├── redeemed
    └── share_price_changed
    ↓
Materialized Views (public schema) - 3-Level Dependency Hierarchy
```

### Materialized View Dependency Hierarchy

**Level 0 (Base views - no dependencies):**
- `atom` - Entities in knowledge graph
- `triple` - Relationships between atoms (uses Python UDF for triple ID calculation)
- `position` - User holdings aggregated from deposits/redemptions

**Level 1 (depends on Level 0):**
- `vault` - Vault state and metrics (depends on position + share_price_changed)
- `triple_vault` - Triple vault aggregations (depends on triple + vault)

**Level 2 (depends on Level 1):**
- `term` - Term-level aggregations (depends on vault)
- `triple_term` - Triple term aggregations (depends on triple_vault)

**Level 3 (analytics views):**
- `predicate_object` - Predicate-object relationship analytics
- `subject_predicate` - Subject-predicate relationship analytics

**Critical**: Views must be refreshed in dependency order. Use `refresh_all_views()` to handle this automatically.

### Key Architectural Patterns

1. **CONCURRENT Refresh**: All materialized views support `REFRESH MATERIALIZED VIEW CONCURRENTLY`, allowing queries during refresh. Requires unique indexes on primary keys.

2. **Covering Indexes**: Indexes include computed columns to avoid table lookups (see `migrations/00-indexes.sql` for extensive documentation).

3. **DISTINCT ON Optimization**: Find latest events efficiently using composite indexes with `(vault_id, block_number DESC, log_index DESC)`.

4. **Python UDFs**: Cryptographic functions (Keccak-256) implemented as PostgreSQL functions using Python's `eth_hash` library. See `migrations/01-crypto.sql`.

5. **Idempotent Migrations**: All migrations use `DROP IF EXISTS` for safe re-runs.

## Database Schema Organization

### `intuition_multi_vault` Schema (Raw Events)
Auto-generated by rindexer. Contains 5 event tables:
- Each has `rindexer_id` (primary key), blockchain metadata (tx_hash, block_number, log_index, etc.)
- Data characteristics: deposited (3M+ rows), share_price_changed (278k+ rows), redeemed (~10 rows)

### `public` Schema (Analytics)
Contains 9 materialized views for aggregated data. See dependency hierarchy above.

Custom types defined:
- `vault_type`: ENUM('atom', 'triple', 'counter_triple')
- `term_type`: ENUM('atom', 'triple', 'counter_triple')
- `atom_type`: ENUM('thing', 'person', 'organization', 'account')
- `atom_resolving_status`: ENUM('pending', 'resolved')

Helper functions:
- `keccak256(text)` - Compute Keccak-256 hash
- `calculateCounterTripleId(numeric)` - Calculate counter-triple vault ID
- `safe_utf8_decode(bytea)` - Decode bytea to UTF-8 with error handling

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

See `migrations/00-indexes.sql` for detailed documentation. Index types used:

1. **Composite Indexes**: For DISTINCT ON queries (CRITICAL priority)
   - Example: `(vault_id, block_number DESC, log_index DESC)`
   - Avoids expensive sorts on large tables

2. **Covering Indexes**: Include computed columns to avoid heap fetches
   - Example: `(vault_id) INCLUDE (shares)` for sum aggregations

3. **Partial Indexes**: For active positions
   - Example: `WHERE shares > 0` reduces index size significantly

4. **BRIN Indexes**: Recommended for very large tables with sequential inserts
   - Block Range INdexes for time-series data

5. **Expression Indexes**: For hex-encoded lookups
   - Example: `encode(term_id, 'hex')` for term ID queries

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
