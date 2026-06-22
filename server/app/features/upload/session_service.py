"""Service-слой upload sessions.

Этот модуль держит бизнес-правила создания, чтения и отмены upload session.
Он не зависит от FastAPI и почти не зависит от SQLAlchemy: наружу ему нужен
repository-объект с маленьким набором методов. Поэтому правила можно тестировать
без реальной PostgreSQL, а DB owner сможет менять внутренности репозитория без
переписывания API-логики.
"""

from __future__ import annotations

import logging
import secrets
import shutil
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Protocol

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.config import settings
from app.db.models import (
    Experiment,
    ExperimentEvent,
    PipelineRun,
    SourceFile,
    UploadSession,
    UploadOrphanObject,
    UploadStorageEvent,
)
from app.features.upload.bronze_storage import (
    BronzeObjectStorage,
    BronzeStorageError,
    BronzeUploadResult,
    NoopBronzeObjectStorage,
)
from app.features.upload.promotion import (
    UploadPromotionError,
    UploadPromotionResult,
    build_experiment_dir,
    promote_staged_upload,
)
from app.features.upload.staging import UploadStagingResult, build_upload_session_dir
from app.features.validation.package_validator import (
    EXPERIMENT_ID_PATTERN,
    ValidationResult,
    validate_experiment_package,
)
from app.features.validation.report_writer import write_validation_report


CROCKFORD_BASE32 = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
REQUIRED_UPLOAD_FILES = ("signal.bin", "experiment.json")
OPTIONAL_UPLOAD_FILES = ("journal.ndjson", "app.log")
DEFAULT_UPLOAD_FILES = REQUIRED_UPLOAD_FILES + OPTIONAL_UPLOAD_FILES
ACTIVE_UPLOAD_SESSION_STATUSES = frozenset({"created", "uploading", "completed", "validating"})
FINAL_UPLOAD_SESSION_STATUSES = frozenset({"accepted", "failed", "expired", "cancelled"})
UPLOAD_SOURCE_DIR_NAME = "source"
VALIDATION_REPORT_FILE_NAME = "validation_report.json"
PRIMARY_PIPELINE_TRIGGER_TYPE = "auto_primary"
PIPELINE_RUN_STATUS_QUEUED = "queued"

logger = logging.getLogger(__name__)


class UploadSessionServiceError(ValueError):
    """Базовая ошибка service-слоя upload sessions."""


class UploadSessionAlreadyExistsError(UploadSessionServiceError):
    """Для experiment_id уже есть зарегистрированный experiment или активная upload session."""


class ExperimentAlreadyRegisteredError(UploadSessionAlreadyExistsError):
    """experiment_id уже зарегистрирован в серверной карточке эксперимента."""


class ActiveUploadSessionAlreadyExistsError(UploadSessionAlreadyExistsError):
    """Для experiment_id уже есть активная upload session."""


class UploadSessionNotFoundError(UploadSessionServiceError):
    """Upload session не найдена."""


class UploadSessionStateConflictError(UploadSessionServiceError):
    """Операция невозможна для текущего статуса upload session."""


class UploadSessionIncompleteError(UploadSessionServiceError):
    """Upload session нельзя завершить, потому что пакет ещё неполный."""


class UploadObjectStorageUnavailableError(UploadSessionServiceError):
    """Accepted package не удалось сохранить в bronze object storage."""


class UploadDatabaseCommitError(UploadSessionServiceError):
    """PostgreSQL transaction не смогла зафиксировать accepted upload."""


class UploadLocalCleanupError(UploadSessionServiceError):
    """Сервер не смог удалить локальную source-копию после accepted commit."""


@dataclass(frozen=True)
class UploadSessionView:
    """API-safe представление upload session без внутренних filesystem paths."""

    upload_session_id: str
    experiment_id: str
    status: str
    expected_files: list[str]
    uploaded_files: list[str]
    expires_at: datetime


@dataclass(frozen=True)
class UploadFileTarget:
    """Безопасные пути для потоковой записи одного upload-файла."""

    upload_session_id: str
    file_name: str
    part_path: Path
    final_path: Path


