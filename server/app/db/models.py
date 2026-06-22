"""SQLAlchemy-модели серверной БД.

Каждый класс в этом файле описывает одну таблицу PostgreSQL.
Исполняемая схема создаётся SQL-скриптами в `scripts/db_scripts/`.
ORM-модели должны оставаться синхронизированными с `010_schema.sql`.
"""

from __future__ import annotations

from datetime import datetime
from typing import Any
from uuid import UUID, uuid4

from sqlalchemy import BigInteger, Boolean, DateTime, Index, String, Text, UniqueConstraint, func, text
from sqlalchemy.dialects.postgresql import JSONB, UUID as PG_UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class TimestampMixin:
    """Общие timestamp-поля для таблиц, где нужны created_at/updated_at."""

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
    )


class Experiment(Base, TimestampMixin):
    """Основная карточка эксперимента.

    PostgreSQL хранит метаданные, статусы и ссылки на объекты в MinIO bronze.
    Сам бинарный сигнал остаётся в object storage.
    """

    __tablename__ = "experiments"
    __table_args__ = (
        Index("ix_experiments_status", "status"),
        Index("ix_experiments_uploaded_at", "uploaded_at"),
    )

    id: Mapped[UUID] = mapped_column(PG_UUID(as_uuid=True), primary_key=True, default=uuid4)
    experiment_id: Mapped[str] = mapped_column(String(64), unique=True, nullable=False)
    display_name: Mapped[str] = mapped_column(Text, nullable=False)
    status: Mapped[str] = mapped_column(String(64), nullable=False)

    storage_bucket: Mapped[str | None] = mapped_column(String(63), nullable=True)
    storage_prefix: Mapped[str | None] = mapped_column(Text, nullable=True)
    source_path: Mapped[str | None] = mapped_column(Text, nullable=True)
    validation_report_path: Mapped[str | None] = mapped_column(Text, nullable=True)
    metadata_json: Mapped[dict[str, Any] | None] = mapped_column(JSONB, nullable=True)

    validation_error_code: Mapped[str | None] = mapped_column(String(128), nullable=True)
    validation_error_message: Mapped[str | None] = mapped_column(Text, nullable=True)
    processing_error_code: Mapped[str | None] = mapped_column(String(128), nullable=True)
    processing_error_message: Mapped[str | None] = mapped_column(Text, nullable=True)

    uploaded_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    accepted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class UploadSession(Base):
    """Сессия ручной загрузки experiment package через Web UI."""

    __tablename__ = "upload_sessions"
    __table_args__ = (
        Index("ix_upload_sessions_experiment_id", "experiment_id"),
        Index("ix_upload_sessions_status", "status"),
        Index(
            "uq_upload_sessions_one_active_per_experiment",
            "experiment_id",
            unique=True,
            postgresql_where=text("status IN ('created', 'uploading', 'completed', 'validating')"),
        ),
    )

    id: Mapped[str] = mapped_column(String(26), primary_key=True)
    experiment_id: Mapped[str] = mapped_column(String(64), nullable=False)
    status: Mapped[str] = mapped_column(String(64), nullable=False)
    tmp_path: Mapped[str] = mapped_column(Text, nullable=False)
    client_id: Mapped[str | None] = mapped_column(String(128), nullable=True)

    expected_files: Mapped[dict[str, Any]] = mapped_column(JSONB, nullable=False)
    uploaded_files: Mapped[dict[str, Any]] = mapped_column(JSONB, nullable=False)

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)


