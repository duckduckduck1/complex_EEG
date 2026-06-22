"""Tests that SQL init scripts stay aligned with ORM contract."""

from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
SCHEMA_SQL = REPO_ROOT / "scripts" / "db_scripts" / "010_schema.sql"


def test_schema_sql_declares_core_tables() -> None:
    sql = SCHEMA_SQL.read_text(encoding="utf-8")

    for table_name in (
        "users",
        "experiments",
        "upload_sessions",
        "upload_storage_events",
        "upload_orphan_objects",
        "experiment_events",
        "source_files",
        "pipeline_runs",
        "pipeline_artifacts",
        "audit_events",
    ):
        assert f"CREATE TABLE {table_name}" in sql


def test_schema_sql_declares_duplicate_protection() -> None:
    sql = SCHEMA_SQL.read_text(encoding="utf-8")

    assert "experiment_id VARCHAR(64) NOT NULL UNIQUE" in sql
    assert "uq_source_files_bucket_object_key" in sql
    assert "storage_bucket VARCHAR(63)" in sql
    assert "bucket VARCHAR(63) NOT NULL" in sql
    assert "object_key TEXT NOT NULL" in sql
    assert "CREATE TABLE upload_storage_events" in sql
    assert "CREATE TABLE upload_orphan_objects" in sql
    assert "ix_upload_storage_events_upload_session_id_created_at" in sql
    assert "uq_upload_sessions_one_active_per_experiment" in sql


def test_compose_mounts_db_init_scripts() -> None:
    compose = (REPO_ROOT / "docker-compose.yml").read_text(encoding="utf-8")

    assert "./scripts/db_scripts:/docker-entrypoint-initdb.d:ro" in compose
    assert "minio-init" in compose
    assert "./scripts/minio:/scripts/minio:ro" in compose