@dataclass(frozen=True)
class UploadCompletionResult:
    """Результат синхронного complete upload."""

    upload_session_id: str
    experiment_id: str
    status: str
    validation_result: ValidationResult | None
    promotion_result: UploadPromotionResult | None
    bronze_upload_result: BronzeUploadResult | None

    @property
    def accepted(self) -> bool:
        return self.status == "accepted"


class UploadSessionRepository(Protocol):
    """Минимальный контракт хранилища, который нужен service-слою."""

    def has_registered_experiment(self, experiment_id: str) -> bool:
        """True, если experiment_id уже зарегистрирован сервером."""

    def find_active_session_by_experiment_id(self, experiment_id: str) -> UploadSession | None:
        """Возвращает активную session для experiment_id, если она есть."""

    def get_by_id(self, upload_session_id: str) -> UploadSession | None:
        """Возвращает upload session по ULID."""

    def get_by_id_for_update(self, upload_session_id: str) -> UploadSession | None:
        """Возвращает upload session и блокирует строку до commit/rollback."""

    def add(self, upload_session: UploadSession) -> None:
        """Добавляет новую upload session в unit of work."""

    def record_accepted_experiment(
        self,
        *,
        upload_session: UploadSession,
        promotion_result: UploadPromotionResult,
        bronze_upload_result: BronzeUploadResult,
        validation_result: ValidationResult,
        accepted_at: datetime,
    ) -> None:
        """Сохраняет accepted experiment и source file inventory."""

    def record_orphan_objects(
        self,
        *,
        upload_session: UploadSession,
        bronze_upload_result: BronzeUploadResult,
        reason: str,
        details: dict[str, object],
    ) -> None:
        """Логирует MinIO objects, оставшиеся после failed accepted transaction."""

    def refresh_upload_session(self, upload_session: UploadSession) -> None:
        """Синхронизирует ORM object с PostgreSQL после rollback."""

    def commit(self) -> None:
        """Фиксирует изменения."""

    def rollback(self) -> None:
        """Откатывает текущую unit of work после ошибки commit."""