class UploadStorageEvent(Base):
    """Журнал связки upload session с object storage.

    Записи создаются в той же PostgreSQL transaction, что и accepted experiment:
    если transaction не закоммитилась, сервер не считает MinIO upload принятым.
    """

    __tablename__ = "upload_storage_events"
    __table_args__ = (
        Index(
            "ix_upload_storage_events_upload_session_id_created_at",
            "upload_session_id",
            "created_at",
        ),
        Index(
            "ix_upload_storage_events_experiment_id_created_at",
            "experiment_id",
            "created_at",
        ),
    )

    id: Mapped[UUID] = mapped_column(PG_UUID(as_uuid=True), primary_key=True, default=uuid4)
    upload_session_id: Mapped[str] = mapped_column(String(26), nullable=False)
    experiment_id: Mapped[str] = mapped_column(String(64), nullable=False)
    event_type: Mapped[str] = mapped_column(String(128), nullable=False)
    status: Mapped[str] = mapped_column(String(64), nullable=False)
    bucket: Mapped[str | None] = mapped_column(String(63), nullable=True)
    storage_prefix: Mapped[str | None] = mapped_column(Text, nullable=True)
    object_key: Mapped[str | None] = mapped_column(Text, nullable=True)
    message: Mapped[str | None] = mapped_column(Text, nullable=True)
    details: Mapped[dict[str, Any] | None] = mapped_column(JSONB, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)


class UploadOrphanObject(Base):
    """MinIO object, загруженный до failed PostgreSQL commit.

    Эти записи создаются best-effort после rollback основной accepted transaction
    и служат входом для cleanup/manual audit.
    """

    __tablename__ = "upload_orphan_objects"
    __table_args__ = (
        Index("ix_upload_orphan_objects_status_created_at", "status", "created_at"),
        Index("ix_upload_orphan_objects_experiment_id_created_at", "experiment_id", "created_at"),
    )

    id: Mapped[UUID] = mapped_column(PG_UUID(as_uuid=True), primary_key=True, default=uuid4)
    upload_session_id: Mapped[str] = mapped_column(String(26), nullable=False)
    experiment_id: Mapped[str] = mapped_column(String(64), nullable=False)
    bucket: Mapped[str] = mapped_column(String(63), nullable=False)
    storage_prefix: Mapped[str] = mapped_column(Text, nullable=False)
    object_key: Mapped[str] = mapped_column(Text, nullable=False)
    relative_path: Mapped[str] = mapped_column(Text, nullable=False)
    size_bytes: Mapped[int] = mapped_column(BigInteger, nullable=False)
    sha256: Mapped[str | None] = mapped_column(String(64), nullable=True)
    reason: Mapped[str] = mapped_column(String(128), nullable=False)
    status: Mapped[str] = mapped_column(String(64), server_default="pending_cleanup", nullable=False)
    details: Mapped[dict[str, Any] | None] = mapped_column(JSONB, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    resolved_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class ExperimentEvent(Base):
    """Append-only история событий эксперимента."""

    __tablename__ = "experiment_events"
    __table_args__ = (
        Index("ix_experiment_events_experiment_id_created_at", "experiment_id", "created_at"),
    )

    id: Mapped[UUID] = mapped_column(PG_UUID(as_uuid=True), primary_key=True, default=uuid4)
    experiment_id: Mapped[str] = mapped_column(String(64), nullable=False)
    event_type: Mapped[str] = mapped_column(String(128), nullable=False)
    from_status: Mapped[str | None] = mapped_column(String(64), nullable=True)
    to_status: Mapped[str | None] = mapped_column(String(64), nullable=True)
    message: Mapped[str | None] = mapped_column(Text, nullable=True)
    details: Mapped[dict[str, Any] | None] = mapped_column(JSONB, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)


class SourceFile(Base):
    """Файл исходного пакета, принятый сервером и сохранённый в MinIO bronze."""

    __tablename__ = "source_files"
    __table_args__ = (
        UniqueConstraint("bucket", "object_key", name="uq_source_files_bucket_object_key"),
        Index("ix_source_files_experiment_id", "experiment_id"),
    )

    id: Mapped[UUID] = mapped_column(PG_UUID(as_uuid=True), primary_key=True, default=uuid4)
    experiment_id: Mapped[str] = mapped_column(String(64), nullable=False)
    name: Mapped[str] = mapped_column(Text, nullable=False)
    relative_path: Mapped[str] = mapped_column(Text, nullable=False)
    bucket: Mapped[str] = mapped_column(String(63), nullable=False)
    object_key: Mapped[str] = mapped_column(Text, nullable=False)
    size_bytes: Mapped[int] = mapped_column(BigInteger, nullable=False)
    sha256: Mapped[str | None] = mapped_column(String(64), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)


class PipelineRun(Base):
    """Один запуск pipeline-обработки для эксперимента."""

    __tablename__ = "pipeline_runs"
    __table_args__ = (
        Index("ix_pipeline_runs_experiment_id_created_at", "experiment_id", "created_at"),
        Index("ix_pipeline_runs_status", "status"),
    )

    id: Mapped[str] = mapped_column(String(26), primary_key=True)
    experiment_id: Mapped[str] = mapped_column(String(64), nullable=False)
    status: Mapped[str] = mapped_column(String(64), nullable=False)
    trigger_type: Mapped[str] = mapped_column(String(64), nullable=False)
    pipeline_version: Mapped[str | None] = mapped_column(String(128), nullable=True)
    params_json: Mapped[dict[str, Any] | None] = mapped_column(JSONB, nullable=True)
    result_path: Mapped[str | None] = mapped_column(Text, nullable=True)
    heartbeat_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    error_code: Mapped[str | None] = mapped_column(String(128), nullable=True)
    error_message: Mapped[str | None] = mapped_column(Text, nullable=True)
    started_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    finished_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)


