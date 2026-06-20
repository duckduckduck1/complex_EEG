-- EEG MVP PostgreSQL schema.
-- Source of truth for database structure. SQLAlchemy models must stay in sync.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username VARCHAR(128) NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    role VARCHAR(64) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE experiments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    experiment_id VARCHAR(64) NOT NULL UNIQUE,
    display_name TEXT NOT NULL,
    status VARCHAR(64) NOT NULL,
    storage_bucket VARCHAR(63),
    storage_prefix TEXT,
    source_path TEXT,
    validation_report_path TEXT,
    metadata_json JSONB,
    validation_error_code VARCHAR(128),
    validation_error_message TEXT,
    processing_error_code VARCHAR(128),
    processing_error_message TEXT,
    uploaded_at TIMESTAMPTZ,
    accepted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX ix_experiments_status ON experiments (status);
CREATE INDEX ix_experiments_uploaded_at ON experiments (uploaded_at);

CREATE TABLE upload_sessions (
    id VARCHAR(26) PRIMARY KEY,
    experiment_id VARCHAR(64) NOT NULL,
    status VARCHAR(64) NOT NULL,
    tmp_path TEXT NOT NULL,
    client_id VARCHAR(128),
    expected_files JSONB NOT NULL,
    uploaded_files JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX ix_upload_sessions_experiment_id ON upload_sessions (experiment_id);
CREATE INDEX ix_upload_sessions_status ON upload_sessions (status);

CREATE TABLE experiment_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    experiment_id VARCHAR(64) NOT NULL,
    event_type VARCHAR(128) NOT NULL,
    from_status VARCHAR(64),
    to_status VARCHAR(64),
    message TEXT,
    details JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX ix_experiment_events_experiment_id_created_at
    ON experiment_events (experiment_id, created_at);

CREATE TABLE source_files (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    experiment_id VARCHAR(64) NOT NULL,
    name TEXT NOT NULL,
    relative_path TEXT NOT NULL,
    bucket VARCHAR(63) NOT NULL,
    object_key TEXT NOT NULL,
    size_bytes BIGINT NOT NULL,
    sha256 VARCHAR(64),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_source_files_bucket_object_key UNIQUE (bucket, object_key)
);

CREATE INDEX ix_source_files_experiment_id ON source_files (experiment_id);

CREATE TABLE pipeline_runs (
    id VARCHAR(26) PRIMARY KEY,
    experiment_id VARCHAR(64) NOT NULL,
    status VARCHAR(64) NOT NULL,
    trigger_type VARCHAR(64) NOT NULL,
    pipeline_version VARCHAR(128),
    params_json JSONB,
    result_path TEXT,
    heartbeat_at TIMESTAMPTZ,
    error_code VARCHAR(128),
    error_message TEXT,
    started_at TIMESTAMPTZ,
    finished_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX ix_pipeline_runs_experiment_id_created_at
    ON pipeline_runs (experiment_id, created_at);
CREATE INDEX ix_pipeline_runs_status ON pipeline_runs (status);

CREATE TABLE pipeline_artifacts (
    id VARCHAR(26) PRIMARY KEY,
    pipeline_run_id VARCHAR(26) NOT NULL,
    experiment_id VARCHAR(64) NOT NULL,
    name TEXT NOT NULL,
    kind VARCHAR(64) NOT NULL,
    relative_path TEXT NOT NULL,
    media_type VARCHAR(128),
    size_bytes BIGINT,
    sha256 VARCHAR(64),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX ix_pipeline_artifacts_pipeline_run_id
    ON pipeline_artifacts (pipeline_run_id);
CREATE INDEX ix_pipeline_artifacts_experiment_id
    ON pipeline_artifacts (experiment_id);

CREATE TABLE audit_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_user_id UUID,
    actor_client_id VARCHAR(128),
    event_type VARCHAR(128) NOT NULL,
    experiment_id VARCHAR(64),
    pipeline_run_id VARCHAR(26),
    ip_address VARCHAR(64),
    user_agent TEXT,
    details JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX ix_audit_events_created_at ON audit_events (created_at);
CREATE INDEX ix_audit_events_actor_user_id_created_at
    ON audit_events (actor_user_id, created_at);
