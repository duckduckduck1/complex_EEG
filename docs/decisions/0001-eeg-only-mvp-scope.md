# ADR 0001: EEG-only MVP scope

## Status

Accepted.

## Context

Project `complex_EEG` was designed around one concrete workflow:

1. Flutter application records EEG data locally.
2. The application creates an experiment package.
3. The package contains `signal.bin`, `experiment.json`, and optional logs/journal files.
4. A user uploads the completed package through the web UI.
5. The server validates, stores, processes, and exposes experiment status.

During DB discussion, a broader science lakehouse design was proposed. It included
MinIO, Airflow, microscopy entities, bronze/silver/gold data layers, vessel metrics,
and a universal file catalog.

That design can be useful later, but it changes the bounded context of the current
repository. The current documentation, Flutter implementation plan, server upload
flow, validation flow, and pipeline flow are all written for EEG.

## Decision

`complex_EEG` remains an EEG-only MVP.

The repository is not a general science lakehouse, microscopy platform, or universal
laboratory data platform at this stage.

The MVP scope is:

- local EEG recording;
- local experiment package creation;
- web UI manual upload;
- server-side validation;
- PostgreSQL metadata and status storage;
- filesystem storage for source files and pipeline artifacts;
- server-side EEG processing workflow;
- web UI for experiment status, artifacts, and repeat processing.

## Out of Scope for MVP

The following are explicitly out of scope for the current repository and must not be
added without a new architecture decision:

- microscopy-specific tables or flows;
- vessel metrics;
- anatomy or staining marker dictionaries;
- MDMS compatibility schema;
- MinIO or S3 object storage;
- Airflow orchestration;
- lakehouse bronze/silver/gold layers;
- universal multi-modality file catalog;
- a separate lab-wide data platform.

## Future Direction

A broader laboratory platform may be created later as a separate repository or
service. In that future architecture, `complex_EEG` can become one domain service
integrated into the larger platform through APIs, events, or artifact export.

The current design should therefore avoid hard coupling between API routes and DB
tables. Server code should use repository/service boundaries so that internal DB
changes remain localized.

## Consequences

- The branch `feat/added-db-implementation` must not be merged into `dev` as is.
- Useful ideas from that branch can be reintroduced only if they support the EEG MVP.
- DB ownership is welcome, but it is bounded by the EEG product scope.
- Flutter is treated as an experiment package builder, not as the primary upload client
  for the MVP.
- Web UI manual upload is the primary MVP upload path.

