# Intuition testnet materialized views

## Index original data

```
curl -L https://rindexer.xyz/install.sh | bash -s -- --version 0.27.0
docker compose up -d
rindexer start indexer
```

## Dump schema

```
PGPASSWORD=rindexer pg_dump --dbname=postgres --host=localhost --port=5440 --username=postgres --schema=intuition_multi_vault --schema-only --file=schema.sql
```

## Dump data

```
PGPASSWORD=rindexer pg_dump --dbname=postgres --host=localhost --port=5440 --username=postgres --schema=intuition_multi_vault --data-only --file=data.sql
```


## Import migrations 

```
gunzip -c data.sql.gz > data.sql

PGPASSWORD=rindexer psql -h localhost -p 5440 -U postgres -d postgres -f schema.sql
PGPASSWORD=rindexer psql -h localhost -p 5440 -U postgres -d postgres -f data.sql
PGPASSWORD=rindexer psql -h localhost -p 5440 -U postgres -d postgres -f migrations/00-indexes.sql
PGPASSWORD=rindexer psql -h localhost -p 5440 -U postgres -d postgres -f migrations/01-crypto.sql
PGPASSWORD=rindexer psql -h localhost -p 5440 -U postgres -d postgres -f migrations/02-position.sql
PGPASSWORD=rindexer psql -h localhost -p 5440 -U postgres -d postgres -f migrations/03-vault.sql
PGPASSWORD=rindexer psql -h localhost -p 5440 -U postgres -d postgres -f migrations/04-term.sql
PGPASSWORD=rindexer psql -h localhost -p 5440 -U postgres -d postgres -f migrations/05-atom.sql
PGPASSWORD=rindexer psql -h localhost -p 5440 -U postgres -d postgres -f migrations/06-triple.sql
PGPASSWORD=rindexer psql -h localhost -p 5440 -U postgres -d postgres -f migrations/07-triple_vault.sql

```
```
