# Intuition testnet materialized views

Start dev DB 

```bash
docker compose up -d
```

Open: [local.drizzle.studio](https://local.drizzle.studio/)

## Import migrations 

```bash
gunzip -c migrations/rindexer-data.sql.gz > migrations/rindexer-data.sql

PGPASSWORD=rindexer psql -h localhost -p 5440 -U postgres -d postgres -f migrations/rindexer-schema.sql
PGPASSWORD=rindexer psql -h localhost -p 5440 -U postgres -d postgres -f migrations/rindexer-data.sql
PGPASSWORD=rindexer psql -h localhost -p 5440 -U postgres -d postgres -f migrations/00-indexes.sql
PGPASSWORD=rindexer psql -h localhost -p 5440 -U postgres -d postgres -f migrations/01-crypto.sql
PGPASSWORD=rindexer psql -h localhost -p 5440 -U postgres -d postgres -f migrations/02-tables.sql
PGPASSWORD=rindexer psql -h localhost -p 5440 -U postgres -d postgres -f migrations/03-functions.sql
```

## Update views

```sql
SELECT * FROM refresh_all_views();
```

## Index original data

```bash
curl -L https://rindexer.xyz/install.sh | bash -s -- --version 0.27.0
rindexer start indexer
```

### Dump schema

```bash
PGPASSWORD=rindexer pg_dump --dbname=postgres --host=localhost --port=5440 --username=postgres --schema=intuition_multi_vault --schema-only --file=migrations/rindexer-schema.sql
```

### Dump data

```bash
PGPASSWORD=rindexer pg_dump --dbname=postgres --host=localhost --port=5440 --username=postgres --schema=intuition_multi_vault --data-only --file=migrations/rindexer-data.sql
```