class SqlAlchemyUploadSessionRepository:
    """SQLAlchemy-реализация repository для PostgreSQL.

    Важно: здесь нет сложных транзакционных гарантий уникальности активной
    session. На первом шаге API получает рабочий слой. Финальную защиту от race
    conditions DB owner должен закрыть constraint'ами или transaction locking.
    """

    def __init__(self, db: Session) -> None:
        self._db = db

    def has_registered_experiment(self, experiment_id: str) -> bool:
        statement = select(Experiment.id).where(Experiment.experiment_id == experiment_id)
        return self._db.execute(statement).first() is not None

    def find_active_session_by_experiment_id(self, experiment_id: str) -> UploadSession | None:
        statement = select(UploadSession).where(
            UploadSession.experiment_id == experiment_id,
            UploadSession.status.in_(ACTIVE_UPLOAD_SESSION_STATUSES),
        )
        return self._db.execute(statement).scalars().first()

    def get_by_id(self, upload_session_id: str) -> UploadSession | None:
        return self._db.get(UploadSession, upload_session_id)

    def get_by_id_for_update(self, upload_session_id: str) -> UploadSession | None:
        statement = (
            select(UploadSession)
            .where(UploadSession.id == upload_session_id)
            .with_for_update()
        )
        return self._db.execute(statement).scalars().first()

    def add(self, upload_session: UploadSession) -> None:
        self._db.add(upload_session)

    def record_accepted_experiment(
        self,
        *,
        upload_session: UploadSession,
        promotion_result: UploadPromotionResult,
        bronze_upload_result: BronzeUploadResult,
        validation_result: ValidationResult,
        accepted_at: datetime,
    ) -> None:
        experiment = Experiment(
            experiment_id=promotion_result.experiment_id,
            # Пока display_name не хранится в upload_sessions. На первом стенде
            # используем experiment_id, чтобы не расширять DB-схему в API-ветке.
            display_name=promotion_result.experiment_id,
            status="accepted",
            storage_bucket=bronze_upload_result.bucket,
            storage_prefix=bronze_upload_result.storage_prefix,
            source_path=None,
            validation_report_path=str(promotion_result.validation_report_path),
            metadata_json=validation_result.metadata,
            uploaded_at=upload_session.created_at,
            accepted_at=accepted_at,
        )
        self._db.add(experiment)

        for source_file in bronze_upload_result.source_files:
            self._db.add(
                SourceFile(
                    experiment_id=promotion_result.experiment_id,
                    name=source_file.name,
                    relative_path=source_file.relative_path,
                    bucket=source_file.bucket,
                    object_key=source_file.object_key,
                    size_bytes=source_file.size_bytes,
                    sha256=source_file.sha256,
                )
            )
            self._db.add(
                UploadStorageEvent(
                    upload_session_id=upload_session.id,
                    experiment_id=promotion_result.experiment_id,
                    event_type="minio_object_uploaded",
                    status="succeeded",
                    bucket=source_file.bucket,
                    storage_prefix=bronze_upload_result.storage_prefix,
                    object_key=source_file.object_key,
                    message="Source file uploaded and verified in MinIO bronze",
                    details={
                        "relative_path": source_file.relative_path,
                        "size_bytes": source_file.size_bytes,
                        "sha256": source_file.sha256,
                    },
                )
            )

        # Первичный run создаётся вместе с accepted experiment: так worker не потеряет задачу,
        # если API-процесс упадёт сразу после commit.
        primary_pipeline_run_id = generate_ulid(now=accepted_at)
        self._db.add(
            PipelineRun(
                id=primary_pipeline_run_id,
                experiment_id=promotion_result.experiment_id,
                status=PIPELINE_RUN_STATUS_QUEUED,
                trigger_type=PRIMARY_PIPELINE_TRIGGER_TYPE,
                pipeline_version=settings.pipeline_version,
                params_json={},
            )
        )
        self._db.add(
            ExperimentEvent(
                experiment_id=promotion_result.experiment_id,
                event_type="pipeline_primary_queued",
                from_status="accepted",
                to_status="accepted",
                message="Primary pipeline run queued after upload acceptance",
                details={
                    "pipeline_run_id": primary_pipeline_run_id,
                    "trigger_type": PRIMARY_PIPELINE_TRIGGER_TYPE,
                },
            )
        )
        self._db.add(
            UploadStorageEvent(
                upload_session_id=upload_session.id,
                experiment_id=promotion_result.experiment_id,
                event_type="source_package_accepted",
                status="succeeded",
                bucket=bronze_upload_result.bucket,
                storage_prefix=bronze_upload_result.storage_prefix,
                message="Accepted source package metadata committed to PostgreSQL",
                details={
                    "source_file_count": len(bronze_upload_result.source_files),
                    "validation_report_path": str(promotion_result.validation_report_path),
                },
            )
        )

    def record_orphan_objects(
        self,
        *,
        upload_session: UploadSession,
        bronze_upload_result: BronzeUploadResult,
        reason: str,
        details: dict[str, object],
    ) -> None:
        for source_file in bronze_upload_result.source_files:
            self._db.add(
                UploadOrphanObject(
                    upload_session_id=upload_session.id,
                    experiment_id=upload_session.experiment_id,
                    bucket=source_file.bucket,
                    storage_prefix=bronze_upload_result.storage_prefix,
                    object_key=source_file.object_key,
                    relative_path=source_file.relative_path,
                    size_bytes=source_file.size_bytes,
                    sha256=source_file.sha256,
                    reason=reason,
                    details=details,
                )
            )

    def refresh_upload_session(self, upload_session: UploadSession) -> None:
        self._db.refresh(upload_session)

    def commit(self) -> None:
        self._db.commit()

    def rollback(self) -> None:
        self._db.rollback()


