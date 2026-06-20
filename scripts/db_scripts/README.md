# Database init scripts

PostgreSQL schema for EEG MVP is defined here, not in Alembic autogenerate.

## Layout

```text
scripts/db_scripts/
  010_schema.sql          -- tables, indexes, constraints
  090_seed_dev.sql        -- optional dev seed
  checks/
    001_schema_readiness.sql
```

## Docker Compose

On first start, PostgreSQL runs files from this directory in lexical order via
`/docker-entrypoint-initdb.d`.

To re-apply schema on an existing volume, drop the database volume or run
`010_schema.sql` manually against a fresh database.

## MinIO buckets

Bucket creation lives in `scripts/minio/010_init_buckets.sh` and is executed by
the `minio-init` Compose service.

## Contract sync

After changing `010_schema.sql`, update:

- `server/app/db/models.py`
- `docs/implementation/server/storage.md`
- relevant server tests

Alembic remains available for future incremental migrations, but the first
stand uses SQL init scripts as the source of truth.