class PipelineArtifact(Base):
    """Файл-результат, созданный pipeline run."""

    __tablename__ = "pipeline_artifacts"
    __table_args__ = (
        Index("ix_pipeline_artifacts_pipeline_run_id", "pipeline_run_id"),
        Index("ix_pipeline_artifacts_experiment_id", "experiment_id"),
    )

    id: Mapped[str] = mapped_column(String(26), primary_key=True)
    pipeline_run_id: Mapped[str] = mapped_column(String(26), nullable=False)
    experiment_id: Mapped[str] = mapped_column(String(64), nullable=False)
    name: Mapped[str] = mapped_column(Text, nullable=False)
    kind: Mapped[str] = mapped_column(String(64), nullable=False)
    relative_path: Mapped[str] = mapped_column(Text, nullable=False)
    media_type: Mapped[str | None] = mapped_column(String(128), nullable=True)
    size_bytes: Mapped[int | None] = mapped_column(BigInteger, nullable=True)
    sha256: Mapped[str | None] = mapped_column(String(64), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)


class AuditEvent(Base):
    """События безопасности и административные действия."""

    __tablename__ = "audit_events"
    __table_args__ = (
        Index("ix_audit_events_created_at", "created_at"),
        Index("ix_audit_events_actor_user_id_created_at", "actor_user_id", "created_at"),
    )

    id: Mapped[UUID] = mapped_column(PG_UUID(as_uuid=True), primary_key=True, default=uuid4)
    actor_user_id: Mapped[UUID | None] = mapped_column(PG_UUID(as_uuid=True), nullable=True)
    actor_client_id: Mapped[str | None] = mapped_column(String(128), nullable=True)
    event_type: Mapped[str] = mapped_column(String(128), nullable=False)
    experiment_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    pipeline_run_id: Mapped[str | None] = mapped_column(String(26), nullable=True)
    ip_address: Mapped[str | None] = mapped_column(String(64), nullable=True)
    user_agent: Mapped[str | None] = mapped_column(Text, nullable=True)
    details: Mapped[dict[str, Any] | None] = mapped_column(JSONB, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)


class User(Base):
    """Минимальный пользователь web UI первого стенда."""

    __tablename__ = "users"

    id: Mapped[UUID] = mapped_column(PG_UUID(as_uuid=True), primary_key=True, default=uuid4)
    username: Mapped[str] = mapped_column(String(128), unique=True, nullable=False)
    password_hash: Mapped[str] = mapped_column(Text, nullable=False)
    role: Mapped[str] = mapped_column(String(64), nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