class UploadSessionService:
    """Use cases для upload session API."""

    def __init__(
        self,
        *,
        repository: UploadSessionRepository,
        upload_tmp_root: str | Path,
        experiments_root: str | Path,
        ttl_hours: int,
        bronze_storage: BronzeObjectStorage | None = None,
        now: datetime | None = None,
    ) -> None:
        self._repository = repository
        self._upload_tmp_root = Path(upload_tmp_root)
        self._experiments_root = Path(experiments_root)
        self._ttl_hours = ttl_hours
        self._bronze_storage = bronze_storage or NoopBronzeObjectStorage(
            bucket=settings.minio_bucket_bronze
        )
        self._now = now

    def create_session(
        self,
        *,
        experiment_id: str,
        expected_files: list[str] | None = None,
        client_id: str = "web_ui",
    ) -> UploadSessionView:
        """Создаёт upload session и временную директорию для будущих файлов."""

        self._validate_experiment_id(experiment_id)
        normalized_expected_files = _normalize_expected_files(expected_files)

        if self._repository.has_registered_experiment(experiment_id):
            raise ExperimentAlreadyRegisteredError("experiment_id is already registered")

        active_session = self._repository.find_active_session_by_experiment_id(experiment_id)
        if active_session is not None:
            raise ActiveUploadSessionAlreadyExistsError(
                "active upload session already exists for experiment_id"
            )

        upload_session_id = generate_ulid(now=self._current_time())
        session_dir = build_upload_session_dir(self._upload_tmp_root, upload_session_id)
        session_dir.mkdir(parents=True, exist_ok=False)

        expires_at = self._current_time() + timedelta(hours=self._ttl_hours)
        upload_session = UploadSession(
            id=upload_session_id,
            experiment_id=experiment_id,
            status="uploading",
            tmp_path=str(session_dir),
            client_id=client_id,
            expected_files={"files": normalized_expected_files},
            uploaded_files={"files": []},
            expires_at=expires_at,
        )

        self._repository.add(upload_session)
        try:
            self._repository.commit()
        except IntegrityError as exc:
            self._repository.rollback()
            shutil.rmtree(session_dir, ignore_errors=True)
            raise ActiveUploadSessionAlreadyExistsError(
                "active upload session already exists for experiment_id"
            ) from exc

        return _to_view(upload_session)

    def get_session(self, upload_session_id: str) -> UploadSessionView:
        """Возвращает текущий статус upload session."""

        upload_session = self._get_existing_session(upload_session_id)
        self._expire_if_needed(upload_session)
        return _to_view(upload_session)

    def cancel_session(self, upload_session_id: str) -> UploadSessionView:
        """Отменяет upload session, если её ещё можно отменить."""

        upload_session = self._get_existing_session(upload_session_id)
        self._expire_if_needed(upload_session)

        if upload_session.status == "cancelled":
            return _to_view(upload_session)

        if upload_session.status in FINAL_UPLOAD_SESSION_STATUSES:
            raise UploadSessionStateConflictError(
                f"upload session cannot be cancelled from status {upload_session.status}"
            )

        upload_session.status = "cancelled"
        self._repository.commit()

        return _to_view(upload_session)

    def prepare_file_upload(self, upload_session_id: str, file_name: str) -> UploadFileTarget:
        """Проверяет session и возвращает пути для безопасной потоковой записи."""

        upload_session = self._get_uploading_session(upload_session_id)
        normalized_file_name = self._validate_upload_file_name(upload_session, file_name)

        source_dir = _source_dir(upload_session)
        source_dir.mkdir(parents=True, exist_ok=True)

        final_path = source_dir / normalized_file_name
        part_path = source_dir / f"{normalized_file_name}.part"

        return UploadFileTarget(
            upload_session_id=upload_session.id,
            file_name=normalized_file_name,
            part_path=part_path,
            final_path=final_path,
        )

    def record_uploaded_file(self, upload_session_id: str, file_name: str) -> UploadSessionView:
        """Фиксирует в metadata, что файл успешно записан в upload_tmp."""

        upload_session = self._get_uploading_session(upload_session_id)
        normalized_file_name = self._validate_upload_file_name(upload_session, file_name)
        final_path = _source_dir(upload_session) / normalized_file_name

        if not final_path.is_file():
            raise UploadSessionServiceError("uploaded file is missing after write")

        uploaded_files = set(_files_from_json(upload_session.uploaded_files))
        uploaded_files.add(normalized_file_name)
        upload_session.uploaded_files = {"files": sorted(uploaded_files)}
        self._repository.commit()

        return _to_view(upload_session)

    def complete_session(self, upload_session_id: str) -> UploadCompletionResult:
        """Завершает upload, синхронно валидирует пакет и делает promotion."""

        upload_session = self._get_existing_session_for_complete(upload_session_id)
        self._expire_if_needed(upload_session)

        if upload_session.status == "accepted":
            return UploadCompletionResult(
                upload_session_id=upload_session.id,
                experiment_id=upload_session.experiment_id,
                status=upload_session.status,
                validation_result=None,
                promotion_result=None,
                bronze_upload_result=None,
            )

        if upload_session.status != "uploading":
            raise UploadSessionStateConflictError(
                f"upload session cannot be completed from status {upload_session.status}"
            )

        source_dir = _source_dir(upload_session)

        missing_files = sorted(
            set(REQUIRED_UPLOAD_FILES) - set(_files_from_json(upload_session.uploaded_files))
        )
        if missing_files:
            raise UploadSessionIncompleteError(
                "upload session is missing required files: " + ", ".join(missing_files)
            )

        if _has_unfinished_part_files(source_dir):
            raise UploadSessionIncompleteError("upload session contains unfinished .part files")

        validation_report_path = _validation_report_path(upload_session)
        validation_result = validate_experiment_package(
            source_dir,
            expected_experiment_id=upload_session.experiment_id,
        )
        write_validation_report(validation_result, validation_report_path)

        staging_result = UploadStagingResult(
            upload_session_id=upload_session.id,
            expected_experiment_id=upload_session.experiment_id,
            session_dir=Path(upload_session.tmp_path),
            package_dir=source_dir,
            validation_report_path=validation_report_path,
            validation_result=validation_result,
        )

        now = self._current_time()
        upload_session.completed_at = now

        if not validation_result.is_valid:
            upload_session.status = "failed"
            self._repository.commit()
            return UploadCompletionResult(
                upload_session_id=upload_session.id,
                experiment_id=upload_session.experiment_id,
                status=upload_session.status,
                validation_result=validation_result,
                promotion_result=None,
                bronze_upload_result=None,
            )

        if self._repository.has_registered_experiment(upload_session.experiment_id):
            raise ExperimentAlreadyRegisteredError("experiment_id is already registered")

        # Удаляем остаток промо-папки от прошлой неудачной попытки. Раньше это
        # делалось с ignore_errors=True, поэтому реальный сбой удаления скрывался,
        # а retry падал на promotion с невнятным "experiment directory already
        # exists". Теперь, если папку не удалить, поднимаем понятную ошибку.
        _ensure_experiment_dir_absent(
            build_experiment_dir(self._experiments_root, upload_session.experiment_id)
        )

        try:
            promotion_result = promote_staged_upload(
                staging_result=staging_result,
                experiments_root=self._experiments_root,
            )
        except UploadPromotionError as exc:
            raise UploadSessionStateConflictError(str(exc)) from exc

        try:
            bronze_upload_result = self._bronze_storage.upload_source_package(
                experiment_id=promotion_result.experiment_id,
                source_dir=promotion_result.source_dir,
                source_files=promotion_result.source_files,
            )
        except BronzeStorageError as exc:
            _remove_uncommitted_experiment_dir(promotion_result.experiment_dir)
            self._record_orphan_objects_after_partial_bronze_upload(
                upload_session=upload_session,
                error=exc,
            )
            raise UploadObjectStorageUnavailableError(str(exc)) from exc

        upload_session.status = "accepted"
        self._repository.record_accepted_experiment(
            upload_session=upload_session,
            promotion_result=promotion_result,
            bronze_upload_result=bronze_upload_result,
            validation_result=validation_result,
            accepted_at=now,
        )
        try:
            self._repository.commit()
        except Exception as exc:
            self._repository.rollback()
            self._refresh_after_failed_accept(upload_session)
            self._safely_record_orphan_objects(
                upload_session=upload_session,
                bronze_upload_result=bronze_upload_result,
                reason="postgres_commit_failed",
                details={
                    "error_type": type(exc).__name__,
                    "error_message": str(exc),
                },
            )
            raise UploadDatabaseCommitError(
                "failed to commit accepted upload metadata transaction"
            ) from exc

        # Эксперимент уже принят (objects в MinIO, pipeline run создан, commit
        # прошёл). Неудача удаления локальной копии не должна превращать
        # успешную приёмку в 500 — логируем и оставляем папку для cleanup.
        if not _remove_permanent_source_dir(promotion_result.source_dir):
            logger.warning(
                "accepted upload %s: failed to remove local source copy %s; "
                "experiment is accepted, leaving local copy for later cleanup",
                upload_session.id,
                promotion_result.source_dir,
            )

        return UploadCompletionResult(
            upload_session_id=upload_session.id,
            experiment_id=upload_session.experiment_id,
            status=upload_session.status,
            validation_result=validation_result,
            promotion_result=promotion_result,
            bronze_upload_result=bronze_upload_result,
        )

    def _get_existing_session(self, upload_session_id: str) -> UploadSession:
        upload_session = self._repository.get_by_id(upload_session_id)
        if upload_session is None:
            raise UploadSessionNotFoundError("upload session was not found")
        return upload_session

    def _get_existing_session_for_complete(self, upload_session_id: str) -> UploadSession:
        upload_session = self._repository.get_by_id_for_update(upload_session_id)
        if upload_session is None:
            raise UploadSessionNotFoundError("upload session was not found")
        return upload_session

    def _get_uploading_session(self, upload_session_id: str) -> UploadSession:
        upload_session = self._get_existing_session(upload_session_id)
        self._expire_if_needed(upload_session)

        if upload_session.status != "uploading":
            raise UploadSessionStateConflictError(
                f"upload session cannot accept this operation from status {upload_session.status}"
            )

        return upload_session

    def _expire_if_needed(self, upload_session: UploadSession) -> None:
        """Лениво переводит активную session в expired после TTL."""

        if (
            upload_session.status in ACTIVE_UPLOAD_SESSION_STATUSES
            and upload_session.expires_at <= self._current_time()
        ):
            upload_session.status = "expired"
            self._repository.commit()

    def _current_time(self) -> datetime:
        return self._now or datetime.now(UTC)

    def _refresh_after_failed_accept(self, upload_session: UploadSession) -> None:
        try:
            self._repository.refresh_upload_session(upload_session)
        except Exception:
            # After rollback, retry semantics depend on the database state, not
            # this in-memory object. Avoid masking the original commit failure.
            return

    def _record_orphan_objects_after_partial_bronze_upload(
        self,
        *,
        upload_session: UploadSession,
        error: BronzeStorageError,
    ) -> None:
        """Учитывает объекты, успевшие попасть в MinIO до сбоя bronze upload.

        Без этого частично загруженные объекты остаются в bucket и нигде не
        зафиксированы: cleanup-worker про них не узнает.
        """

        partial_result = error.uploaded
        if partial_result is None or not partial_result.source_files:
            return

        self._safely_record_orphan_objects(
            upload_session=upload_session,
            bronze_upload_result=partial_result,
            reason="bronze_upload_partial_failure",
            details={
                "error_type": type(error).__name__,
                "error_message": str(error),
            },
        )

    def _safely_record_orphan_objects(
        self,
        *,
        upload_session: UploadSession,
        bronze_upload_result: BronzeUploadResult,
        reason: str,
        details: dict[str, object],
    ) -> None:
        try:
            self._repository.record_orphan_objects(
                upload_session=upload_session,
                bronze_upload_result=bronze_upload_result,
                reason=reason,
                details=details,
            )
            self._repository.commit()
        except Exception:
            self._repository.rollback()

    @staticmethod
    def _validate_experiment_id(experiment_id: str) -> None:
        if not EXPERIMENT_ID_PATTERN.fullmatch(experiment_id):
            raise UploadSessionServiceError("experiment_id has invalid format")

    @staticmethod
    def _validate_upload_file_name(upload_session: UploadSession, file_name: str) -> str:
        if file_name not in DEFAULT_UPLOAD_FILES:
            raise UploadSessionServiceError("file_name is not allowed")

        expected_files = set(_files_from_json(upload_session.expected_files))
        if file_name not in expected_files:
            raise UploadSessionServiceError("file_name is not expected for this upload session")

        return file_name


