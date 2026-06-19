# EEG DB owner handoff

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
- source file records;
- validation status and errors;
- pipeline run status;
- pipeline artifact records;
- experiment events;
- audit events.

Filesystem stores:

- `signal.bin`;
- `experiment.json`;
- source logs and journals;
- validation reports;
- pipeline outputs and logs.

## Public DB Contract

Other server layers may rely on these concepts:

```text
users
experiments
upload_sessions
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
- MinIO/S3 storage;
- Airflow fields;
- lakehouse layers;
- universal file catalog;
- non-EEG modalities;
- raw SQL schema as the primary migration mechanism.

The schema source of truth for this service is:

```text
SQLAlchemy models -> Alembic migrations -> PostgreSQL
```

Raw SQL scripts may be used for diagnostics or seed data, but not as the primary
schema definition.

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

