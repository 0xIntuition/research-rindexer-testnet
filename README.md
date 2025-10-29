# Intuition testnet materialized views

Start dev DB 

```
docker compose up -d
```

Open: [local.drizzle.studio](https://local.drizzle.studio/)

## Import migrations 

```
gunzip -c migrations/rindexer-data.sql.gz > migrations/rindexer-data.sql

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

## Index original data

```
curl -L https://rindexer.xyz/install.sh | bash -s -- --version 0.27.0
rindexer start indexer
```

## Dump schema

```
PGPASSWORD=rindexer pg_dump --dbname=postgres --host=localhost --port=5440 --username=postgres --schema=intuition_multi_vault --schema-only --file=migrations/rindexer-schema.sql
```

## Dump data

```
PGPASSWORD=rindexer pg_dump --dbname=postgres --host=localhost --port=5440 --username=postgres --schema=intuition_multi_vault --data-only --file=migrations/rindexer-data.sql
```