def generate_ulid(*, now: datetime | None = None) -> str:
    """Генерирует ULID без внешней зависимости.

    ULID = 48 бит timestamp в миллисекундах + 80 бит случайности, закодированные
    в Crockford Base32. Такой ID сортируется примерно по времени создания и
    хорошо подходит для upload_session_id.
    """

    current_time = now or datetime.now(UTC)
    timestamp_ms = int(current_time.timestamp() * 1000)
    randomness = int.from_bytes(secrets.token_bytes(10), byteorder="big")
    value = (timestamp_ms << 80) | randomness

    return "".join(
        CROCKFORD_BASE32[(value >> shift) & 0b11111]
        for shift in range(125, -1, -5)
    )


def _normalize_expected_files(expected_files: list[str] | None) -> list[str]:
    files = expected_files or list(DEFAULT_UPLOAD_FILES)
    normalized = sorted(set(files))

    missing_required = set(REQUIRED_UPLOAD_FILES) - set(normalized)
    if missing_required:
        missing = ", ".join(sorted(missing_required))
        raise UploadSessionServiceError(f"expected_files must include required files: {missing}")

    return normalized


def _to_view(upload_session: UploadSession) -> UploadSessionView:
    return UploadSessionView(
        upload_session_id=upload_session.id,
        experiment_id=upload_session.experiment_id,
        status=upload_session.status,
        expected_files=_files_from_json(upload_session.expected_files),
        uploaded_files=_files_from_json(upload_session.uploaded_files),
        expires_at=upload_session.expires_at,
    )


