# ADR 0002: MinIO bronze storage for EEG source packages

## Status

Accepted.

## Context

ADR 0001 fixed EEG MVP storage to the local filesystem. The team agreed to
store accepted experiment packages in MinIO: `signal.bin` and
`experiment.json` go to the bronze layer; metadata from `experiment.json`
stays in PostgreSQL with object references.

## Decision

EEG MVP uses MinIO bronze for durable source files and PostgreSQL for metadata.
Duplicate protection uses `experiments.experiment_id` unique and
`source_files (bucket, object_key)` unique.

## Consequences

- Docker Compose includes `minio`, `minio-init`, and SQL init scripts.
- Schema source of truth: `scripts/db_scripts/010_schema.sql`.
- SQLAlchemy models mirror SQL, they do not bootstrap the database.
