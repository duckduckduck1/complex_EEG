# EEG DB owner handoff

Current task list for the DB owner lives in
`docs/implementation/server/db_owner_tasks.md`.

## Purpose

This document describes how DB ownership works for the current `complex_EEG` MVP.
It is written for the contributor who owns the PostgreSQL schema and migration layer.

The DB owner may improve the database design, but must keep the project inside the
EEG-only bounded context defined in
`docs/decisions/0001-eeg-only-mvp-scope.md`.

## Product Boundary

The current product is an EEG experiment service.

Flutter is responsible for recording data and producing a valid experiment package.
The MVP upload path is the web UI.

Expected experiment package:

```text
{experiment_folder}/
  signal.bin
  experiment.json
  journal.ndjson optional
  app.log optional
```

`signal.bin` contains processed EEG amplitude values in binary format. PostgreSQL
does not store the binary signal.

`experiment.json` is the metadata contract between the recording application and the
server.

## Current Storage Decisions

PostgreSQL stores:

- users;
- experiment metadata;
- upload sessions;
- upload storage events;
- orphan object records for failed accepted commits;
- source file records;
- validation status and errors;
- pipeline run status;
- pipeline artifact records;
- experiment events;
- audit events.

MinIO bronze stores accepted source package files:

- `signal.bin`;
- `experiment.json`;
- source logs and journals;

Filesystem stores only staging/cache and derived local outputs:

- validation reports;
- pipeline outputs and logs.

After accepted MinIO upload and successful PostgreSQL commit,
`experiments/{experiment_id}/source/` is deleted. If PostgreSQL commit fails
after MinIO upload, local source remains for retry/audit and uploaded MinIO
objects are logged best-effort in `upload_orphan_objects`.

## Public DB Contract

Other server layers may rely on these concepts:

```text
users
experiments
upload_sessions
upload_storage_events
upload_orphan_objects
source_files
experiment_events
pipeline_runs
pipeline_artifacts
audit_events
```

Important stable fields:

```text
experiments.experiment_id
experiments.display_name
experiments.status
experiments.metadata_json
upload_sessions.id
upload_sessions.experiment_id
pipeline_runs.id
pipeline_runs.experiment_id
```

Upload consistency rules:

- `experiments.experiment_id` is unique.
- Active `upload_sessions(experiment_id)` are unique by partial unique index.
- `complete` uses row-level lock on upload session via `SELECT ... FOR UPDATE`.
- Accepted metadata is committed only after MinIO upload and object readability
  checks.
- `source_files(bucket, object_key)` is unique.

`experiment_id` is the external stable identifier for an EEG experiment. It is
generated before upload and is checked by the server for uniqueness.

`display_name` is human-readable and may repeat unless DB owner explicitly proposes
a scoped uniqueness rule.

## Ownership Rules

The DB owner may change:

- indexes;
- constraints;
- nullable flags;
- foreign keys;
- Alembic migrations;
- repository query implementation;
- user-to-experiment ownership fields;
- event/audit structure;
- validation-related DB fields.

The DB owner must not add without a new architecture decision:

- microscopy entities;
- Airflow fields;
- lakehouse layers;
- universal file catalog;
- non-EEG modalities;
- raw SQL schema as the primary migration mechanism.

The schema source of truth for this service is:

```text
scripts/db_scripts/010_schema.sql -> PostgreSQL
server/app/db/models.py           -> ORM mirror
scripts/minio/010_init_buckets.sh -> MinIO buckets
```

Alembic remains for future incremental migrations after the first stand. Raw SQL
init scripts are the primary schema definition for the first stand.

## Immediate DB Tasks

The next DB work should be done in a new branch from `dev`:

```bash
git switch dev
git pull origin dev
git switch -c feature/eeg-db-review
```

Recommended task list:

1. Review current EEG models in `server/app/db/models.py`.
2. Check the models against `docs/implementation/server/storage.md`.
3. Propose minimal changes for user ownership:
   - who uploaded the experiment;
   - who owns the experiment;
   - who can see it in web UI.
4. Confirm uniqueness rule for `experiment_id`.
5. Add or adjust DB constraints and indexes.
6. Generate the first Alembic migration.
7. Verify:
   - `pytest`;
   - `alembic upgrade head`;
   - `alembic downgrade -1`;
   - `alembic upgrade head`.
8. Open a PR into `dev` and explain every schema decision.

## Review Questions

Every DB change should answer:

1. Which EEG use case does this support?
2. Which API or server flow will use it?
3. Can this be represented in `metadata_json` for now?
4. Does this introduce a new product domain?
5. Does this make future upload, validation, or processing simpler?

If a proposed table or service does not support a current EEG use case, it should not
be added to the MVP.

## Branch `feat/added-db-implementation`

The branch `feat/added-db-implementation` should be closed without merge.

Reason:

- it is useful as a future science lakehouse concept;
- it changes the current bounded context;
- it adds microscopy, MinIO, Airflow, lakehouse layers, and a universal file catalog;
- those changes conflict with the current EEG-only MVP.

Useful ideas from that branch can be reintroduced later through focused EEG-specific
PRs.
