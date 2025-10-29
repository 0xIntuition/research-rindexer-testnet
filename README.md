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
PGPASSWORD=rindexer psql -h localhost -p 5440 -U postgres -d postgres -f migrations/position.sql
PGPASSWORD=rindexer psql -h localhost -p 5440 -U postgres -d postgres -f migrations/vault.sql

```
```