def _source_dir(upload_session: UploadSession) -> Path:
    return Path(upload_session.tmp_path) / UPLOAD_SOURCE_DIR_NAME


def _validation_report_path(upload_session: UploadSession) -> Path:
    return Path(upload_session.tmp_path) / VALIDATION_REPORT_FILE_NAME


def _has_unfinished_part_files(source_dir: Path) -> bool:
    for part_path in source_dir.glob("*.part"):
        final_name = part_path.name.removesuffix(".part")
        if not (source_dir / final_name).is_file():
            return True

    return False


def _remove_permanent_source_dir(source_dir: Path) -> bool:
    """Best-effort удаление локальной source-копии после MinIO upload и DB commit.

    Возвращает True, если копии больше нет. На этом этапе эксперимент уже принят,
    поэтому сбой удаления не должен ронять ответ — вызывающий код его логирует.
    """

    try:
        shutil.rmtree(source_dir)
        return True
    except FileNotFoundError:
        return True
    except OSError:
        return False


def _ensure_experiment_dir_absent(experiment_dir: Path) -> None:
    """Гарантирует отсутствие промо-папки перед promotion.

    Удаляет остаток от прошлой неудачной попытки. Если папку реально не удалить,
    поднимает понятную ошибку вместо того, чтобы дать promotion упасть позже с
    невнятным "experiment directory already exists".
    """

    try:
        shutil.rmtree(experiment_dir)
    except FileNotFoundError:
        pass
    except OSError as exc:
        raise UploadLocalCleanupError(
            f"stale local experiment directory could not be removed before retry: {experiment_dir}"
        ) from exc

    if experiment_dir.exists():
        raise UploadLocalCleanupError(
            f"stale local experiment directory still present after cleanup: {experiment_dir}"
        )


def _remove_uncommitted_experiment_dir(experiment_dir: Path) -> None:
    """Best-effort удаление local promotion, если upload не дошёл до accepted commit.

    Сбой удаления здесь не критичен: следующая попытка пройдёт через
    `_ensure_experiment_dir_absent`, который при реальной проблеме поднимет ошибку.
    """

    try:
        shutil.rmtree(experiment_dir)
    except FileNotFoundError:
        return
    except OSError:
        logger.warning(
            "failed to remove uncommitted local experiment directory: %s", experiment_dir
        )


def _files_from_json(value: dict[str, object] | None) -> list[str]:
    if not value:
        return []

    raw_files = value.get("files", [])
    if not isinstance(raw_files, list):
        return []

    return sorted(file_name for file_name in raw_files if isinstance(file_name, str))
