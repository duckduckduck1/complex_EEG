"""Тесты SQLAlchemy-моделей.

Эти тесты проверяют Python-описание схемы БД без подключения к PostgreSQL.
"""

from app.db.base import Base
from app.db.models import Experiment, SourceFile, UploadOrphanObject, UploadSession, UploadStorageEvent


def test_all_expected_tables_are_registered() -> None:
    """Base.metadata должен содержать все таблицы из storage.md."""

    assert set(Base.metadata.tables) == {
        "experiments",
        "upload_sessions",
        "upload_storage_events",
        "upload_orphan_objects",
        "experiment_events",
        "source_files",
        "pipeline_runs",
        "pipeline_artifacts",
        "audit_events",
        "users",
    }


def test_experiment_model_matches_storage_contract() -> None:
    """Experiment должен иметь ключевые поля карточки эксперимента."""

    columns = Experiment.__table__.c

    assert columns.experiment_id.unique is True
    assert columns.experiment_id.nullable is False
    assert columns.display_name.nullable is False
    assert columns.status.nullable is False
    assert columns.metadata_json.nullable is True
    assert columns.storage_bucket.nullable is True
    assert columns.storage_prefix.nullable is True


def test_source_file_bucket_object_key_unique() -> None:
    """Пара bucket+object_key уникальна — защита от дублей объектов в MinIO."""

    constraints = {
        constraint.name
        for constraint in SourceFile.__table__.constraints
        if constraint.name
    }

    assert "uq_source_files_bucket_object_key" in constraints

    columns = SourceFile.__table__.c
    assert columns.bucket.nullable is False
    assert columns.object_key.nullable is False


def test_upload_session_model_uses_ulid_primary_key() -> None:
    """UploadSession.id хранит ULID как строку."""

    columns = UploadSession.__table__.c

    assert columns.id.primary_key is True
    assert columns.id.type.length == 26
    assert columns.experiment_id.nullable is False
    assert columns.expected_files.nullable is False
    assert columns.uploaded_files.nullable is False


def test_upload_storage_event_model_logs_minio_commit_boundary() -> None:
    """UploadStorageEvent фиксирует связь upload session с MinIO object keys."""

    columns = UploadStorageEvent.__table__.c

    assert columns.upload_session_id.nullable is False
    assert columns.experiment_id.nullable is False
    assert columns.event_type.nullable is False
    assert columns.status.nullable is False
    assert columns.bucket.nullable is True
    assert columns.object_key.nullable is True


def test_upload_orphan_object_model_tracks_failed_commit_objects() -> None:
    """UploadOrphanObject хранит MinIO objects, оставшиеся после failed DB commit."""

    columns = UploadOrphanObject.__table__.c

    assert columns.upload_session_id.nullable is False
    assert columns.experiment_id.nullable is False
    assert columns.bucket.nullable is False
    assert columns.object_key.nullable is False
    assert columns.reason.nullable is False
    assert columns.status.nullable is False


def test_required_indexes_exist() -> None:
    """Минимальные индексы из storage.md должны быть объявлены в моделях."""

    index_names = {
        index.name
        for table in Base.metadata.tables.values()
        for index in table.indexes
    }

    assert "ix_experiments_status" in index_names
    assert "ix_upload_sessions_status" in index_names
    assert "uq_upload_sessions_one_active_per_experiment" in index_names
    assert "ix_upload_storage_events_upload_session_id_created_at" in index_names
    assert "ix_upload_orphan_objects_status_created_at" in index_names
    assert "ix_pipeline_runs_status" in index_names
    assert "ix_audit_events_created_at" in index_names
